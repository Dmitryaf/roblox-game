--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local CFrame, Vector3 = rb.CFrame, rb.Vector3
local source = fs.readFile("src/client/presentation/ClassLocomotion.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function difference(a, b)
    local _, angle = (a:Inverse() * b):ToAxisAngle()
    return math.abs(angle) + (a.Position - b.Position).Magnitude
end
local function fixture(rig, classId, constrained)
    local f = { time = 10, life = 3, classId = classId or "warrior", acting = false, motors = {}, base = {}, present = true }
    local character = { Parent = true }
    f.character = character
    function character:GetAttribute(name) return if name == "CombatClass" then f.classId else f.life end
    f.humanoidData = { Health = 100, MoveDirection = Vector3.zero, AutoRotate = true, WalkSpeed = 16 }
    f.humanoid = setmetatable({}, { __index = f.humanoidData, __newindex = function(_, key) error("Stance wrote Humanoid." .. key) end })
    f.rootData = { Anchored = false, CFrame = CFrame.new(4, 3, 2), AssemblyLinearVelocity = Vector3.new(0, 0, -16) }
    f.root = setmetatable({}, {
        __index = function(_, key)
            if key == "IsA" then return function(_, kind) return kind == "BasePart" end end
            return f.rootData[key]
        end,
        __newindex = function(_, key) error("Stance wrote root." .. key) end,
    })
    function character:FindFirstChildOfClass() return f.humanoid end
    function character:FindFirstChild(name) return if name == "HumanoidRootPart" then f.root else nil end
    local descendants = {}
    local channels = if rig == "R6" then { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }
        else { "RootJoint", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist", "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle" }
    for index, name in channels do
        local data = { Name = if constrained then "Animated" .. name else name, Parent = character,
            Transform = CFrame.new(0.01, 0.02, 0.03) * CFrame.Angles(index * 0.02, 0.07, -0.03),
            C0 = CFrame.Angles(0.2, -0.1, 0.12), Attachment0 = { Name = name .. "RigAttachment", CFrame = CFrame.Angles(0.2, -0.1, 0.12) } }
        local motor = setmetatable({}, {
            __index = function(_, key)
                if key == "IsA" then return function(_, kind) return kind == (if constrained then "AnimationConstraint" else "Motor6D") end end
                return data[key]
            end,
            __newindex = function(_, key, value)
                assert(key == "Transform", "Stance wrote joint." .. key)
                data[key] = value
            end,
        })
        f.motors[name], f.base[name] = motor, data.Transform
        table.insert(descendants, motor)
    end
    function character:GetDescendants() return descendants end
    f.player = { UserId = 19, Character = character }
    local players = {}; function players:GetPlayers() return if f.present then { f.player } else {} end
    local game = {}; function game:GetService(name) assert(name == "Players", "Unexpected service/independent frame connection: " .. name); return players end
    f.pose = luau.load(source, { environment = { game = game, CFrame = CFrame, Vector3 = Vector3 } })().new({
        isActing = function(subject) assert(subject == character); return f.acting end,
    })
    function f.frame(delta, animate)
        local dt = delta or 1 / 60
        f.time += dt; f.pose.beforePose()
        if animate then
            for name, motor in f.motors do
                f.base[name] = CFrame.new(0.01, 0.02, 0.03) * CFrame.Angles(math.sin(f.time * 8) * 0.5, 0.08, -0.05)
                motor.Transform = f.base[name]
            end
        end
        f.pose.afterPose(f.time, dt)
    end
    function f.restored()
        for name, motor in f.motors do assert(difference(motor.Transform, f.base[name]) < 0.00001, "Not restored: " .. name) end
    end
    function f.settle() for _ = 1, 60 do f.frame() end end
    return f
end
test("R6 R15 and retargeted constraints have distinct finite class stances without taking root or running legs", function()
    for _, rig in { "R6", "R15" } do
        for _, constrained in { false, true } do
            local poses = {}
            for _, classId in { "warrior", "warlock" } do
                local f = fixture(rig, classId, constrained); f.settle()
                assert(f.pose.active(19))
                local name = if rig == "R6" then "Right Shoulder" else "RightShoulder"
                assert(difference(f.motors[name].Transform, f.base[name]) > 0.15)
                poses[classId] = f.motors[name].Transform
                f.humanoidData.MoveDirection = Vector3.new(0, 0, -1)
                for _ = 1, 90 do
                    f.frame(1 / 60, true)
                    for key, motor in f.motors do
                        local distance = difference(motor.Transform, f.base[key])
                        assert(distance == distance and distance < 0.9, "Unbounded pose: " .. key)
                        assert((motor.Transform.Position - f.base[key].Position).Magnitude < 0.03)
                        if key:find("Hip") or key:find("Knee") or key:find("Ankle") or key == "RootJoint" then
                            assert(motor.Transform == f.base[key], "Took native locomotion joint " .. key)
                        end
                    end
                end
                assert(f.humanoid.AutoRotate and f.humanoid.WalkSpeed == 16 and f.root.AssemblyLinearVelocity == Vector3.new(0, 0, -16))
                f.pose.destroy(); f.restored()
            end
            assert(difference(poses.warrior, poses.warlock) > 0.15)
        end
    end
end)
test("idle to run and stop blend without an abrupt weapon shoulder change at either transition", function()
    local f = fixture("R15"); f.settle()
    for _, moving in { true, false } do
        local before = f.motors.RightShoulder.Transform
        f.humanoidData.MoveDirection = if moving then Vector3.new(0, 0, -1) else Vector3.zero
        f.frame(); local first = f.motors.RightShoulder.Transform
        assert(difference(before, first) < 0.02)
        for _ = 1, 30 do f.frame() end
        assert(difference(first, f.motors.RightShoulder.Transform) > 0.02)
    end
    f.pose.destroy(); f.restored()
end)
test("action ownership immediately suppresses stance and fades back after action without transforming its Animator base", function()
    local f = fixture("R15"); f.settle(); f.acting = true
    f.frame(); f.restored(); assert(not f.pose.active(19))
    local action = CFrame.Angles(-1, 0.6, -0.2)
    f.motors.RightShoulder.Transform = action
    f.pose.beforePose(); f.pose.afterPose(f.time, 0.016)
    assert(f.motors.RightShoulder.Transform == action and not f.pose.active(19))
    f.base.RightShoulder = action; f.acting = false; f.frame()
    assert(difference(f.motors.RightShoulder.Transform, action) < 0.04)
    for _ = 1, 40 do f.frame() end
    assert(difference(f.motors.RightShoulder.Transform, action) > 0.15)
    f.pose.destroy(); f.restored()
end)
test("death pause life class character replacement leave and unsupported classes clear the previous owner", function()
    for _, reason in { "death", "pause", "life", "class", "replacement", "leave", "unknown" } do
        local f = fixture("R15"); f.settle()
        if reason == "death" then f.humanoidData.Health = 0
        elseif reason == "pause" then f.rootData.Anchored = true
        elseif reason == "life" then f.life += 1
        elseif reason == "class" then f.classId = "warlock"
        elseif reason == "replacement" then f.player.Character = nil
        elseif reason == "leave" then f.present = false
        else f.classId = "unknown" end
        f.pose.afterPose(f.time, 0.016); f.restored(); assert(not f.pose.active(19), reason)
        if reason == "life" or reason == "class" then
            f.frame(); assert(difference(f.motors.RightShoulder.Transform, f.base.RightShoulder) < 0.04)
        elseif reason == "pause" then
            f.rootData.Anchored = false; f.frame()
            assert(difference(f.motors.RightShoulder.Transform, f.base.RightShoulder) < 0.04)
        end
        f.pose.destroy(); f.restored()
    end
end)
test("repeated throttled Animator frames never accumulate stance and cleanup preserves later writer ownership", function()
    local f = fixture("R15"); f.settle()
    for _ = 1, 400 do f.pose.afterPose(f.time, 0.016) end
    assert(difference(f.motors.RightShoulder.Transform, f.base.RightShoulder) < 0.4)
    local external = CFrame.Angles(0.6, 0.3, -0.9)
    f.motors.RightShoulder.Transform = external; f.base.RightShoulder = external
    f.pose.beforePose(); assert(f.motors.RightShoulder.Transform == external)
    f.pose.destroy(); f.restored(); f.frame(); f.restored(); assert(not f.pose.active(19))
end)
test("warrior inertial shoulders reduce fast native weapon wag without freezing the running animation", function()
    local f = fixture("R15"); f.humanoidData.MoveDirection = Vector3.new(0, 0, -1); f.settle()
    local before = f.motors.RightShoulder.Transform
    f.pose.beforePose()
    f.base.RightShoulder = f.base.RightShoulder * CFrame.Angles(0.6, 0, 0)
    f.motors.RightShoulder.Transform = f.base.RightShoulder
    f.pose.afterPose(f.time, 1 / 60)
    local response = difference(before, f.motors.RightShoulder.Transform)
    assert(response > 0.25 and response < 0.5, "Shoulder should follow but damp the native run frame: " .. response)
    for _ = 1, 90 do f.frame() end
    assert(difference(before, f.motors.RightShoulder.Transform) > response + 0.05)
    f.pose.destroy(); f.restored()
end)
print(string.format("%d class locomotion lifecycle/composition tests passed", total))
