--!strict
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local Matter = require(script.Parent.ChaosMatter)
local ChaosImpact = {}
type Tongue = { beam: Beam, near: Attachment, far: Attachment, angle: number, reach: number, height: number, width: number }

-- Textured, curved sheets leave gaps between the flames instead of enclosing the target in a sphere.
local function flameTongues(root: BasePart, random: Random): { Tongue }
	local tongues: { Tongue } = {}
	for index = 1, 7 do
		local angle = index * math.pi * 2 / 7 + random:NextNumber(-0.16, 0.16)
		local near, far = Instance.new("Attachment"), Instance.new("Attachment")
		near.Name, far.Name = "RuptureTongueFoot", "RuptureTongueTip"
		near.Parent, far.Parent = root, root
		local beam = Instance.new("Beam")
		beam.Name, beam.Attachment0, beam.Attachment1 = "RaggedChaosTongue", near, far
		beam.Texture, beam.TextureMode, beam.TextureSpeed = Style.textures.flame, Enum.TextureMode.Stretch, 1.4
		beam.Color = ColorSequence.new(if index % 3 == 0 then Style.color else Style.flame, Style.core)
		beam.FaceCamera, beam.Segments, beam.LightEmission, beam.LightInfluence = true, 6, 0.8, 0
		beam.CurveSize0, beam.CurveSize1 = random:NextNumber(0.4, 1.5), random:NextNumber(-0.7, 0.7)
		beam.Parent = root
		-- Three particles at each flame's foot supplement the open sheets without adding a fog bank.
		local sparks = Matter.particles(near, false)
		sparks.Size, sparks.Speed = NumberSequence.new(0.9, 0), NumberRange.new(5, 9)
		sparks.Lifetime, sparks.Acceleration = NumberRange.new(0.3, 0.65), Vector3.new(0, 5, 0)
		sparks:Emit(3)
		table.insert(tongues, { beam = beam, near = near, far = far, angle = angle,
			reach = random:NextNumber(2.4, 3.3), height = random:NextNumber(5, 8.5), width = random:NextNumber(1.45, 2.2) })
	end
	return tongues
end

function ChaosImpact.new(folder: Folder, position: Vector3, teleport: boolean, seed: number, now: number)
	local root = Matter.part(folder, "ChaosAftermath", Vector3.one * 0.1, Style.shadow)
	root.Position, root.Transparency = position, 1
	game:GetService("Debris"):AddItem(root, 1.8)
	local flash = Matter.part(root, "Rupture", Vector3.one, if teleport then Style.color else Style.core)
	flash.Shape = Enum.PartType.Ball
	local light = Matter.light(root, if teleport then Style.color else Style.flame, if teleport then 5 else 8, if teleport then 18 else 24)
	local fire, smoke = Matter.particles(root, false), Matter.particles(root, true)
	fire.Speed, fire.SpreadAngle = NumberRange.new(3, 11), Vector2.new(180, 180)
	fire.Lifetime, fire.Drag = NumberRange.new(0.16, 0.5), 4
	fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(0.2, 2.6), NumberSequenceKeypoint.new(1, 0)})
	smoke.Speed, smoke.SpreadAngle = NumberRange.new(1, 4), Vector2.new(120, 120)
	smoke.Acceleration, smoke.Drag = Vector3.new(0, 1.8, 0), 3
	smoke.Lifetime, smoke.Size = NumberRange.new(0.5, 1.4), NumberSequence.new(1.5, 4)
	smoke.Transparency = NumberSequence.new(0.58, 1)
	if not teleport then
		fire.Speed, fire.Lifetime = NumberRange.new(5, 16), NumberRange.new(0.22, 0.65)
		fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(0.18, 3.6), NumberSequenceKeypoint.new(1, 0)})
		fire.Acceleration = Vector3.new(0, 4, 0)
		smoke.Speed, smoke.Size = NumberRange.new(2, 5), NumberSequence.new(2, 4.8)
		smoke.Transparency = NumberSequence.new(0.7, 1)
	end
	fire:Emit(if teleport then 14 else 30)
	smoke:Emit(if teleport then 7 else 10)
	local random = Random.new(seed)
	local tongues: { Tongue } = if teleport then {} else flameTongues(root, random)
	local fragments = {}
	for _ = 1, if teleport then 6 else 16 do
		local direction = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.2, 1), random:NextNumber(-1, 1)).Unit
		local shard = Matter.part(root, "Fracture", Vector3.new(if teleport then 0.08 else 0.13, if teleport then 0.12 else 0.2,
			random:NextNumber(if teleport then 0.7 else 1.3, if teleport then 1.8 else 2.8)), if random:NextNumber() < 0.4 then Style.color else Style.flame)
		table.insert(fragments, {part = shard, direction = direction, speed = random:NextNumber(if teleport then 6 else 10, if teleport then 12 else 18)})
	end
	local marks = {}
	-- A small floor remnant, not a circular area-of-effect telegraph.
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {folder}
	local ground = workspace:Raycast(position + Vector3.yAxis, Vector3.new(0, -9, 0), params)
	if ground and ground.Normal.Y > 0.9 then
		for i = 1, if teleport then 5 else 8 do
			local angle = i * math.pi * 2 / (if teleport then 5 else 8) + random:NextNumber(-0.2, 0.2)
			local length = random:NextNumber(if teleport then 0.7 else 1.3, if teleport then 1.7 else 3)
			local mark = Matter.part(root, "ScorchFissure", Vector3.new(if teleport then 0.07 else 0.12, 0.015, length), if i % 2 == 0 then Style.shadow else Style.flame)
			mark.CFrame = CFrame.new(ground.Position + Vector3.new(math.sin(angle) * length / 2, 0.025, math.cos(angle) * length / 2)) * CFrame.Angles(0, angle, 0)
			table.insert(marks, mark)
		end
	end
	local impact = {}
	function impact.step(at: number): boolean
		local age = at - now
		if age >= 1.8 then root:Destroy(); return false end
		local peak = math.clamp(age / (if teleport then 0.18 else 0.065), 0, 1)
		flash.CFrame = CFrame.new(position)
		flash.Size = (if teleport then Vector3.new(1, 1.3, 1) else Vector3.new(1, 1.22, 1)) * (0.4 + peak * (if teleport then 2.8 else 6.8))
		flash.Transparency = if teleport then math.clamp(age / 0.24, 0, 1) else 0.12 + math.clamp(age / 0.19, 0, 1) * 0.88
		light.Brightness = (if teleport then 5 else 8) * math.max(0, 1 - age / (if teleport then 0.42 else 0.5)) ^ 2
		for _, tongue in tongues do
			local opening = 0.15 + 0.85 * math.clamp(age / 0.11, 0, 1)
			local lift = math.max(0, age - 0.12) * 1.8
			local radius = tongue.reach * opening
			tongue.near.Position = Vector3.new(math.cos(tongue.angle) * radius * 0.2, -0.6 + lift, math.sin(tongue.angle) * radius * 0.2)
			tongue.far.Position = Vector3.new(math.cos(tongue.angle) * radius, tongue.height * opening + lift, math.sin(tongue.angle) * radius)
			tongue.near.Axis = Vector3.new(math.cos(tongue.angle), 0.6, math.sin(tongue.angle)).Unit
			tongue.far.Axis = Vector3.new(-math.cos(tongue.angle), 0.7, -math.sin(tongue.angle)).Unit
			tongue.beam.Width0 = tongue.width * (1 - math.clamp(age / 0.95, 0, 1) * 0.65)
			tongue.beam.Width1 = 0.15
			local fade = math.clamp((age - 0.16) / 0.8, 0, 1)
			tongue.beam.Transparency = NumberSequence.new(0.15 + fade * 0.85, 0.72 + fade * 0.28)
			tongue.beam.Enabled = age < 0.96
		end
		for _, fragment in fragments do
			local point = position + fragment.direction * fragment.speed * math.min(age, 0.4) + Vector3.new(0, -age * age * 5, 0)
			fragment.part.CFrame = CFrame.lookAt(point, point + fragment.direction)
			fragment.part.Transparency = math.clamp(age / (if teleport then 0.48 else 0.65), 0, 1)
		end
		for _, mark in marks do mark.Transparency = (if teleport then 0.3 else 0.15) + math.clamp(age / 1.6, 0, 1) * (if teleport then 0.7 else 0.85) end
		return true
	end
	function impact.destroy() root:Destroy() end
	impact.step(now)
	return impact
end
return ChaosImpact
