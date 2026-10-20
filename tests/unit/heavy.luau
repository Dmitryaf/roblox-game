--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
local Prefix = "../../build/test-source/server/"
local Domain = require(Prefix .. "domain/combat/SwordSwing")
local Melee = luau.load(fs.readFile("build/test-source/server/application/combat/MeleeService.luau"), {environment = {
    Vector3 = Vector3, require = function(path) assert(path == "../../domain/combat/SwordSwing"); return Domain end,
}})()
local Slow = require(Prefix .. "application/combat/TimedSlowService")
local Heavy = luau.load(fs.readFile("build/test-source/server/application/combat/HeavyStrikeService.luau"), {environment = {
    require = function(path)
        if path == "./MeleeService" then return Melee end
        assert(path == "./TimedSlowService"); return Slow
    end,
}})()
local Dash = luau.load(fs.readFile("build/test-source/server/application/combat/DashService.luau"), {environment = {Vector3 = Vector3}})()
local Arrow = require(Prefix .. "application/combat/ArrowService")
local Hands = require(Prefix .. "application/combat/HandsService")
local Warlock = require(Prefix .. "application/combat/WarlockCombat")
local ClassCombat = require(Prefix .. "application/combat/ClassCombat")
local MatchCombat = require(Prefix .. "application/combat/MatchCombat")
local Config = require(Prefix .. "config/Heavy")
local NormalConfig = require(Prefix .. "config/Warrior")
local DashConfig = require(Prefix .. "config/Dash")
local ArrowConfig = require(Prefix .. "config/Warlock")
local HandsConfig = require(Prefix .. "config/Hands")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a-b) < 0.000001, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture()
    local f = {now = 0, classes = {[1] = "warrior", [2] = "warrior", [3] = "warlock", [4] = "warrior"},
        living = {[1] = true, [2] = true, [3] = true, [4] = true}, lives = {[1] = 10, [2] = 20, [3] = 30, [4] = 40},
        events = {heavy = {}, melee = {}, dash = {}}, damages = {}, queries = {}, faces = {}, starts = {}, stops = {},
        slowEvents = {}, slows = {}, canAct = true, protected = false, ticks = 0, outcome = true}
    f.victim = {owner = 4, life = 40, health = 100, position = Vector3.new(5, 4, 0)}
    f.members = {f.victim, f.victim}
    local function alive(owner) return f.living[owner] == true end
    local function origin(owner) return if f.noOrigin then nil else Vector3.new(owner, 4, 0) end
    local function emit(kind) return function(event) table.insert(f.events[kind], event) end end
    local function ports(kind)
        return {alive = alive, origin = origin, face = function(owner, direction)
            table.insert(f.faces, {owner = owner, direction = direction}); return not f.badFace end,
            targets = function(owner, direction, range, arc)
                table.insert(f.queries, {kind = kind, owner = owner, direction = direction, range = range, arc = arc})
                return table.clone(f.members)
            end,
            damage = function(owner, target, amount)
                table.insert(f.damages, {kind = kind, owner = owner, target = target, amount = amount})
                if f.onDamage then f.onDamage(owner, target) end
                if f.outcome == true then target.health -= amount end
                return f.outcome
            end,
            impact = function(target) return target.position end,
            token = function(target) return if target.health > 0 then target.life else nil end,
            targetOwner = function(target) return target.owner end,
            slow = function(target, amount) f.slows[target] = amount; table.insert(f.slowEvents, {target = target, amount = amount}) end,
            emit = emit(kind)}
    end
    local heavy, melee = Heavy.new(ports("heavy"), Config), Melee.new(ports("melee"), NormalConfig)
    local dash = Dash.new({alive = alive,
        start = function(owner, direction, distance, duration)
            table.insert(f.starts, {owner = owner, direction = direction, duration = duration}); return origin(owner), distance, nil end,
        stop = function(owner) table.insert(f.stops, owner) end, emit = emit("dash")}, DashConfig)
    local arrow = Arrow.new({alive = alive, origin = origin, sweep = function() return nil, nil end,
        damage = function() end, landing = function(_, point) return point end, move = function() end, emit = function() end}, ArrowConfig)
    local hands = Hands.new({alive = alive, placement = function(_, point) return point end, targets = function() return {} end,
        damage = function() end, slow = function() end, emit = function() end}, HandsConfig)
    f.combat = ClassCombat.new(Warlock.new(arrow, hands), melee, function(owner) return f.classes[owner] end, dash, heavy)
    for owner, life in f.lives do f.combat.join(owner, life) end
    f.guarded = MatchCombat.new(f.combat, {canAct = function() return f.canAct end}, function()
        f.ticks += 1; f.combat.step(f.now)
    end, function() return if f.protected then "spawn_protected" else nil end)
    function f.call(action, owner, at, life)
        owner, f.now = owner or 1, at or f.now
        return f.guarded[action](owner, life or f.lives[owner], Vector3.xAxis, f.now)
    end
    function f.step(at) f.now = at; f.combat.step(at) end
    function f.state(action, owner)
        local key = ({heavyStrike = "heavySnapshot", swing = "meleeSnapshot", dash = "dashSnapshot"})[action]
        return f.combat[key](owner or 1)
    end
    function f.contacts()
        local result = {}; for _, event in f.events.heavy do if event.kind == "contact" then table.insert(result, event) end end
        return result
    end
    return f
end

test("heavy tuning, event style and snapshots describe one authoritative prepared action", function()
    assert(Config.windup == 0.65 and Config.recovery == 0.6 and Config.cooldown == 8 and Config.damage == 25)
    assert(Config.slowMultiplier == 0.6 and Config.slowDuration == 2 and Config.range == 7 and Config.arcDegrees == 100)
    local f = fixture(); assert(f.call("heavyStrike"))
    local event = f.events.heavy[1]
    assert(event.style == "heavy" and event.kind == "preparing" and event.owner == 1 and event.life == 10)
    near(event.hitAt, 0.65); near(event.expiresAt, 1.25); near(event.readyAt, 8)
    local snapshot = f.guarded.heavySnapshot(1)
    assert(snapshot.life == 10 and snapshot.active[1].style == "heavy" and snapshot.active[1].swingId == event.swingId)
    assert(f.ticks == 1 and #f.damages == 0 and #f.slowEvents == 0)
end)
test("confirmed impact deals twenty-five once per unique target and then applies the timed slow", function()
    local f = fixture(); assert(f.call("heavyStrike")); f.step(0.649)
    assert(#f.damages == 0 and #f.slowEvents == 0)
    f.step(0.65); f.step(0.8)
    assert(#f.damages == 1 and f.damages[1].amount == 25 and f.victim.health == 75)
    assert(f.slows[f.victim] == 0.6 and #f.slowEvents == 1 and #f.contacts() == 1)
    assert(f.contacts()[1].style == "heavy" and f.contacts()[1].position == f.victim.position)
    assert(f.state("heavyStrike").active[1].kind == "struck" and f.queries[1].range == 7 and f.queries[1].arc == 100)
    f.step(2.649); assert(f.slows[f.victim] == 0.6)
    f.step(2.65); assert(f.slows[f.victim] == 1 and #f.slowEvents == 2)
end)
test("misses and damage-adapter refusals including ForceField false never apply slow or fake contact", function()
    for _, outcome in {"miss", "false", "legacy_nil"} do
        local f = fixture()
        if outcome == "miss" then f.members = {}
        elseif outcome == "false" then f.outcome = false
        else f.outcome = nil end
        assert(f.call("heavyStrike")); f.step(0.65)
        assert(f.victim.health == 100 and #f.slowEvents == 0 and #f.contacts() == 0)
        assert(#f.damages == (if outcome == "miss" then 0 else 1))
    end
end)
test("all six ordered LMB E Q overlaps reject busy without spending the refused action's cooldown", function()
    for _, first in {"swing", "dash", "heavyStrike"} do
        for _, second in {"swing", "dash", "heavyStrike"} do
            if first == second then continue end
            local f = fixture(); assert(f.call(first, 1, 0))
            local ok, reason = f.call(second, 1, 0.1)
            assert(not ok and reason == "busy", first .. " did not exclude " .. second)
            assert(f.state(second).readyAt == 0)
            assert(#f.state(second).active == 0)
        end
    end
end)
test("another warrior may act concurrently without inheriting the first warrior's busy state", function()
    local f = fixture(); assert(f.call("heavyStrike", 1)); assert(f.call("swing", 2, 0.1))
    assert(f.state("heavyStrike", 2).readyAt == 0 and f.state("swing", 1).readyAt == 0)
    local other = fixture(); assert(other.call("heavyStrike", 1)); assert(other.call("heavyStrike", 2, 0.1))
    near(other.state("heavyStrike", 1).readyAt, 8); near(other.state("heavyStrike", 2).readyAt, 8.1)
end)
test("heavy cooldown is independent from normal sword and dash after their active windows", function()
    local f = fixture(); assert(f.call("heavyStrike", 1, 0)); assert(f.call("swing", 1, 1.25))
    near(f.state("heavyStrike").readyAt, 8); near(f.state("swing").readyAt, 2.15)
    assert(f.call("dash", 1, 2)); near(f.state("dash").readyAt, 7)
    local ok, reason = f.call("heavyStrike", 1, 2.3); assert(not ok and reason == "cooldown")
    assert(f.call("heavyStrike", 1, 8))
end)
test("wrong class, stale life, match pause and spawn protection reject before spending heavy resources", function()
    for _, failure in {"wrong_class", "stale_life", "paused", "spawn_protected"} do
        local f = fixture(); local owner, life = 1, 10
        if failure == "wrong_class" then owner, life = 3, 30
        elseif failure == "stale_life" then life = 9
        elseif failure == "paused" then f.canAct = false
        else f.protected = true end
        local ok, reason = f.call("heavyStrike", owner, 0, life)
        assert(not ok and reason == failure)
        assert(f.state("heavyStrike", owner).readyAt == 0 and #f.faces == 0 and #f.damages == 0 and #f.slowEvents == 0)
    end
end)
test("invalid facing and unsupported current position do not spend heavy cooldown", function()
    for _, field in {"badFace", "noOrigin"} do
        local f = fixture(); f[field] = true
        local ok, reason = f.call("heavyStrike")
        assert(not ok and reason == "invalid_position" and f.state("heavyStrike").readyAt == 0)
        assert(#f.damages == 0 and #f.slowEvents == 0)
    end
end)
test("death pause new life leave or destruction during windup cancel future damage and slow", function()
    for _, method in {"die", "pause", "join", "leave", "destroy"} do
        local f = fixture(); assert(f.call("heavyStrike"))
        if method == "pause" then f.combat.pause(1, 0.2)
        elseif method == "join" then f.combat.join(1, 11)
        elseif method == "destroy" then f.combat.destroy()
        else f.combat[method](1) end
        f.step(0.65); f.step(3)
        assert(#f.damages == 0 and #f.slowEvents == 0 and #f.contacts() == 0)
    end
end)
test("ending the caster's life or participation immediately clears its existing slow contribution", function()
    for _, method in {"die", "pause", "join", "leave"} do
        local f = fixture(); assert(f.call("heavyStrike")); f.step(0.65); assert(f.slows[f.victim] == 0.6)
        if method == "pause" then f.combat.pause(1, 0.8)
        elseif method == "join" then f.combat.join(1, 11)
        else f.combat[method](1) end
        assert(f.slows[f.victim] == 1)
        local before = #f.slowEvents; f.step(4); assert(#f.slowEvents == before)
    end
end)
test("victim pause clears incoming heavy slow while its unchanged life remains current", function()
    local f = fixture(); assert(f.call("heavyStrike")); f.step(0.65)
    f.combat.pause(4, 0.8)
    assert(f.victim.life == 40 and f.slows[f.victim] == 1)
    f.combat.resume(4, 1); f.step(2); assert(f.slows[f.victim] == 1)
end)
test("victim life reset never applies an old slow to a reused target object", function()
    local f = fixture(); assert(f.call("heavyStrike")); f.step(0.65)
    f.victim.life = 41; f.slows[f.victim] = 1 -- World.place clears sources before the new CombatLife.
    f.lives[4] = 41; f.combat.join(4, 41); f.step(1)
    assert(f.slows[f.victim] == 1)
    assert(f.call("heavyStrike", 2, 1)); f.step(1.65); assert(f.slows[f.victim] == 0.6)
    f.step(2.65); assert(f.slows[f.victim] == 0.6, "The old victim life expired the new contribution")
    f.step(3.65); assert(f.slows[f.victim] == 1)
end)
test("overlapping heavy casters preserve the strongest contribution when one leaves", function()
    local f = fixture(); assert(f.call("heavyStrike", 1, 0)); assert(f.call("heavyStrike", 2, 0.1))
    f.step(0.65); f.step(0.75)
    assert(f.slows[f.victim] == 0.6 and #f.slowEvents == 1, "Heavy slows multiplied or duplicated source application")
    f.combat.leave(1); assert(f.slows[f.victim] == 0.6 and #f.slowEvents == 1)
    f.step(2.75); assert(f.slows[f.victim] == 1 and #f.slowEvents == 2)
end)
test("paused cooldown resumes with the same remaining time and stale caster life cannot route another action", function()
    local f = fixture(); assert(f.call("heavyStrike")); f.combat.pause(1, 0.2)
    local ok, reason = f.call("heavyStrike", 1, 1); assert(not ok and reason == "paused")
    f.combat.resume(1, 10); near(f.state("heavyStrike").readyAt, 17.8)
    ok, reason = f.call("heavyStrike", 1, 17.799); assert(not ok and reason == "cooldown")
    f.combat.join(1, 11); f.lives[1] = 11
    ok, reason = f.call("heavyStrike", 1, 18, 10); assert(not ok and reason == "stale_life")
    assert(f.call("heavyStrike", 1, 18, 11))
end)
test("reentrant caster reset from actual damage prevents a stale on-hit slow and contact", function()
    local f = fixture(); f.onDamage = function() f.combat.join(1, 11) end
    assert(f.call("heavyStrike")); f.step(0.65)
    assert(#f.damages == 1 and f.victim.health == 75 and #f.slowEvents == 0 and #f.contacts() == 0)
end)
print(string.format("%d HeavyStrike/ClassCombat/MatchCombat real-service contracts passed", total))
