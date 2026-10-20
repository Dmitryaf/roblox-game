--!strict
-- Real-engine queries and the unchanged production adapter. No physics settings/collision groups are changed.
-- require(module).run("baseline") records the old rejection; run() requires contact acceptance after a fix.
local Players = game:GetService("Players")
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local CombatWorld = require(modules.adapters.world.CombatWorld)
local Probe = {}
local OWNER = 9401
local ORIGIN = Vector3.new(500, 0, 500)
local ROOT_SIZE, TORSO_SIZE = Vector3.new(2, 2, 1), Vector3.new(2, 2, 1)

local function colliderSource(): (boolean, boolean, string)
    -- Read live properties when a real character exists. Sizes stay explicit fixture values.
    for _, player in Players:GetPlayers() do
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        local torso = if character then character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") else nil
        if root and root:IsA("BasePart") and torso and torso:IsA("BasePart") and (root.CanCollide or torso.CanCollide) then
            return root.CanCollide, torso.CanCollide, character:GetFullName()
        end
    end
    -- These are declared surrogate properties, not a claim about a generated avatar's defaults.
    return false, true, "explicit_root_false_torso_true_surrogate"
end
local function part(parent: Instance, name: string, size: Vector3, collide: boolean): Part
    local item = Instance.new("Part")
    item.Name, item.Size, item.Anchored = name, size, true
    item.CanCollide, item.CanQuery, item.CanTouch = collide, true, false
    item.Parent = parent
    return item
end
local function avatar(parent: Instance, name: string, rootCollision: boolean, torsoCollision: boolean): (Model, Part, Humanoid)
    local model = Instance.new("Model")
    model.Name = name
    local root = part(model, "HumanoidRootPart", ROOT_SIZE, rootCollision)
    local torso = part(model, "Torso", TORSO_SIZE, torsoCollision)
    torso.CFrame = root.CFrame
    local humanoid = Instance.new("Humanoid")
    humanoid.RequiresNeck, humanoid.HipHeight, humanoid.Parent = false, 2, model
    model.PrimaryPart, model.Parent = root, parent
    return model, root, humanoid
end
local function position(model: Model, frame: CFrame)
    -- Synchronous query fixture: explicit part placement, no waits or physics stepping.
    for _, item in model:GetChildren() do if item:IsA("BasePart") then item.CFrame = frame end end
end
local function policy(): any
    return {
        contains = function(_, p) return p.X == p.X and p.Y == p.Y and p.Z == p.Z and p.Y > 1 and p.Y < 24 end,
        allowed = function() return true end, accepted = function() end,
        castAllowed = function() return true end, damageAllowed = function() return false end,
        barrier = function() return nil end,
    }
end
local function cast(character: Model, frame: CFrame, size: Vector3, delta: Vector3): RaycastResult?
    local p = RaycastParams.new()
    p.FilterType, p.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
    p.RespectCanCollide = true
    return workspace:Blockcast(frame, size, delta, p)
end
local function hitName(hit: RaycastResult?): string return if hit then hit.Instance:GetFullName() else "none" end
local function clear(character: Model, frame: CFrame, size: Vector3): boolean
    local p = OverlapParams.new()
    p.FilterType, p.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
    p.RespectCanCollide = true
    return #workspace:GetPartBoundsInBox(frame, size, p) == 0
end

function Probe.run(mode: string?): any
    local baseline = mode == "baseline"
    assert(mode == nil or mode == "acceptance" or baseline, "Use baseline or acceptance")
    local fixture = Instance.new("Folder")
    fixture.Name, fixture.Parent = "MovementContactGeometry", workspace
    local rootCollision, torsoCollision, source = colliderSource()
    local actor, root, humanoid = avatar(fixture, "MovementContactActor", rootCollision, torsoCollision)
    local world = CombatWorld.new(nil, policy())
    local result: any = { mode = mode or "acceptance", source = source, rows = {}, wallAccepted = 0,
        staticAccepted = 0, dynamicAccepted = 0, hiddenWallAccepted = 0, overlapAccepted = 0,
        surrogateFalsePositives = 0, manualFalsePositives = 0 }
    local obstacles: { Instance } = {}
    local function discardObstacles()
        for _, item in obstacles do item:Destroy() end
        table.clear(obstacles)
    end
    local function begin(frame: CFrame)
        world.remove(OWNER)
        position(actor, frame)
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        world.register(OWNER, actor, root, humanoid)
    end
    local function observe(label: string, yaw: number, from: CFrame, destination: CFrame): boolean
        local delta = destination.Position - from.Position
        local old = cast(actor, from, Vector3.new(2, 3, 2), delta)
        local actual = cast(actor, from, ROOT_SIZE, delta)
        local endpointsClear = clear(actor, from, ROOT_SIZE) and clear(actor, destination, ROOT_SIZE)
        position(actor, destination)
        local accepted = world.validate(OWNER, "contact_geometry_" .. label)
        local corrected = (root.Position - destination.Position).Magnitude
        local row = { label = label, yaw = yaw, accepted = accepted, corrected = corrected,
            oldHit = hitName(old), oldDistance = if old then old.Distance else nil,
            actualHit = hitName(actual), endpointsClear = endpointsClear, step = delta.Magnitude }
        table.insert(result.rows, row)
        print("MovementContact", label, yaw, "accepted", accepted, "correction", corrected,
            "old", row.oldHit, "actual", row.actualHit, "clear", endpointsClear, "step", row.step)
        assert(delta.Magnitude < 8, "Contact fixture exceeded the ordinary movement budget")
        if old and not actual and endpointsClear then result.surrogateFalsePositives += 1 end
        position(actor, root.CFrame)
        return accepted
    end
    local ok, problem = xpcall(function()
        for yaw = 0, 315, 45 do
            discardObstacles()
            local scene = CFrame.new(ORIGIN) * CFrame.Angles(0, math.rad(yaw), 0)
            local function frame(x: number, y: number, z: number): CFrame return scene * CFrame.new(x, y, z) end
            local dummy = Instance.new("Model")
            dummy.Name, dummy.Parent = "ContactTrainingDummy", fixture
            dummy:SetAttribute("TrainingTarget", true)
            local dummyRoot = part(dummy, "HumanoidRootPart", Vector3.new(3, 5, 2), true)
            dummyRoot.CFrame = frame(0, 2.5, 0)
            local dummyHealth = Instance.new("Humanoid")
            dummyHealth.RequiresNeck, dummyHealth.Parent = false, dummy
            table.insert(obstacles, dummy)
            -- Both adjacent segments stay clear for the declared 2x2x1 avatar body.
            -- The old deeper surrogate enters the dummy while that real envelope remains outside.
            local start, middle, finish = frame(0, 3, 2.2), frame(0, 3, 1.9), frame(0, 3, 1.6)
            assert(clear(actor, middle, ROOT_SIZE) and clear(actor, finish, ROOT_SIZE))
            begin(start)
            if observe("static_contact_1", yaw, start, middle) then result.staticAccepted += 1 end
            if observe("static_contact_2", yaw, middle, finish) then result.staticAccepted += 1 end
            -- The first observed manual rejection; absolute source coordinates are 230/-38.
            local before = frame(228.867126 - 230, 2.989174, -35.907600 + 38)
            local observed = frame(228.740921 - 230, 2.980494, -36.010482 + 38)
            begin(before)
            local old, actual = cast(actor, before, Vector3.new(2, 3, 2), observed.Position - before.Position),
                cast(actor, before, ROOT_SIZE, observed.Position - before.Position)
            if old and not actual and clear(actor, before, ROOT_SIZE) and clear(actor, observed, ROOT_SIZE) then
                result.manualFalsePositives += 1
            end
            observe("manual_13_15_21", yaw, before, observed)
            discardObstacles()
            local enemy, enemyRoot = avatar(fixture, "ContactMovingHumanoid", rootCollision, torsoCollision)
            table.insert(obstacles, enemy)
            position(enemy, frame(4, 3, -8))
            local first, second, third = frame(0, 3, 0), frame(2, 3, 0), frame(6.5, 3, 0)
            begin(first)
            if observe("dynamic_clear_1", yaw, first, second) then result.dynamicAccepted += 1 end
            -- Enemy arrives behind the already simulated actor, inside the historical sweep.
            -- Both final bodies are separated; no request to phase through a current opponent.
            position(actor, third)
            position(enemy, frame(4, 3, 0))
            assert(clear(actor, third, ROOT_SIZE), "Moving obstacle overlaps the actor endpoint")
            if observe("dynamic_history_2", yaw, second, third) then result.dynamicAccepted += 1 end
            assert(enemyRoot.CanCollide == rootCollision)
            -- Ignoring a historical humanoid must not hide static geometry farther along the path.
            position(enemy, frame(2.5, 3, 0))
            local hiddenWall = part(fixture, "ContactWallBehindHumanoid", Vector3.new(0.15, 10, 12), true)
            hiddenWall.CFrame = frame(4.5, 5, 0)
            table.insert(obstacles, hiddenWall)
            begin(first)
            if observe("historical_body_then_wall", yaw, first, third) then result.hiddenWallAccepted += 1 end
            hiddenWall:Destroy()
            -- A snapshot overlap is not proof of illegal movement between animated, asynchronously replicated bodies.
            -- LiveContact 868... disproved the earlier endpoint-rejection assumption; see docs/MOVEMENT_CONTACT.md.
            local enemyTorso = enemy:FindFirstChild("Torso") :: BasePart
            local groups = { root.CollisionGroup, enemyRoot.CollisionGroup, enemyTorso.CollisionGroup }
            position(enemy, frame(4, 3, 0))
            begin(first)
            local overlappingSnapshot = frame(4.2, 3, 0)
            assert(not clear(actor, overlappingSnapshot, ROOT_SIZE), "Snapshot fixture did not overlap the collidable torso")
            if observe("body_snapshot_overlap", yaw, first, overlappingSnapshot) then result.overlapAccepted += 1 end
            assert(root.CanCollide == rootCollision and enemyRoot.CanCollide == rootCollision
                and enemyTorso.CanCollide == torsoCollision, "Snapshot handling changed native collision properties")
            assert(root.CollisionGroup == groups[1] and enemyRoot.CollisionGroup == groups[2]
                and enemyTorso.CollisionGroup == groups[3], "Snapshot handling changed collision groups")
            discardObstacles()
            local wall = part(fixture, "ContactThinStaticWall", Vector3.new(0.15, 10, 12), true)
            wall.CFrame = frame(2, 5, 0)
            table.insert(obstacles, wall)
            begin(first)
            if observe("thin_wall_crossing", yaw, first, frame(4, 3, 0)) then result.wallAccepted += 1 end
        end
        assert(result.wallAccepted == 0, "Contact handling permitted crossing a thin static wall")
        assert(result.hiddenWallAccepted == 0, "Skipping a historical body hid the thin wall behind it")
        if baseline then
            assert(result.surrogateFalsePositives >= 8, "Old surrogate false-positive baseline was not reproduced")
            assert(result.staticAccepted < 16 or result.dynamicAccepted < 16, "Production no longer reproduces the contact defect")
        else
            assert(result.overlapAccepted == 8, "A native body snapshot overlap caused an artificial movement rollback")
            assert(result.staticAccepted == 16, "Ordinary contact with the dummy still rolls back a clear body")
            assert(result.dynamicAccepted == 16, "An opponent entering a historical sweep still rolls back a clear current body")
        end
    end, debug.traceback)
    world.remove(OWNER)
    fixture:Destroy()
    assert(ok, problem)
    print("MovementContactSummary", result.mode, "surrogateFalsePositives", result.surrogateFalsePositives,
        "manualFalsePositives", result.manualFalsePositives, "staticAccepted", result.staticAccepted,
        "dynamicAccepted", result.dynamicAccepted, "wallAccepted", result.wallAccepted,
        "hiddenWallAccepted", result.hiddenWallAccepted, "overlapAccepted", result.overlapAccepted)
    return result
end
return Probe
