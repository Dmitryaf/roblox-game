--!strict
-- Local full-body overlay; Roblox locomotion and the authoritative root remain active.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CastPose = {}
type AnimationJoint = Motor6D | AnimationConstraint
type Joint = { motor: AnimationJoint, rest: CFrame, raised: Vector3, charge: Vector3, focus: Vector3, release: Vector3,
	breath: Vector3, aimFocus: Vector3, aimRelease: Vector3, name: string, lower: boolean?, support: boolean?, lastBase: CFrame?, lastApplied: CFrame? }
type Pose = { character: Model, joints: { Joint }, started: number, release: number, life: any, preview: boolean?, requestId: number?, timeline: any?, native: any?,
    facing: any?, direction: Vector3?, lowerWeight: number?, lastFrame: number? }
local RELEASE = 0.05
local RECOVERY = 0.4
local function radians(x: number, y: number, z: number): Vector3 return Vector3.new(math.rad(x), math.rad(y), math.rad(z)) end
local function smooth(t: number): number t = math.clamp(t, 0, 1); return t * t * (3 - 2 * t) end
local function setTransform(joint: AnimationJoint, value: CFrame)
	if joint:IsA("Motor6D") then joint.Transform = value else (joint :: AnimationConstraint).Transform = value end
end
function CastPose.new(clock: (() -> number)?, manualFrames: boolean?, clips: Instance?)
    local Native: any = if clips then require(script.Parent.NativePoseSampler) else nil
    local NativeTiming: any = if clips then require(script.Parent.NativePoseTiming) else nil
    local NativeLocomotion: any = if clips then require(script.Parent.NativePoseLocomotion) else nil
    local Facing: any = if clips then require(script.Parent.MeleeFacing) else nil
	local readClock = clock or function(): number return workspace:GetServerTimeNow() end
	local poses: { [number]: Pose } = {}
	local pose = {}
	function pose.stop(owner: number)
		local current = poses[owner]
		if current then
			if current.native then current.native.destroy() end
            if current.facing then current.facing.destroy() end
			for _, joint in current.joints do
				-- Animator may have written a new pose since our last update. Preserve that value.
				if joint.motor.Parent and joint.lastApplied and joint.motor.Transform == joint.lastApplied and joint.lastBase then
					setTransform(joint.motor, joint.lastBase)
				end
			end
		end
		poses[owner] = nil
	end
	function pose.begin(owner: number, release: number, direction: Vector3?, startedAt: number?, requestId: number?)
        local current = poses[owner]
        if current and current.preview and current.requestId == requestId then
            current.timeline.confirm(readClock(), release)
            current.started, current.release, current.preview = startedAt or current.started, release, false
            current.direction = direction or current.direction
            return
        end
		pose.stop(owner)
		local player = Players:GetPlayerByUserId(owner)
		local character = if player then player.Character else nil
		if not character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		local segmentedArms = character:FindFirstChild("UpperTorso") ~= nil
		local pitch, yaw = 0, 0
		if direction and direction.Magnitude > 0.1 and root and root:IsA("BasePart") then
			local localDirection = root.CFrame:VectorToObjectSpace(direction.Unit)
			pitch = math.clamp(math.asin(math.clamp(localDirection.Y, -1, 1)), -0.4, 0.6)
			yaw = math.clamp(math.atan2(-localDirection.X, -localDirection.Z), -0.5, 0.5)
		end
		local joints: { Joint } = {}
		local descendants = character:GetDescendants()
		local function add(names: { string }, raised: Vector3, charge: Vector3, released: Vector3, focus: Vector3?, breath: Vector3?, lower: boolean?, support: boolean?)
			local aimFocus = if names[1] == "Waist" then Vector3.new(0, yaw * 0.25, 0)
				else if names[1] == "Neck" then Vector3.new(pitch * 0.55, yaw * 0.65, 0) else Vector3.zero
			local aimRelease = if names[1] == "Neck" then aimFocus
				else if names[1] == "RightShoulder" then Vector3.new(pitch, yaw, 0) else Vector3.zero
			for _, candidate in descendants do
				if not candidate:IsA("Motor6D") and not candidate:IsA("AnimationConstraint") then continue end
				for _, name in names do
					local attachment = if candidate:IsA("AnimationConstraint") then candidate.Attachment0 else nil
					if candidate.Name ~= name and not (attachment and attachment.Name == name .. "RigAttachment") then continue end
					-- The attachment frame is the upgraded rig's read-only equivalent of C0.
					local rest = if candidate:IsA("Motor6D") then candidate.C0.Rotation else if attachment then attachment.CFrame.Rotation else CFrame.identity
					table.insert(joints, { motor = candidate, rest = rest, raised = raised, charge = charge, focus = focus or charge,
						release = released, breath = breath or Vector3.zero, aimFocus = aimFocus, aimRelease = aimRelease, name = names[1], lower = lower, support = support })
					return
				end
			end
		end
		-- Both hands rise directly toward the sternum and remain there to gather power.
		-- The final aim is a small head movement, not an early throwing gesture.
		add({ "Waist", "RootJoint" }, radians(-3, -4, 0), radians(-7, -7, 0), radians(-12, 7, 1),
			Vector3.new(math.rad(-6), yaw * 0.25, 0), radians(0.65, 0, 0))
		add({ "Neck" }, radians(-10, 3, 0), radians(-17, 5, 0), Vector3.new(pitch * 0.55, yaw * 0.65, 0),
			Vector3.new(pitch * 0.55, yaw * 0.65, 0), radians(-0.25, 0, 0))
		local raisedArm, heldArm = if segmentedArms then 40 else 58, if segmentedArms then 54 else 78
		add({ "RightShoulder", "Right Shoulder" }, radians(raisedArm, -10, -10), radians(heldArm, -12, -25),
			Vector3.new(math.rad(104) + pitch, yaw, math.rad(6)), nil, radians(0.35, 0, 0))
		add({ "LeftShoulder", "Left Shoulder" }, radians(raisedArm, 10, 10), radians(heldArm, 12, 25), radians(65, 5, 16), nil, radians(0.35, 0, 0))
		add({ "RightElbow" }, radians(58, 0, 0), radians(92, 0, 0), radians(8, 0, 0))
		add({ "LeftElbow" }, radians(58, 0, 0), radians(92, 0, 0), radians(48, 0, 0))
		add({ "RightWrist" }, radians(-8, 0, 6), radians(-16, -8, 12), radians(17, 0, -5))
		add({ "LeftWrist" }, radians(-8, 0, -6), radians(-16, 8, -12), radians(-4, 0, -6))
		poses[owner] = { character = character, joints = joints, started = math.min(startedAt or readClock(), release - 0.06), release = release, life = character:GetAttribute("CombatLife"), direction = direction }
		local clip = if clips then clips:FindFirstChild("WarlockCast") else nil
		if clip and clip:IsA("AnimationClip") then
			local created = poses[owner]
			created.native = Native.new(character, clip)
			if created.native then
                local waistFound = false
                for index = #joints, 1, -1 do
                    local joint = joints[index]
                    if joint.name ~= "Waist" then continue end
                    local attachment = if joint.motor:IsA("AnimationConstraint") then joint.motor.Attachment0 else nil
                    if joint.motor.Name == "RootJoint" or (attachment and attachment.Name == "RootRigAttachment") then table.remove(joints, index)
                    else waistFound = true end
                end
                if not waistFound then add({"Waist"}, Vector3.zero, Vector3.zero, Vector3.zero) end
                for _, name in NativeLocomotion.joints do add({name}, Vector3.zero, Vector3.zero, Vector3.zero, nil, nil, true) end
                add({"Root", "RootJoint"}, Vector3.zero, Vector3.zero, Vector3.zero, nil, nil, true, true)
                created.lowerWeight, created.lastFrame = 0, readClock()
                if player == Players.LocalPlayer and direction then created.facing = Facing.new(character, direction) end
            end
        end
	end
    function pose.preview(owner: number, requestId: number, life: number, direction: Vector3): boolean
        if poses[owner] then return false end
        local player = Players:GetPlayerByUserId(owner)
        if not player or not player.Character or player.Character:GetAttribute("CombatLife") ~= life then return false end
        local now = readClock()
        pose.begin(owner, math.huge, direction, now)
        local current = poses[owner]
        if not current then return false end
        local Timeline = require(script.Parent.PreparationTimeline)
        current.preview, current.requestId, current.timeline = true, requestId, Timeline.new(now)
        return true
    end
    function pose.cancelPreview(owner: number, requestId: number?)
        local current = poses[owner]
        if current and current.preview and (requestId == nil or current.requestId == requestId) then pose.stop(owner) end
    end
    function pose.active(owner: number): boolean return poses[owner] ~= nil end
	function pose.step(now: number)
		for owner, current in poses do
			local player = Players:GetPlayerByUserId(owner)
			local humanoid = current.character:FindFirstChildOfClass("Humanoid")
			local root = current.character:FindFirstChild("HumanoidRootPart")
			if not player or player.Character ~= current.character or not humanoid or humanoid.Health <= 0 or now >= current.release + RELEASE + RECOVERY
                or current.character:GetAttribute("CombatLife") ~= current.life
                or (current.preview and now - current.started >= 2.5)
                or not root or not root:IsA("BasePart") or root.Anchored then
				pose.stop(owner); continue
			end
		end
	end
	-- Animator runs before PreSimulation. RenderStepped is too early to own this overlay.
    function pose.beforePose()
        for _, current in poses do
            for _, joint in current.joints do
                if joint.motor.Parent and joint.lastApplied and joint.motor.Transform == joint.lastApplied and joint.lastBase then setTransform(joint.motor, joint.lastBase) end
                joint.lastApplied = nil
            end
        end
    end
    function pose.preparePose(now: number)
        pose.step(now)
        for _, current in poses do
            if current.native then
                current.native.prepare(NativeTiming.time(now, current.started, current.release,
                    current.release + RELEASE + RECOVERY, 0.708333313, 1.20833337, current.timeline))
            end
        end
    end
    function pose.afterPose(now: number, delta: number?)

		pose.step(now)
		for _, current in poses do
			if current.native then current.native.capture() end
            if current.native then
                local frameDelta = delta or math.max(0, now - (current.lastFrame or now))
                current.lastFrame = now
                if current.facing then current.facing.step(now, current.release, frameDelta) end
                local humanoid = current.character:FindFirstChildOfClass("Humanoid")
                local root = current.character:FindFirstChild("HumanoidRootPart")
                if humanoid and root and root:IsA("BasePart") then
                    current.lowerWeight = NativeLocomotion.weight(humanoid, root, current.lowerWeight or 0, frameDelta)
                    if current.direction and current.direction.Magnitude > 0.1 then
                        local aim = root.CFrame:VectorToObjectSpace(current.direction.Unit)
                        local pitch = math.clamp(math.asin(math.clamp(aim.Y, -1, 1)), -0.4, 0.6)
                        local yaw = math.clamp(math.atan2(-aim.X, -aim.Z), -0.5, 0.5)
                        for _, joint in current.joints do
                            joint.aimFocus = if joint.name == "Waist" then Vector3.new(0, yaw * 0.25, 0)
                                else if joint.name == "Neck" then Vector3.new(pitch * 0.55, yaw * 0.65, 0) else Vector3.zero
                            joint.aimRelease = if joint.name == "Neck" then joint.aimFocus
                                else if joint.name == "RightShoulder" then Vector3.new(pitch, yaw, 0) else Vector3.zero
                        end
                    end
                end
            end
			local preparing = now < current.release
			local progress = if current.timeline and preparing then current.timeline.progress(now)
                else math.clamp((now - current.started) / math.max(0.06, current.release - current.started), 0, 1)
			local rise = smooth(progress / 0.32)
			local gather = smooth((progress - 0.32) / 0.2)
			local focus = smooth((progress - 0.72) / 0.24)
			local breath = math.sin((now - current.started) * 4) * smooth((progress - 0.52) / 0.12) * (1 - smooth((progress - 0.9) / 0.1))
			local snap = smooth((now - current.release) / RELEASE)
			local recovery = 1 - smooth((now - current.release - RELEASE) / RECOVERY)
			for _, joint in current.joints do
				if not joint.motor.Parent then continue end
				local held = joint.charge:Lerp(joint.focus, focus)
				local gathered = joint.raised:Lerp(held, gather) + joint.breath * breath
				local angles = if preparing then if progress < 0.32 then joint.raised * rise else gathered
					else joint.focus:Lerp(joint.release, snap) * recovery
				local base = joint.motor.Transform
				-- Unanimated joints retain our previous value; remove that overlay before applying the next.
				if joint.lastApplied and base == joint.lastApplied and joint.lastBase then base = joint.lastBase end
                if joint.lower and (current.lowerWeight or 0) == 0 then
                    setTransform(joint.motor, base); joint.lastBase, joint.lastApplied = base, nil
                    continue
                end
				local parentRotation = CFrame.Angles(angles.X, angles.Y, angles.Z)
				local localRotation = if current.native then (if joint.support then current.native.support(joint.motor) else current.native.sample(joint.motor)) or CFrame.identity
					else joint.rest:Inverse() * parentRotation * joint.rest
				if current.native then
					local aim = if preparing then joint.aimFocus * focus
						else joint.aimFocus:Lerp(joint.aimRelease, snap) * recovery
					localRotation = joint.rest:Inverse() * CFrame.Angles(aim.X, aim.Y, aim.Z) * joint.rest * localRotation
                    if joint.lower then localRotation = CFrame.identity:Lerp(localRotation, current.lowerWeight or 0) end
				end
				setTransform(joint.motor, localRotation * base)
				joint.lastBase, joint.lastApplied = base, joint.motor.Transform
			end
		end
    end
    local simulation: RBXScriptConnection? = nil
    local animation: RBXScriptConnection? = nil
    if not manualFrames then animation = RunService.PreAnimation:Connect(function()
        pose.beforePose(); pose.preparePose(readClock())
    end) end
    if not manualFrames then simulation = RunService.PreSimulation:Connect(function(delta: number) pose.afterPose(readClock(), delta) end) end
	function pose.destroy()
        if animation then animation:Disconnect() end
        if simulation then simulation:Disconnect() end
		for owner in poses do pose.stop(owner) end
	end
	return pose
end
return CastPose
