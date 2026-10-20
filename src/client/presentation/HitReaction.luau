--!strict
-- PoseLayers owns scheduling: restore reaction before action/locomotion, apply it last.
local Players = game:GetService("Players")
local Motion = require(script.Parent.HitReactionMotion)
local HitReaction = {}
type Motor = Motor6D | AnimationConstraint
type Joint = { motor: Motor, rest: CFrame, role: string, base: CFrame?, applied: CFrame? }
type Impulse = { kind: string, at: number, away: Vector3 }
type Cue = { sound: Sound, expires: number }
type Target = { model: Model, life: number, classId: any, player: Player?, human: Humanoid, root: BasePart,
	joints: { Joint }, impulses: { Impulse }, cues: { Cue }, seen: { [string]: number }, touched: number }
local channels = {
	{ names = { "Waist", "RootJoint" }, role = "torso" }, { names = { "Neck" }, role = "neck" },
	{ names = { "RightShoulder", "Right Shoulder" }, role = "right" }, { names = { "LeftShoulder", "Left Shoulder" }, role = "left" },
}
local function finite(value: any): boolean return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function vector(value: any): boolean return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z) end
local function write(motor: Motor, value: CFrame)
	if motor:IsA("Motor6D") then motor.Transform = value else (motor :: AnimationConstraint).Transform = value end
end
local function restore(joint: Joint)
	if joint.motor.Parent and joint.base and joint.applied and joint.motor.Transform == joint.applied then write(joint.motor, joint.base) end
	joint.base, joint.applied = nil, nil
end

function HitReaction.new()
	local targets: { [Model]: Target } = {}
	local stopped = false
	local reaction = {}
	local function valid(target: Target): boolean
		return target.model.Parent ~= nil and target.human.Parent == target.model and target.root.Parent == target.model and target.human.Health > 0
			and (target.model:GetAttribute("CombatLife") or 0) == target.life and target.model:GetAttribute("CombatClass") == target.classId
			and (not target.player or target.player.Character == target.model)
			and (not target.root.Anchored or target.model:GetAttribute("TrainingTarget") == true)
	end
	function reaction.cancel(model: Model, expectedLife: number?)
		local target = targets[model]
		if not target or (expectedLife ~= nil and target.life ~= expectedLife) then return end
		for _, joint in target.joints do restore(joint) end
		for _, cue in target.cues do cue.sound:Destroy() end
		targets[model] = nil
	end
	local function collect(model: Model): { Joint }
		local joints: { Joint } = {}
		local descendants = model:GetDescendants()
		for _, channel in channels do
			local found = false
			for _, motor in descendants do
				if not motor:IsA("Motor6D") and not motor:IsA("AnimationConstraint") then continue end
				local attachment = if motor:IsA("AnimationConstraint") then motor.Attachment0 else nil
				for _, name in channel.names do
					if motor.Name ~= name and not (attachment and attachment.Name == name .. "RigAttachment") then continue end
					local rest = if motor:IsA("Motor6D") then motor.C0.Rotation else if attachment then attachment.CFrame.Rotation else CFrame.identity
					table.insert(joints, { motor = motor, rest = rest, role = channel.role }); found = true; break
				end
				if found then break end
			end
		end
		return joints
	end
	local function cue(target: Target, kind: string, now: number)
		if #target.cues >= 4 then local previous = table.remove(target.cues, 1); if previous then previous.sound:Destroy() end end
		local sound = Instance.new("Sound")
		sound.Name = "HitReactionContact"
		sound.SoundId = if kind == "arrow" then "rbxasset://sounds/warlock-art-v2/impact.wav" else "rbxasset://sounds/warrior-v1/impact.wav"
		sound.Volume, sound.PlaybackSpeed = if kind == "heavy" then 0.3 else 0.2, if kind == "heavy" then 0.8 else if kind == "arrow" then 1.15 else 1.08
		sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.Parent = 5, 55, target.root
		sound:Play(); table.insert(target.cues, { sound = sound, expires = now + 0.65 })
	end
	function reaction.hit(event: any): boolean
		if stopped or type(event) ~= "table" then return false end
		local kind: string? = nil
		local sequence: any = nil
		local contact: any = nil
		if event.kind == "contact" then
			kind, sequence, contact = if event.style == "heavy" then "heavy" else "melee", event.swingId, event.contactId
		elseif event.kind == "ended" and event.reason == "hit" then kind, sequence, contact = "arrow", event.castId, 0
		else return false end
		local sourceKind = kind :: string
		local model, token = event.targetModel, event.targetLife
		local now = workspace:GetServerTimeNow()
		if typeof(model) ~= "Instance" or not model:IsA("Model") or not finite(token) or token < 0 or token % 1 ~= 0
			or not finite(event.owner) or not finite(event.life) or not finite(sequence) or sequence <= 0 or not finite(contact)
			or not finite(event.contactAt) or now - event.contactAt > 0.6 or event.contactAt - now > 0.1
			or not vector(event.sourcePosition) then return false end
		local human = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not human or not root or not root:IsA("BasePart") or (model:GetAttribute("CombatLife") or 0) ~= token then return false end
		local existing: Target? = targets[model]
		if existing and (existing.life ~= token or existing.human ~= human or existing.root ~= root) then reaction.cancel(model); existing = nil end
		local target: Target = existing or { model = model, life = token, classId = model:GetAttribute("CombatClass"), player = Players:GetPlayerFromCharacter(model),
			human = human, root = root, joints = collect(model), impulses = {}, cues = {}, seen = {}, touched = now }
		if not valid(target) then return false end
		local id = sourceKind .. ":" .. event.owner .. ":" .. event.life .. ":" .. sequence .. ":" .. contact
		if target.seen[id] then return false end
		if not existing then
			local count, oldest, oldestAt = 0, nil, math.huge
			for other, value in targets do count += 1; if value.touched < oldestAt then oldest, oldestAt = other, value.touched end end
			if count >= 12 and oldest then reaction.cancel(oldest) end
			targets[model] = target
		end
		local away = (root.Position - (event.sourcePosition :: Vector3)) * Vector3.new(1, 0, 1)
		if away.Magnitude < 0.01 and vector(event.direction) then away = event.direction * Vector3.new(1, 0, 1) end
		if away.Magnitude < 0.01 then away = -root.CFrame.LookVector * Vector3.new(1, 0, 1) end
		if away.Magnitude < 0.01 then return false end
		local seenCount, oldestSeen, oldestExpiry = 0, nil, math.huge
		for key, expires in target.seen do seenCount += 1; if expires < oldestExpiry then oldestSeen, oldestExpiry = key, expires end end
		if seenCount >= 32 and oldestSeen then target.seen[oldestSeen] = nil end
		target.seen[id], target.touched = now + 0.9, now
		if #target.impulses >= 4 then table.remove(target.impulses, 1) end
		table.insert(target.impulses, { kind = sourceKind, at = now, away = away.Unit })
		cue(target, sourceKind, now)
		return true
	end
	function reaction.beforePose()
		for _, target in targets do for _, joint in target.joints do restore(joint) end end
	end
	function reaction.step(now: number)
		if stopped then return end
		for model, target in targets do
			if not valid(target) then reaction.cancel(model); continue end
			for index = #target.impulses, 1, -1 do
				local impulse = target.impulses[index]
				if now >= impulse.at + Motion.duration(impulse.kind) then table.remove(target.impulses, index) end
			end
			for index = #target.cues, 1, -1 do
				if now >= target.cues[index].expires then target.cues[index].sound:Destroy(); table.remove(target.cues, index) end
			end
			for id, expires in target.seen do if now >= expires then target.seen[id] = nil end end
			if #target.impulses == 0 then
				for _, joint in target.joints do restore(joint) end
				if #target.cues == 0 and next(target.seen) == nil then targets[model] = nil end
			end
		end
	end
	function reaction.afterPose(now: number, _delta: number?)
		if stopped then return end
		reaction.step(now)
		for _, target in targets do
			if #target.impulses == 0 then continue end
			for _, joint in target.joints do
				if not joint.motor.Parent then continue end
				restore(joint)
				local base, angles = joint.motor.Transform, Vector3.zero
				for _, impulse in target.impulses do
					angles += Motion.sample(impulse.kind, joint.role, now - impulse.at, target.root.CFrame:VectorToObjectSpace(impulse.away))
				end
				local limit = math.rad(if joint.role == "torso" then 18 else if joint.role == "neck" then 7 else 16)
				angles = Vector3.new(math.clamp(angles.X, -limit, limit), math.clamp(angles.Y, -limit, limit), math.clamp(angles.Z, -limit, limit))
				local rotation = joint.rest:Inverse() * CFrame.Angles(angles.X, angles.Y, angles.Z) * joint.rest
				write(joint.motor, rotation * base); joint.base, joint.applied = base, joint.motor.Transform
			end
		end
	end
	function reaction.active(model: Model): boolean
		reaction.step(workspace:GetServerTimeNow())
		local target = targets[model]
		return target ~= nil and valid(target) and #target.impulses > 0
	end
	function reaction.destroy()
		if stopped then return end
		stopped = true
		for model in targets do reaction.cancel(model) end
	end
	return reaction
end
return HitReaction
