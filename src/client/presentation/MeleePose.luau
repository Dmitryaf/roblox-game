--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MeleePose = {}
local STROKE_LEAD, STROKE_TAIL, RECOVERY = 0.08, 0.04, 0.41
type Motor = Motor6D | AnimationConstraint
type Joint = { motor: Motor, rest: CFrame, charge: Vector3, slash: Vector3, base: CFrame?, applied: CFrame? }
type Swing = { character: Model, joints: { Joint }, started: number, hitAt: number, expires: number }
local function radians(x: number, y: number, z: number): Vector3 return Vector3.new(math.rad(x), math.rad(y), math.rad(z)) end
local function smooth(t: number): number t = math.clamp(t, 0, 1); return t * t * (3 - 2 * t) end
local function transform(motor: Motor, value: CFrame)
	if motor:IsA("Motor6D") then motor.Transform = value else (motor :: AnimationConstraint).Transform = value end
end
function MeleePose.new()
	local swings: { [number]: Swing } = {}
	local pose = {}
	function pose.stop(owner: number)
		local swing = swings[owner]
		if swing then
			for _, joint in swing.joints do
				if joint.motor.Parent and joint.applied and joint.base and joint.motor.Transform == joint.applied then transform(joint.motor, joint.base) end
			end
		end
		swings[owner] = nil
	end
	function pose.begin(owner: number, hitAt: number, startedAt: number?, expiresAt: number?)
		pose.stop(owner)
		local player = Players:GetPlayerByUserId(owner)
		local character = if player then player.Character else nil
		if not character then return end
		local joints: { Joint } = {}
		local descendants = character:GetDescendants()
		local function add(names: { string }, charge: Vector3, slash: Vector3)
			for _, candidate in descendants do
				if not candidate:IsA("Motor6D") and not candidate:IsA("AnimationConstraint") then continue end
				local attachment = if candidate:IsA("AnimationConstraint") then candidate.Attachment0 else nil
				for _, name in names do
					if candidate.Name ~= name and not (attachment and attachment.Name == name .. "RigAttachment") then continue end
					local rest = if candidate:IsA("Motor6D") then candidate.C0.Rotation else if attachment then attachment.CFrame.Rotation else CFrame.identity
					table.insert(joints, {motor = candidate, rest = rest, charge = charge, slash = slash})
					return
				end
			end
		end
		add({"Waist", "RootJoint"}, radians(-4, -26, 3), radians(2, 39, -5))
		add({"Neck"}, radians(0, 15, 0), radians(0, -15, 0))
		add({"RightShoulder", "Right Shoulder"}, radians(39, -48, 32), radians(102, 43, -52))
		add({"RightElbow"}, radians(61, 0, 0), radians(10, 0, 0))
		add({"RightWrist"}, radians(-12, -15, 10), radians(12, 10, -14))
		add({"LeftShoulder", "Left Shoulder"}, radians(25, 10, -23), radians(39, -16, 26))
		add({"LeftElbow"}, radians(43, 0, 0), radians(29, 0, 0))
		swings[owner] = {character = character, joints = joints, started = startedAt or hitAt - 0.3,
			hitAt = hitAt, expires = expiresAt or hitAt + 0.45}
	end
	function pose.step(now: number)
		for owner, swing in swings do
			local player = Players:GetPlayerByUserId(owner)
			local humanoid = swing.character:FindFirstChildOfClass("Humanoid")
			if not player or player.Character ~= swing.character or not humanoid or humanoid.Health <= 0
				or swing.character:GetAttribute("CombatClass") ~= "warrior" or now >= swing.expires then pose.stop(owner) end
		end
	end
	local simulation = RunService.PreSimulation:Connect(function()
		local now = workspace:GetServerTimeNow()
		pose.step(now)
		for _, swing in swings do
			local strokeAt = swing.hitAt - STROKE_LEAD
			local preparing = now < strokeAt
			local load = smooth((now - swing.started) / math.max(0.05, strokeAt - swing.started))
			-- At contact the shoulder has crossed roughly half the arc; the blade is already moving.
			local stroke = math.clamp((now - strokeAt) / (STROKE_LEAD + STROKE_TAIL), 0, 1) ^ 1.5
			local recovery = 1 - smooth((now - swing.hitAt - STROKE_TAIL) / RECOVERY)
			for _, joint in swing.joints do
				if not joint.motor.Parent then continue end
				local angles = if preparing then joint.charge * load else joint.charge:Lerp(joint.slash, stroke) * recovery
				local base = joint.motor.Transform
				if joint.applied and base == joint.applied and joint.base then base = joint.base end
				local rotation = joint.rest:Inverse() * CFrame.Angles(angles.X, angles.Y, angles.Z) * joint.rest
				transform(joint.motor, rotation * base)
				joint.base, joint.applied = base, joint.motor.Transform
			end
		end
	end)
	function pose.destroy()
		simulation:Disconnect()
		for owner in swings do pose.stop(owner) end
	end
	return pose
end
return MeleePose
