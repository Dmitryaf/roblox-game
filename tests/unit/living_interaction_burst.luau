--!strict
-- Real burst/material code; Roblox instance/audio calls are simulated boundary objects.
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local V, C = rb.Vector3, rb.CFrame
local function fixture()
    local objects, expiries = {}, {}
    local time = 100
    local instance = {}
    function instance.new(kind)
        assert(kind ~= "LinearVelocity" and kind ~= "VectorForce", "Cosmetic burst created a physical mover")
        local object = { ClassName = kind, Attributes = {}, played = 0 }
        function object:SetAttribute(key, value) self.Attributes[key] = value end
        function object:Play() self.played += 1 end
        function object:Destroy()
            for _, child in objects do
                local ancestor = child.Parent
                while ancestor do
                    if ancestor == self then child.destroyed = true; break end
                    ancestor = ancestor.Parent
                end
            end
            self.destroyed = true
        end
        table.insert(objects, object); return object
    end
    local game = { GetService = function(_, name)
        if name == "Debris" then return { AddItem = function(_, object, duration) table.insert(expiries, { object, duration }) end } end
        return { Shared = { presentation = { ArrowStyle = "Style" } } }
    end }
    local matter = luau.load(fs.readFile("src/client/presentation/ChaosMatter.luau"), { environment = {
        game = game, Instance = instance, Enum = rb.Enum,
        require = function() return {} end,
    } })()
    local burst = luau.load(fs.readFile("src/client/presentation/LivingInteractionBurst.luau"), { environment = {
        game = game, Instance = instance, Enum = rb.Enum,
        Vector3 = V, CFrame = C, Color3 = rb.Color3,
        workspace = { GetServerTimeNow = function() return time end },
        script = { Parent = { ChaosMatter = "Matter" } },
        require = function() return matter end,
    } })()
    return burst, objects, expiries
end
for _, kind in { "redirect", "gather", "raise", "shatter" } do
    local Burst, objects, expiries = fixture()
    local event = { position = V.new(4, 2, -7), direction = -V.zAxis, areaId = 3, castId = 4 }
    local handle = Burst.new({ Parent = nil }, kind, event, 100.7)
    assert(#expiries == 1 and expiries[1][2] <= .81)
    handle.step(100.2); handle.step(100.69)
    local parts, sounds = 0, 0
    for _, object in objects do
        if object.ClassName == "Part" then
            parts += 1
            assert(object.Anchored and not object.CanCollide and not object.CanTouch and not object.CanQuery)
            assert(not object.CastShadow and object.CFrame ~= nil or object.Name == "CueAnchor")
        elseif object.ClassName == "Sound" then
            sounds += 1; assert(object.played == 1 and object.RollOffMaxDistance == 95 and object.Volume <= .75)
            assert(object.SoundId == "rbxasset://sounds/living-magic-v1/" .. kind .. ".wav")
        end
    end
    assert(parts <= 22 and sounds == 1)
    handle.destroy(); handle.destroy(); handle.step(101)
    for _, object in objects do assert(object.destroyed, object.ClassName) end
    print("PASS harmless bounded " .. kind .. " geometry and owned audio cleanup")
end
