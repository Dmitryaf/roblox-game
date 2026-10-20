--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
-- Run current, unchanged source; only Roblox module/value lookups are injected.
local Config = luau.load(fs.readFile("src/server/config/Warrior.luau"))()
local Domain = luau.load(fs.readFile("src/server/domain/combat/SwordSwing.luau"))()
local domainModule = {}
local Service = luau.load(fs.readFile("src/server/application/combat/MeleeService.luau"), {environment = {
    Vector3 = Vector3, script = {Parent = {Parent = {Parent = {domain = {combat = {SwordSwing = domainModule}}}}}},
    require = function(module) assert(module == domainModule); return Domain end,
}})()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
    local f = {events = {}, damages = {}, impacts = {}, members = {"enemy"}, living = true,
        outcomes = {enemy = true}, points = {enemy = Vector3.new(5, 4, 0)}, now = 0}
    f.service = Service.new({
        alive = function() return f.living end,
        origin = function() return Vector3.new(0, 4, 0) end,
        face = function() return true end,
        targets = function() return table.clone(f.members) end,
        damage = function(owner, target, amount)
            table.insert(f.damages, {owner = owner, target = target, amount = amount})
            if f.onDamage then f.onDamage(owner, target) end
            return f.outcomes[target]
        end,
        impact = function(target) table.insert(f.impacts, target); return f.points[target] end,
        emit = function(event) table.insert(f.events, event) end,
    }, Config)
    f.service.join(1, 10)
    function f.cast(life, at) return f.service.cast(1, life or 10, Vector3.xAxis, at or 0) end
    function f.contacts()
        local result = {}; for _, event in f.events do if event.kind == "contact" then table.insert(result, event) end end
        return result
    end
    return f
end

test("a committed actual hit emits one authoritative contact at the target point", function()
    local f = fixture(); assert(f.cast()); f.service.step(0.299)
    assert(#f.damages == 0 and #f.impacts == 0 and #f.contacts() == 0)
    f.service.step(0.3); f.service.step(0.4)
    assert(#f.damages == 1 and f.damages[1].amount == 20 and f.damages[1].target == "enemy")
    assert(#f.impacts == 1 and #f.contacts() == 1)
    local contact, prepared = f.contacts()[1], f.events[1]
    assert(contact.contactId == 1 and contact.owner == 1 and contact.life == 10 and contact.swingId == prepared.swingId)
    assert(contact.position == Vector3.new(5, 4, 0) and contact.direction == Vector3.xAxis)
    assert(contact.startedAt == 0 and contact.hitAt == 0.3 and contact.expiresAt == 0.75 and contact.readyAt == 0.9)
    assert(f.events[2].kind == "struck" and f.events[3] == contact)
    assert(f.service.snapshot(1).active[1].kind == "struck", "A feedback event replaced gameplay phase")
end)
test("blocked false and legacy nil damage never fabricate impact feedback", function()
    for _, outcome in {"false", "nil"} do
        local f = fixture(); f.outcomes.enemy = if outcome == "false" then false else nil
        assert(f.cast()); f.service.step(0.3)
        assert(#f.damages == 1 and #f.impacts == 0 and #f.contacts() == 0)
        assert(f.service.snapshot(1).active[1].kind == "struck")
    end
    local missing = fixture(); missing.points.enemy = nil
    assert(missing.cast()); missing.service.step(0.3)
    assert(#missing.damages == 1 and #missing.impacts == 1 and #missing.contacts() == 0)
end)
test("an empty arc is still a miss without damage, target lookup or contact", function()
    local f = fixture(); f.members = {}; assert(f.cast()); f.service.step(0.3); f.service.step(0.75)
    assert(#f.damages == 0 and #f.impacts == 0 and #f.contacts() == 0)
    assert(f.events[2].kind == "struck" and f.events[3].kind == "ended")
end)
test("deduplication emits one contact per actual target and resets IDs for the next swing", function()
    local f = fixture(); f.members = {"enemy", "enemy", "blocked", "second", "second"}
    f.outcomes.blocked, f.outcomes.second, f.points.second = false, true, Vector3.new(4, 4, 2)
    assert(f.cast()); f.service.step(0.3); f.service.step(0.31)
    assert(#f.damages == 3 and #f.impacts == 2 and #f.contacts() == 2)
    assert(f.contacts()[1].contactId == 1 and f.contacts()[2].contactId == 2)
    assert(f.contacts()[2].position == f.points.second)
    local oldId = f.contacts()[1].swingId
    assert(f.cast(10, 0.9)); f.service.step(1.2)
    assert(#f.contacts() == 4 and f.contacts()[3].contactId == 1 and f.contacts()[4].contactId == 2)
    assert(f.contacts()[3].swingId ~= oldId)
end)
test("death, pause and life reset during windup suppress later hits and contact", function()
    for _, cancel in {"die", "pause", "join", "leave", "destroy"} do
        local f = fixture(); assert(f.cast())
        if cancel == "pause" then f.service.pause(1, 0.1)
        elseif cancel == "join" then f.service.join(1, 11)
        elseif cancel == "destroy" then f.service.destroy()
        else f.service[cancel](1) end
        f.service.step(0.3); f.service.step(1)
        assert(#f.damages == 0 and #f.impacts == 0 and #f.contacts() == 0, cancel .. " emitted a late hit")
    end
end)
test("reentrant death, pause or reset from damage cannot emit a stale contact or hit the next target", function()
    for _, cancel in {"die", "pause", "join", "leave"} do
        local f = fixture(); f.members = {"enemy", "second"}; f.outcomes.second = true; f.points.second = Vector3.zAxis
        f.onDamage = function()
            if cancel == "pause" then f.service.pause(1, 0.3)
            elseif cancel == "join" then f.service.join(1, 11)
            else f.service[cancel](1) end
        end
        assert(f.cast()); f.service.step(0.3); f.service.step(0.4)
        assert(#f.damages == 1 and #f.contacts() == 0, cancel .. " emitted stale/repeated contact")
    end
end)
test("a new life rejects old cast requests and only its new swing can route contact", function()
    local f = fixture(); assert(f.cast()); local oldSwing = f.events[1].swingId
    f.service.join(1, 11)
    local ok, reason = f.cast(10, 0.3)
    assert(not ok and reason == "stale_life" and #f.damages == 0 and #f.contacts() == 0)
    assert(f.cast(11, 0.3)); f.service.step(0.6)
    assert(#f.damages == 1 and #f.contacts() == 1)
    assert(f.contacts()[1].life == 11 and f.contacts()[1].swingId ~= oldSwing)
end)
test("the optional impact port preserves legacy damage callers without feedback", function()
    local events, damages = {}, 0
    local legacy = Service.new({alive = function() return true end, origin = function() return Vector3.zero end,
        face = function() return true end, targets = function() return {"enemy"} end,
        damage = function() damages += 1; return true end,
        emit = function(event) table.insert(events, event) end}, Config)
    legacy.join(1, 10); assert(legacy.cast(1, 10, Vector3.xAxis, 0)); legacy.step(0.3)
    assert(damages == 1 and #events == 2 and events[2].kind == "struck")
end)

local function signal()
    local callbacks, event = {}, {}
    function event:Connect(callback)
        local c = {Connected = true}; function c:Disconnect() self.Connected = false end
        table.insert(callbacks, {c, callback}); return c
    end
    function event.fire(...) for _, entry in callbacks do if entry[1].Connected then entry[2](...) end end end
    return event
end
local function controller()
    local f = {now = 100, sent = {}, events = {}, frames = signal(), messages = signal()}
    local character = {}; function character:GetAttribute() return "warrior" end
    local game = {}; function game:GetService() return {RenderStepped = f.frames} end
    local workspace = {}; function workspace:GetServerTimeNow() return f.now end
    local remote = {OnClientEvent = f.messages}; function remote:FireServer(value) table.insert(f.sent, value) end
    local hud = {show = function(status) f.status = status end, destroy = function() end}
    local effects = {event = function(event) table.insert(f.events, event) end, sync = function() end,
        step = function() end, destroy = function() end}
    local Controller = luau.load(fs.readFile("src/client/controllers/MeleeController.luau"), {
        environment = {game = game, workspace = workspace},
    })()
    f.stop = Controller.start({UserId = 1, Character = character}, remote, hud, effects,
        function(_, attack) f.attack = attack; return function() end end)
    function f.frame() f.now += 0.11; f.frames.fire() end
    function f.snapshot(life)
        f.messages.fire({kind = "snapshot", state = {life = life, alive = true, suspended = false, readyAt = 0, active = {}}})
    end
    function f.event(kind, life, id, ready, owner)
        return {kind = kind, owner = owner or 1, life = life, swingId = id, readyAt = ready or 101,
            contactId = 1, position = Vector3.xAxis, expiresAt = 100.75}
    end
    f.snapshot(10)
    return f
end

test("contact cannot replace a newer local phase, swing ID or cooldown", function()
    local f = controller()
    f.messages.fire(f.event("preparing", 10, 20)); f.frame(); assert(string.find(f.status, "Подготовка"))
    f.messages.fire(f.event("contact", 10, 19, 999)); f.frame()
    assert(string.find(f.status, "Подготовка") and #f.events == 2 and f.events[2].kind == "contact")
    f.messages.fire(f.event("struck", 10, 20)); f.frame()
    f.messages.fire(f.event("contact", 10, 20, 999)); f.frame(); assert(string.find(f.status, "Возвращаем"))
    f.messages.fire(f.event("ended", 10, 20)); f.frame(); assert(string.find(f.status, "Восстановление"))
    f.now = 101.1; f.frame(); assert(not string.find(f.status, "Восстановление"))
    f.stop()
end)
test("contact is presentation-only while an attack reply is pending", function()
    local f = controller(); f.attack(Vector3.xAxis); local request = f.sent[#f.sent]
    f.messages.fire(f.event("contact", 10, 99, 999)); f.frame()
    assert(string.find(f.status, "подтверждения"))
    f.attack(Vector3.xAxis); assert(f.sent[#f.sent] == request)
    f.stop()
end)
test("stale local and foreign contact lives cannot route feedback into a newer life", function()
    local f = controller(); f.snapshot(11)
    f.messages.fire(f.event("contact", 10, 1)); f.messages.fire(f.event("contact", 12, 2))
    assert(#f.events == 0)
    f.messages.fire(f.event("contact", 3, 30, 101, 2))
    f.messages.fire(f.event("contact", 2, 29, 101, 2))
    assert(#f.events == 1 and f.events[1].owner == 2 and f.events[1].life == 3)
    f.stop()
end)
print(string.format("%d Melee contact service/controller contracts passed", total))
