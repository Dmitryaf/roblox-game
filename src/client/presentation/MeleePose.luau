--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Motion = require(script.Parent.MeleeMotion)
local Facing = require(script.Parent.MeleeFacing)
local MeleePose = {}
type Motor = Motor6D | AnimationConstraint
type Joint = { motor: Motor, rest: CFrame, keys: { Vector3 }, body: boolean, base: CFrame?, applied: CFrame? }
type Swing = { character: Model, humanoid: Humanoid, root: BasePart?, joints: { Joint }, started: number,
    hitAt: number, expires: number, received: number, direction: Vector3?, facing: any }
local function transform(motor: Motor, value: CFrame)
    if motor:IsA("Motor6D") then motor.Transform = value else (motor :: AnimationConstraint).Transform = value end
end
local function restore(joint: Joint)
    if joint.motor.Parent and joint.applied and joint.base and joint.motor.Transform == joint.applied then
        transform(joint.motor, joint.base)
    end
    joint.applied = nil
end
function MeleePose.new()
    local swings: { [number]: Swing } = {}
    local pose = {}
    function pose.stop(owner: number)
        local swing = swings[owner]
        if not swing then return end
        for _, joint in swing.joints do restore(joint) end
        if swing.facing then swing.facing.destroy() end
        swings[owner] = nil
    end
    function pose.begin(owner: number, hitAt: number, startedAt: number?, expiresAt: number?, direction: Vector3?)
        pose.stop(owner)
        local player = Players:GetPlayerByUserId(owner)
        local character = if player then player.Character else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        if not character or not humanoid or humanoid.Health <= 0 then return end
        local joints: { Joint } = {}
        local descendants = character:GetDescendants()
        for _, channel in Motion.channels do
            local found = false
            for _, candidate in descendants do
                if not candidate:IsA("Motor6D") and not candidate:IsA("AnimationConstraint") then continue end
                local attachment = if candidate:IsA("AnimationConstraint") then candidate.Attachment0 else nil
                for _, name in channel.names do
                    if candidate.Name ~= name and not (attachment and attachment.Name == name .. "RigAttachment") then continue end
                    local rest = if candidate:IsA("Motor6D") then candidate.C0.Rotation else if attachment then attachment.CFrame.Rotation else CFrame.identity
                    table.insert(joints, { motor = candidate, rest = rest, keys = channel.keys, body = channel.body })
                    found = true
                    break
                end
                if found then break end
            end
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        swings[owner] = { character = character, humanoid = humanoid, joints = joints,
            root = if root and root:IsA("BasePart") then root else nil, direction = direction,
            started = startedAt or hitAt - 0.3, hitAt = hitAt, expires = expiresAt or hitAt + 0.45,
            received = workspace:GetServerTimeNow(),
            facing = if player == Players.LocalPlayer and direction then Facing.new(character, direction) else nil }
    end
    function pose.step(now: number)
        for owner, swing in swings do
            local player = Players:GetPlayerByUserId(owner)
            if not player or player.Character ~= swing.character or not swing.character.Parent or swing.humanoid.Health <= 0
                or swing.character:GetAttribute("CombatClass") ~= "warrior" or now >= swing.expires then pose.stop(owner) end
        end
    end
    -- Remove only our last overlay before the Animator evaluates its next running frame.
    local animation = RunService.PreAnimation:Connect(function()
        for _, swing in swings do for _, joint in swing.joints do restore(joint) end end
    end)
    local simulation = RunService.PreSimulation:Connect(function(delta: number)
        local now = workspace:GetServerTimeNow()
        pose.step(now)
        for _, swing in swings do
            if swing.facing then swing.facing.step(now, swing.hitAt, delta) end
            local time = Motion.time(now, swing.started, swing.hitAt, swing.expires)
            local weight = Motion.weight(time, now - swing.received)
            local running = swing.humanoid.MoveDirection.Magnitude > 0.1
            local aim = 0
            if swing.root and swing.direction then
                local look = swing.root.CFrame.LookVector * Vector3.new(1, 0, 1)
                local direction = swing.direction * Vector3.new(1, 0, 1)
                if look.Magnitude > 0.1 and direction.Magnitude > 0.1 then
                    aim = math.clamp(math.atan2(look:Cross(direction).Y, look:Dot(direction)), -0.55, 0.55)
                end
            end
            for _, joint in swing.joints do
                if not joint.motor.Parent then continue end
                -- PreAnimation normally restores us; this also covers throttled Animator frames.
                restore(joint)
                local base = joint.motor.Transform
                local angles = Motion.sample(joint.keys, time)
                local rotation = joint.rest:Inverse() * CFrame.Angles(angles.X, angles.Y, angles.Z) * joint.rest
                local target: CFrame
                if joint.body then
                    local amplitude = if running then 0.5 else 1
                    target = CFrame.identity:Lerp(rotation, amplitude) * base
                    if joint.motor.Name == "Waist" or joint.motor.Name == "RootJoint" then
                        target = joint.rest:Inverse() * CFrame.Angles(0, aim * 0.65, 0) * joint.rest * target
                    end
                else
                    -- Keep the Animator's rig/retargeting basis; identity is not an avatar's neutral arm pose.
                    target = rotation * base
                end
                transform(joint.motor, base:Lerp(target, weight * (if joint.body then 1 else 0.94)))
                joint.base, joint.applied = base, joint.motor.Transform
            end
        end
    end)
    function pose.destroy()
        animation:Disconnect(); simulation:Disconnect()
        for owner in swings do pose.stop(owner) end
    end
    return pose
end
return MeleePose
