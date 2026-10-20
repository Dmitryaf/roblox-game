--!strict
-- Registered Studio rigs exercise real world speed composition, not live network players.
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local World = require(modules.adapters.world.CombatWorld)
local Heavy = require(modules.application.combat.HeavyStrikeService)
local Hands = require(modules.application.combat.HandsService)
local heavyConfig = require(modules.config.Heavy)
local handsConfig = require(modules.config.Hands)
local world = World.new()
local rigs: { Model } = {}
local roots: { [number]: BasePart } = {}
local bodies: { [number]: Humanoid } = {}
local base = CFrame.new(35, 0, 55)
for owner = 701, 703 do
    local model, root, humanoid = Instance.new("Model"), Instance.new("Part"), Instance.new("Humanoid")
    model.Name = "SlowCompositionRig" .. owner
    root.Name, root.Size, root.Anchored, root.Parent = "HumanoidRootPart", Vector3.new(2, 2, 1), true, model
    humanoid.RequiresNeck, humanoid.HipHeight, humanoid.Parent = false, 2, model
    model:SetAttribute("CombatLife", owner)
    model.Parent = workspace
    world.register(owner, model, root, humanoid, base + Vector3.new((owner - 701) * 5, 0, 0))
    roots[owner], bodies[owner] = root, humanoid
    table.insert(rigs, model)
end
local occupying = true
local victim = bodies[703]
local heavy = Heavy.new({ alive = world.alive, origin = world.origin, face = world.face,
    targets = function() return { victim } end,
    damage = function(_: number, target: Humanoid, amount: number) target.Health -= amount; return true end,
    token = world.slowToken, targetOwner = world.targetOwner,
    slow = function(target, amount) world.slow(target, amount, "heavy") end,
    emit = function() end }, heavyConfig)
local hands = Hands.new({ alive = world.alive, placement = function(_, point) return point, nil end,
    targets = function() return if occupying then { victim } else {} end,
    damage = function() end, slow = world.slow, emit = function() end }, handsConfig)
heavy.join(702, 702); hands.join(701, 701)
local count = 0
local function near(value: number, expected: number) assert(math.abs(value - expected) < 0.001, tostring(value) .. " ~= " .. expected) end
local function test(name: string, run: () -> ()) run(); count += 1; print("PASS Slow world: " .. name) end
local ok, problem = xpcall(function()
    test("confirmed heavy damage applies real world WalkSpeed and its movement budget", function()
        assert(heavy.cast(702, 702, Vector3.xAxis, 0))
        heavy.step(0.65)
        near(victim.Health, 75); near(victim.WalkSpeed, 9.6)
        roots[703].CFrame += Vector3.new(0.3, 0, 0)
        assert(world.validate(703), "Ordinary slow movement rolled back")
    end)
    test("hands and heavy choose the strongest source without multiplying", function()
        assert(hands.cast(701, 701, Vector3.new(40, 0, 55), 0))
        hands.step(0.8)
        near(victim.WalkSpeed, 9.6)
    end)
    test("leaving hands cannot erase an existing heavy contribution", function()
        occupying = false; hands.step(1)
        near(victim.WalkSpeed, 9.6)
    end)
    test("heavy expiry inside hands leaves the hands multiplier", function()
        occupying = true; hands.step(1.2); heavy.step(2.65)
        near(victim.WalkSpeed, 16 * handsConfig.slowMultiplier)
    end)
    test("last source removal restores base speed", function()
        hands.leave(701); near(victim.WalkSpeed, 16)
    end)
    test("same Humanoid new life clears old sources without leaking on the next frame", function()
        assert(heavy.cast(702, 702, Vector3.xAxis, 8)); heavy.step(8.65)
        near(victim.WalkSpeed, 9.6)
        assert(world.place(703, base, false))
        rigs[3]:SetAttribute("CombatLife", 900)
        heavy.join(703, 900); heavy.step(8.8)
        near(victim.WalkSpeed, 16)
    end)
    test("pause and death clear outgoing timed slows while target pause clears incoming", function()
        assert(heavy.cast(702, 702, Vector3.xAxis, 16)); heavy.step(16.65)
        heavy.pause(703, 16.7); near(victim.WalkSpeed, 16); heavy.resume(703, 17)
        assert(heavy.cast(702, 702, Vector3.xAxis, 24)); heavy.step(24.65)
        heavy.die(702); near(victim.WalkSpeed, 16)
    end)
    test("cleanup restores the registered target and releases lifecycle resources", function()
        heavy.join(702, 702)
        victim.Health = 100
        assert(heavy.cast(702, 702, Vector3.xAxis, 32)); heavy.step(32.65)
        near(victim.WalkSpeed, 9.6)
        victim.Health = 0; world.step(); heavy.step(32.7)
        near(victim.WalkSpeed, 16)
        heavy.destroy(); hands.destroy(); near(victim.WalkSpeed, 16)
        assert((rigs[3]:GetAttribute("CombatMovementCorrections") or 0) == 0)
    end)
end, debug.traceback)
heavy.destroy(); hands.destroy()
for owner = 701, 703 do world.remove(owner) end
for _, rig in rigs do rig:Destroy() end
assert(ok, problem)
print(count .. " Studio slow composition contracts passed")
return true
