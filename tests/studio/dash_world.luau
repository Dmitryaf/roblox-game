--!strict
-- Synchronous real-engine geometry/allowance checks; multiplayer observes actual E and motion separately.
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local Arena = require(modules.adapters.world.MatchArena)
local World = require(modules.adapters.world.MatchWorld)
local CombatWorld = require(modules.adapters.world.CombatWorld)
local arena = Arena.create()
local mode, frozen = "match", false
local team: number? = 1
local world = World.new(arena, function() return { mode = mode, team = team, frozen = frozen, matchId = 1 } end,
    function() return not frozen end)
local rig = Instance.new("Model")
rig.Name = "DashGeometryRig"
local root, humanoid = Instance.new("Part"), Instance.new("Humanoid")
root.Name, root.Size, root.Anchored, root.Parent = "HumanoidRootPart", Vector3.new(2, 2, 1), false, rig
humanoid.RequiresNeck, humanoid.HipHeight, humanoid.Parent = false, 2, rig
rig.Parent = workspace
world.register(901, rig, root, humanoid, arena.spawn(1, 901))
local fixtures: { Instance } = {}
local count = 0
local function test(name: string, run: () -> ()) run(); count += 1; print("PASS Dash geometry: " .. name) end
local function reset(position: Vector3)
    world.stopDash(901, "reset")
    world.move(901, position)
    root.AssemblyLinearVelocity = Vector3.zero
end
local function noMover()
    assert(not root:FindFirstChild("WarriorDashVelocity") and not root:FindFirstChild("WarriorDashAttachment"))
end
local ok, err = xpcall(function()
    test("server admits supported directional movement without moving root or changing walking speed", function()
        reset(Vector3.new(70, 3.5, 55))
        local before, speed = root.CFrame, humanoid.WalkSpeed
        local position, distance = world.startDash(901, -Vector3.zAxis, 16, 0.28)
        assert(position and distance == 16 and root.CFrame == before and humanoid.WalkSpeed == speed)
        local mover = root:FindFirstChild("WarriorDashVelocity") :: LinearVelocity
        assert(mover and mover.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane)
        assert(math.abs(mover.PlaneVelocity.Y + 16 / 0.28) < 0.001)
        root.CFrame += Vector3.new(0, 0, -16)
        assert(world.validate(901), "Authorized distance was corrected")
        world.stopDash(901, "expired"); noMover()
    end)
    test("finite credit cannot authorize a second full dash", function()
        reset(Vector3.new(70, 3.5, 55))
        assert(world.startDash(901, -Vector3.zAxis, 16, 0.28))
        root.CFrame += Vector3.new(0, 0, -16)
        assert(world.validate(901))
        local trusted = root.Position
        root.CFrame += Vector3.new(0, 0, -16)
        assert(not world.validate(901) and (root.Position - trusted).Magnitude < 0.01)
        noMover()
    end)
    test("forward credit cannot pay for a sideways jump", function()
        reset(Vector3.new(70, 3.5, 55))
        assert(world.startDash(901, -Vector3.zAxis, 16, 0.28))
        local trusted = root.Position
        root.CFrame += Vector3.new(-16, 0, 0)
        assert(not world.validate(901) and (root.Position - trusted).Magnitude < 0.01)
        noMover()
    end)
    test("forward credit cannot hide a diagonal jump outside the movement budget", function()
        reset(Vector3.new(70, 3.5, 55))
        assert(world.startDash(901, -Vector3.zAxis, 16, 0.28))
        local trusted = root.Position
        root.CFrame += Vector3.new(-16, 0, -16)
        assert(not world.validate(901) and (root.Position - trusted).Magnitude < 0.01)
        noMover()
    end)
    test("thin wall clips distance and still blocks a forged endpoint behind it", function()
        local wall = Instance.new("Part")
        wall.Name, wall.Anchored, wall.Size, wall.Position, wall.Parent = "DashThinWall", true,
            Vector3.new(12, 8, 0.2), Vector3.new(70, 4, 45), workspace
        table.insert(fixtures, wall)
        reset(Vector3.new(70, 3.5, 55))
        local _, distance = world.startDash(901, -Vector3.zAxis, 16, 0.28)
        assert(distance and distance > 6 and distance < 9)
        root.CFrame = CFrame.new(70, 3.5, 39)
        assert(not world.validate(901) and root.Position.Z == 55)
        noMover()
        reset(Vector3.new(70, 3.5, 46.7))
        local position, _, reason = world.startDash(901, -Vector3.zAxis, 16, 0.28)
        assert(not position and reason == "blocked"); noMover()
        wall:Destroy()
    end)
    test("dash cannot start airborne or frozen and cannot cross missing floor", function()
        reset(Vector3.new(70, 13, 55))
        local position, _, reason = world.startDash(901, -Vector3.zAxis, 16, 0.28)
        assert(not position and reason == "airborne"); noMover()
        reset(Vector3.new(70, 3.5, 55)); world.freeze(901, true)
        assert(not world.startDash(901, -Vector3.zAxis, 16, 0.28)); noMover()
        world.freeze(901, false)
        local floor = Instance.new("Part")
        floor.Anchored, floor.Size, floor.Position, floor.Parent = true, Vector3.new(12, 2, 16), Vector3.new(400, -1, 0), workspace
        table.insert(fixtures, floor)
        local isolated = CombatWorld.new(nil, {
            contains = function(_, p) return p.Y > 1 and p.Y < 24 end,
            allowed = function() return true end, accepted = function() end,
            castAllowed = function() return true end, damageAllowed = function() return false end,
            barrier = function() return nil end,
        })
        root.CFrame = CFrame.new(400, 3.5, 0)
        root.AssemblyLinearVelocity = Vector3.zero
        isolated.register(902, rig, root, humanoid)
        local _, distance = isolated.startDash(902, Vector3.xAxis, 16, 0.28)
        assert(distance and distance >= 3 and distance < 5, "Dash crosses the unsupported gap")
        isolated.remove(902); noMover(); floor:Destroy()
    end)
    test("own pad exit restriction and enemy pad block the swept path", function()
        reset(Vector3.new(0, 3.5, 98))
        local _, distance = world.startDash(901, Vector3.zAxis, 16, 0.28)
        assert(distance and distance < 2, "Dash entered own protected pad")
        world.stopDash(901, "reset")
        reset(Vector3.new(0, 3.5, -98))
        local _, enemyDistance = world.startDash(901, -Vector3.zAxis, 16, 0.28)
        assert(enemyDistance and enemyDistance < 2, "Dash entered enemy protected pad")
        world.stopDash(901, "reset")
    end)
    test("arena edge includes body clearance and pause/reset clear native resources", function()
        reset(Vector3.new(86, 3.5, 0))
        local _, distance = world.startDash(901, Vector3.xAxis, 16, 0.28)
        assert(distance and distance < 5.6)
        world.freeze(901, true); noMover(); world.freeze(901, false)
        reset(Vector3.new(70, 3.5, 55)); assert(world.startDash(901, -Vector3.zAxis, 16, 0.28))
        world.resetContext(901, 1, false); noMover()
        reset(Vector3.new(70, 3.5, 55)); assert(world.startDash(901, -Vector3.zAxis, 16, 0.28))
        world.remove(901); noMover()
    end)
end, debug.traceback)
world.remove(901); rig:Destroy()
for _, instance in fixtures do instance:Destroy() end
arena.folder:Destroy()
assert(ok, err)
print(string.format("%d Studio dash geometry tests passed", count))
return true
