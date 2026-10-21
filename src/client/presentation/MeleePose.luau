--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Motion = require(script.Parent.MeleeMotion)
local DashMotion = require(script.Parent.DashPoseMotion)
local Facing = require(script.Parent.MeleeFacing)
local HeavyMotion: any = nil
local MeleePose = {}
type Motor = Motor6D | AnimationConstraint
type Joint = { motor: Motor, rest: CFrame, keys: { Vector3 }, body: boolean, torso: boolean, lower: boolean?, support: boolean?, base: CFrame?, applied: CFrame? }
type Swing = { character: Model, humanoid: Humanoid, root: BasePart?, joints: { Joint }, started: number,
    hitAt: number, expires: number, received: number, direction: Vector3?, facing: any, kind: string, id: number?, life: any, timeline: any?, preview: boolean?, requestId: number?, dashLead: number?, native: any?, lowerWeight: number? }
local function transform(motor: Motor, value: CFrame)
    if motor:IsA("Motor6D") then motor.Transform = value else (motor :: AnimationConstraint).Transform = value end
end
local function restore(joint: Joint)
    if joint.motor.Parent and joint.applied and joint.base and joint.motor.Transform == joint.applied then
        transform(joint.motor, joint.base)
    end
    joint.applied = nil
end
function MeleePose.new(manualFrames: boolean?, clips: Instance?)
    local Native: any = if clips then require(script.Parent.NativePoseSampler) else nil
    local NativeTiming: any = if clips then require(script.Parent.NativePoseTiming) else nil
    local NativeLocomotion: any = if clips then require(script.Parent.NativePoseLocomotion) else nil
    local swings: { [number]: Swing } = {}
    local pose = {}
    function pose.stop(owner: number, expectedKind: string?, expectedId: number?)
        local swing = swings[owner]
        if not swing then return end
        if expectedKind and swing.kind ~= expectedKind then return end
        if expectedId and swing.id ~= expectedId then return end
        for _, joint in swing.joints do restore(joint) end
        if swing.facing then swing.facing.destroy() end
        if swing.native then swing.native.destroy() end
        swings[owner] = nil
    end
    local function collect(character: Model, channels: any, nativeBody: boolean?): { Joint }
        local joints: { Joint } = {}
        local descendants = character:GetDescendants()
        for _, channel in channels do
            local found = false
            for _, candidate in descendants do
                if not candidate:IsA("Motor6D") and not candidate:IsA("AnimationConstraint") then continue end
                local attachment = if candidate:IsA("AnimationConstraint") then candidate.Attachment0 else nil
                for _, name in channel.names do
                    if nativeBody and channel.names[1] == "Waist" and name == "RootJoint" then continue end
                    if candidate.Name ~= name and not (attachment and attachment.Name == name .. "RigAttachment") then continue end
                    local rest = if candidate:IsA("Motor6D") then candidate.C0.Rotation else if attachment then attachment.CFrame.Rotation else CFrame.identity
                    table.insert(joints, { motor = candidate, rest = rest, keys = channel.keys, body = channel.body,
                        torso = channel.names[1] == "Waist", lower = channel.lower == true, support = channel.support == true })
                    found = true
                    break
                end
                if found then break end
            end
        end
        return joints
    end
    local function adopt(owner: number, kind: string, requestId: number?, hitAt: number, startedAt: number?, expiresAt: number?, direction: Vector3?, swingId: number?): boolean
        local current = swings[owner]
        if not current or not current.preview or current.kind ~= kind or current.requestId ~= requestId then return false end
        current.timeline.confirm(workspace:GetServerTimeNow(), hitAt)
        current.started, current.hitAt, current.expires = startedAt or hitAt - 0.3, hitAt, expiresAt or hitAt + 0.45
        current.direction, current.id, current.preview = direction, swingId, false
        return true
    end
    function pose.begin(owner: number, hitAt: number, startedAt: number?, expiresAt: number?, direction: Vector3?, swingId: number?, requestId: number?)
        if adopt(owner, "melee", requestId, hitAt, startedAt, expiresAt, direction, swingId) then return end
        pose.stop(owner)
        local player = Players:GetPlayerByUserId(owner)
        local character = if player then player.Character else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        if not character or not humanoid or humanoid.Health <= 0 then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        swings[owner] = { character = character, humanoid = humanoid, joints = collect(character, Motion.channels),
            root = if root and root:IsA("BasePart") then root else nil, direction = direction,
            started = startedAt or hitAt - 0.3, hitAt = hitAt, expires = expiresAt or hitAt + 0.45,
            received = workspace:GetServerTimeNow(), kind = "melee", id = swingId, life = character:GetAttribute("CombatLife"),
            facing = if player == Players.LocalPlayer and direction then Facing.new(character, direction) else nil }
        local clip = if clips then clips:FindFirstChild("WarriorStrike") else nil
        if clip and clip:IsA("AnimationClip") then
            local swing = swings[owner]
            swing.native = Native.new(character, clip)
            if swing.native then
                -- R15's visual RootJoint is not the R6 fallback for Waist here.
                swing.joints = collect(character, Motion.channels, true)
                local channels = {}
                for _, name in NativeLocomotion.joints do
                    table.insert(channels, { names = { name }, body = true, lower = true, keys = { Vector3.zero } })
                end
                table.insert(channels, { names = { "Root", "RootJoint" }, body = true, lower = true, support = true, keys = { Vector3.zero } })
                for _, joint in collect(character, channels) do table.insert(swing.joints, joint) end
                swing.lowerWeight = 0
            end
        end
    end
    function pose.beginDash(owner: number, duration: number, direction: Vector3, dashId: number, requestId: number?)
        local current = swings[owner]
        local now = workspace:GetServerTimeNow()
        if current and current.kind == "dash" then
            if not current.preview and current.id == dashId then return end
            if current.preview then
                local currentPlayer = Players:GetPlayerByUserId(owner)
                -- A late acknowledgement cannot replace a newer pending brace or another life.
                if current.requestId ~= requestId or not currentPlayer or currentPlayer.Character ~= current.character
                    or current.character:GetAttribute("CombatClass") ~= "warrior" or current.character:GetAttribute("CombatLife") ~= current.life
                    or current.humanoid.Health <= 0 or (current.root and current.root.Anchored) then return end
                current.dashLead = math.min(0.03, math.max(0, now - current.started))
                current.started, current.hitAt, current.expires = now, now, now + math.clamp(duration, 0.18, 0.28)
                current.direction, current.id, current.preview = direction, dashId, false
                return
            end
        end
        pose.stop(owner)
        local player = Players:GetPlayerByUserId(owner)
        local character = if player then player.Character else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        if not character or not humanoid or humanoid.Health <= 0 then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        swings[owner] = { character = character, humanoid = humanoid, joints = collect(character, DashMotion.channels),
            root = if root and root:IsA("BasePart") then root else nil, direction = direction,
            started = now, hitAt = now, expires = now + math.clamp(duration, 0.18, 0.28), received = now,
            facing = nil, kind = "dash", id = dashId, life = character:GetAttribute("CombatLife") }
    end
    function pose.previewDash(owner: number, requestId: number, life: number, direction: Vector3): boolean
        if swings[owner] then return false end
        local player = Players:GetPlayerByUserId(owner)
        local character = if player then player.Character else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        local flat = direction * Vector3.new(1, 0, 1)
        if not character or not character.Parent or character:GetAttribute("CombatLife") ~= life
            or character:GetAttribute("CombatClass") ~= "warrior" or not humanoid or humanoid.Health <= 0
            or not root or not root:IsA("BasePart") or root.Anchored or not (flat.Magnitude > 0 and flat.Magnitude < math.huge) then return false end
        local now = workspace:GetServerTimeNow()
        swings[owner] = { character = character, humanoid = humanoid, root = root, joints = collect(character, DashMotion.channels),
            direction = flat.Unit, started = now, hitAt = math.huge, expires = now + 2.5, received = now,
            facing = nil, kind = "dash", id = -requestId, life = life, requestId = requestId, preview = true }
        return true
    end
    function pose.beginHeavy(owner: number, hitAt: number, startedAt: number?, expiresAt: number?, direction: Vector3?, swingId: number?, requestId: number?)
        if adopt(owner, "heavy", requestId, hitAt, startedAt, expiresAt, direction, swingId) then return end
        HeavyMotion = HeavyMotion or require(script.Parent.HeavyMotion)
        pose.stop(owner)
        local player = Players:GetPlayerByUserId(owner)
        local character = if player then player.Character else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        if not character or not humanoid or humanoid.Health <= 0 then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        swings[owner] = { character = character, humanoid = humanoid, joints = collect(character, HeavyMotion.channels),
            root = if root and root:IsA("BasePart") then root else nil, direction = direction,
            started = startedAt or hitAt - 0.65, hitAt = hitAt, expires = expiresAt or hitAt + 0.6,
            received = workspace:GetServerTimeNow(), kind = "heavy", id = swingId, life = character:GetAttribute("CombatLife"),
            facing = if player == Players.LocalPlayer and direction then Facing.new(character, direction) else nil }
    end
    function pose.preview(owner: number, kind: string, requestId: number, life: number, direction: Vector3): boolean
        if swings[owner] then return false end
        local player = Players:GetPlayerByUserId(owner)
        if not player or not player.Character or player.Character:GetAttribute("CombatLife") ~= life then return false end
        local now = workspace:GetServerTimeNow()
        if kind == "heavy" then pose.beginHeavy(owner, now + 0.65, now, now + 2.5, direction, -requestId)
        else pose.begin(owner, now + 0.3, now, now + 2.5, direction, -requestId) end
        local current = swings[owner]
        if not current then return false end
        local Timeline = require(script.Parent.PreparationTimeline)
        current.preview, current.requestId, current.timeline, current.hitAt = true, requestId, Timeline.new(now), math.huge
        return true
    end
    function pose.cancelPreview(owner: number, kind: string, requestId: number?)
        local current = swings[owner]
        if current and current.preview and current.kind == kind and (requestId == nil or current.requestId == requestId) then pose.stop(owner) end
    end
    function pose.active(owner: number): boolean return swings[owner] ~= nil end
    function pose.step(now: number)
        for owner, swing in swings do
            local player = Players:GetPlayerByUserId(owner)
            if not player or player.Character ~= swing.character or not swing.character.Parent or swing.humanoid.Health <= 0
                or swing.character:GetAttribute("CombatClass") ~= "warrior" or swing.character:GetAttribute("CombatLife") ~= swing.life
                or (swing.root and swing.root.Anchored) or now >= swing.expires then pose.stop(owner) end
        end
    end
    -- Remove only our last overlay before the Animator evaluates its next running frame.
    function pose.beforePose()
        for _, swing in swings do for _, joint in swing.joints do restore(joint) end end
    end
    function pose.preparePose(now: number)
        pose.step(now)
        for _, swing in swings do
            if swing.native then
                swing.native.prepare(NativeTiming.time(now, swing.started, swing.hitAt, swing.expires,
                    0.458333343, 1, swing.timeline))
            end
        end
    end
    function pose.afterPose(now: number, delta: number)

        pose.step(now)
        for _, swing in swings do
            if swing.native then swing.native.capture() end
            if swing.native then swing.lowerWeight = NativeLocomotion.weight(swing.humanoid, swing.root, swing.lowerWeight or 0, delta) end
            if swing.facing then swing.facing.step(now, swing.hitAt, delta) end
            local isDash = swing.kind == "dash"
            local isHeavy = swing.kind == "heavy"
            local time = if isDash then DashMotion.time(now, swing.started, swing.expires)
                else if isHeavy then HeavyMotion.time(now, swing.started, swing.hitAt, swing.expires)
                else Motion.time(now, swing.started, swing.hitAt, swing.expires)
            if isDash then
                if swing.preview then time = math.min(0.03, math.max(0, now - swing.started))
                elseif swing.dashLead then time = swing.dashLead + (0.28 - swing.dashLead) * time / 0.28 end
            end
            if swing.timeline and now < swing.hitAt then
                time = swing.timeline.progress(now) * (if isHeavy then 0.65 else 0.3)
            end
            local weight = if isDash then DashMotion.weight(time)
                else if isHeavy then HeavyMotion.weight(time, now - swing.received) else Motion.weight(time, now - swing.received)
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
                if joint.lower and (swing.lowerWeight or 0) == 0 then continue end
                local base = joint.motor.Transform
                local angles = if swing.native then Vector3.zero else if isDash then DashMotion.sample(joint.keys, time)
                    else if isHeavy then HeavyMotion.sample(joint.keys, time) else Motion.sample(joint.keys, time)
                if isDash and joint.torso and swing.root and swing.direction then
                    local localDirection = swing.root.CFrame:VectorToObjectSpace(swing.direction)
                    angles = Vector3.new(localDirection.Z * math.abs(angles.X), angles.Y, angles.Z - localDirection.X * math.abs(angles.X) * 0.7)
                end
                local rotation = if swing.native then (if joint.support then swing.native.support(joint.motor) else swing.native.sample(joint.motor)) or CFrame.identity
                    else joint.rest:Inverse() * CFrame.Angles(angles.X, angles.Y, angles.Z) * joint.rest
                local target: CFrame
                if joint.lower then
                    target = CFrame.identity:Lerp(rotation, swing.lowerWeight or 0) * base
                elseif joint.body then
                    local amplitude = if running and not isDash then (if isHeavy then 0.75 else 0.5) else 1
                    target = CFrame.identity:Lerp(rotation, amplitude) * base
                    if not isDash and (joint.motor.Name == "Waist" or joint.motor.Name == "RootJoint") then
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
    end
    local animation: RBXScriptConnection? = nil
    local simulation: RBXScriptConnection? = nil
    if not manualFrames then
        animation = RunService.PreAnimation:Connect(function()
            pose.beforePose(); pose.preparePose(workspace:GetServerTimeNow())
        end)
        simulation = RunService.PreSimulation:Connect(function(delta: number) pose.afterPose(workspace:GetServerTimeNow(), delta) end)
    end
    function pose.destroy()
        if animation then animation:Disconnect() end
        if simulation then simulation:Disconnect() end
        for owner in swings do pose.stop(owner) end
    end
    return pose
end
return MeleePose
