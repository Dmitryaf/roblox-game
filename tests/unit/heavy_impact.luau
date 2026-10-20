--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame, Color3 = rb.Vector3, rb.CFrame, rb.Color3
local source = fs.readFile("src/client/presentation/MeleeImpact.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
    local f = {time = 100, created = {}, players = {}}
    local function instance(className)
        local values, children = {ClassName = className, Transparency = 0}, {}
        local object
        object = setmetatable({}, {
            __index = function(_, key)
                if key == "Destroy" then return function()
                    for _, child in children do if child.Parent == object then child:Destroy() end end
                    values.Parent, values.destroyed = nil, true
                end end
                if key == "IsA" then return function(_, name)
                    return name == className or (name == "BasePart" and className == "Part")
                end end
                if key == "Play" then return function() values.played = true end end
                if key == "add" then return function(_, child) table.insert(children, child) end end
                return values[key]
            end,
            __newindex = function(_, key, value)
                values[key] = value
                if key == "Parent" and value then value:add(object) end
            end,
        })
        table.insert(f.created, object)
        return object
    end
    f.parent = instance("Folder")
    local function player(owner)
        local character = {life = 10, classId = "warrior"}
        local humanoid = {Health = 100}
        local root = instance("Part"); root.Anchored = false
        function character:GetAttribute(name) return if name == "CombatLife" then self.life else self.classId end
        function character:FindFirstChildOfClass(name) assert(name == "Humanoid"); return self.humanoid end
        function character:FindFirstChild(name) assert(name == "HumanoidRootPart"); return self.root end
        character.humanoid, character.root = humanoid, root
        f.players[owner] = {Character = character}
        return character
    end
    f.character = player(1); f.other = player(2)
    local players = {}; function players:GetPlayerByUserId(owner) return f.players[owner] end
    local game = {}; function game:GetService(name) assert(name == "Players"); return players end
    local workspace = {}; function workspace:GetServerTimeNow() return f.time end
    f.effect = luau.load(source, {environment = {game = game, workspace = workspace,
        Instance = {new = instance}, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3,
        Enum = {Material = {Neon = "Neon"}, PartType = {Ball = "Ball"}},
    }})().new(f.parent, "heavy")
    function f.event(id, contact, owner)
        return {owner = owner or 1, life = 10, swingId = id or 1, contactId = contact or 1,
            position = Vector3.new(5, 4, 3), direction = Vector3.xAxis, hitAt = f.time}
    end
    function f.named(name, live)
        local found = {}; for _, object in f.created do
            if object.Name == name and (not live or object.Parent ~= nil) then table.insert(found, object) end
        end; return found
    end
    function f.step(delta) f.time += delta; f.effect.step(f.time) end
    return f
end

test("one correlated contact emits once while distinct contacts and owners remain independent", function()
    local f = fixture(); local event = f.event()
    f.effect.hit(event); local count = #f.created; f.effect.hit(event)
    assert(#f.created == count and #f.named("ConfirmedHeavyImpact", true) == 1)
    assert(#f.named("HeavyContactSpark", true) == 16 and #f.named("HeavyContactFlash", true) == 1)
    local flash = f.named("HeavyContactFlash", true)[1]
    assert(flash.CFrame.Position == event.position)
    local sound = f.named("HeavyContactWeight", true)[1]
    assert(sound.played and sound.Parent == flash and sound.PlaybackSpeed == 0.82)
    f.effect.hit(f.event(1, 2)); f.effect.hit(f.event(1, 1, 2))
    assert(#f.named("ConfirmedHeavyImpact", true) == 3)
    f.effect.destroy()
end)
test("impact geometry is cosmetic and follows finite visible movement and fading", function()
    local f = fixture(); f.effect.hit(f.event())
    local sparks = f.named("HeavyContactSpark", true); local before = sparks[1].CFrame.Position
    for _, object in f.created do if object.Name == "HeavyContactSpark" or object.Name == "HeavyContactFlash" then
        assert(object.Anchored and object.Massless and not object.CanCollide and not object.CanTouch and not object.CanQuery)
    end end
    f.step(0.05)
    assert((sparks[1].CFrame.Position - before).Magnitude > 0.1 and sparks[1].Transparency > 0 and sparks[1].Transparency < 1)
    f.step(0.10); assert(f.named("HeavyContactFlash", true)[1].Transparency == 1)
    f.step(0.40); assert(#f.named("ConfirmedHeavyImpact", true) == 0 and #f.named("HeavyContactWeight", true) == 0)
end)
test("death, life/class changes, pause and missing current bodies remove feedback on the next update", function()
    for _, cancel in {"dead", "life", "class", "pause", "missing_root", "missing_character", "missing_player"} do
        local f = fixture(); f.effect.hit(f.event())
        if cancel == "dead" then f.character.humanoid.Health = 0
        elseif cancel == "life" then f.character.life = 11
        elseif cancel == "class" then f.character.classId = "warlock"
        elseif cancel == "pause" then f.character.root.Anchored = true
        elseif cancel == "missing_root" then f.character.root = nil
        elseif cancel == "missing_character" then f.players[1].Character = nil
        else f.players[1] = nil end
        f.step(0.01)
        assert(#f.named("ConfirmedHeavyImpact", true) == 0 and #f.named("HeavyContactSpark", true) == 0, cancel)
        f.effect.destroy(); f.effect.destroy()
    end
    local f = fixture(); f.effect.hit(f.event(1)); f.effect.hit(f.event(2)); f.effect.hit(f.event(1, 1, 2))
    f.effect.cancel(1, 1); f.effect.cancel(1, 1)
    assert(#f.named("ConfirmedHeavyImpact", true) == 2)
    f.effect.destroy(); f.effect.destroy(); f.step(1)
    assert(#f.named("ConfirmedHeavyImpact", true) == 0 and #f.named("HeavyContactWeight", true) == 0)
end)
test("stale or incomplete contacts never allocate and expired contacts cannot replay after retirement", function()
    local f = fixture(); local before = #f.created
    local stale = f.event(); stale.hitAt = f.time - 0.351; f.effect.hit(stale)
    local missingPoint = f.event(); missingPoint.position = nil; f.effect.hit(missingPoint)
    local missingId = f.event(); missingId.contactId = nil; f.effect.hit(missingId)
    assert(#f.created == before)
    local event = f.event(); f.effect.hit(event); f.step(1.1)
    assert(#f.named("ConfirmedHeavyImpact", true) == 0)
    before = #f.created; f.effect.hit(event); assert(#f.created == before)
    f.effect.destroy()
end)
test("a burst flood retains at most twelve live effects and evicts the oldest before allocating another", function()
    local f = fixture(); f.effect.hit(f.event(1)); local first = f.named("ConfirmedHeavyImpact", true)[1]
    for id = 2, 30 do f.time += 0.001; f.effect.hit(f.event(id)) end
    assert(first.Parent == nil and #f.named("ConfirmedHeavyImpact", true) == 12)
    assert(#f.named("HeavyContactSpark", true) == 192 and #f.named("HeavyContactFlash", true) == 12)
    f.step(0.53)
    assert(#f.named("ConfirmedHeavyImpact", true) == 0 and #f.named("HeavyContactSpark", true) == 0)
    f.effect.destroy()
end)
print(string.format("%d HeavyImpact presentation lifecycle tests passed", total))
