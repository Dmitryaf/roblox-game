--!strict
-- A low, open spiral of green vapour. It only moves local attachments and visual particles.
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local HandsVortex = {}
type Arm = { nodes: { Attachment }, beams: { Beam }, phase: number }
type Stream = { anchor: Attachment, emitter: ParticleEmitter, phase: number }

function HandsVortex.new(root: BasePart, radius: number)
	local arms: { Arm } = {}
	for index = 1, 3 do
		local nodes: { Attachment } = {}
		local beams: { Beam } = {}
		for node = 1, 6 do
			local attachment = Instance.new("Attachment")
			attachment.Name, attachment.Parent = "FelVortexNode", root
			table.insert(nodes, attachment)
			if node == 1 then continue end
			local beam = Instance.new("Beam")
			beam.Name, beam.Attachment0, beam.Attachment1 = "FelVapourSpiral", nodes[node - 1], attachment
			beam.Texture, beam.TextureMode, beam.TextureSpeed = Style.textures.smoke, Enum.TextureMode.Stretch, 0.65
			beam.Color = ColorSequence.new(Style.flame:Lerp(Color3.fromRGB(29, 130, 77), 0.5), Style.flame)
			beam.FaceCamera, beam.Segments, beam.LightEmission, beam.LightInfluence = true, 5, 0.35, 0.25
			beam.Width0, beam.Width1 = 1.2 + (node - 1) * 0.14, 1.25 + node * 0.14
			beam.CurveSize0, beam.CurveSize1 = 0.9, 0.9
			beam.Transparency, beam.Enabled, beam.Parent = NumberSequence.new(1), false, root
			table.insert(beams, beam)
		end
		table.insert(arms, {nodes = nodes, beams = beams, phase = (index - 1) * math.pi * 2 / 3})
	end
	local streams: { Stream } = {}
	for index = 1, 6 do
		local anchor = Instance.new("Attachment")
		anchor.Name, anchor.Parent = "InwardFelMist", root
		local mist = Instance.new("ParticleEmitter")
		mist.Name, mist.Texture = "GreenVortexVeil", Style.textures.smoke
		mist.Color = ColorSequence.new(Color3.fromRGB(42, 130, 65), Style.flame)
		mist.Rate, mist.Lifetime, mist.Speed = 0, NumberRange.new(0.65, 1.05), NumberRange.new(1.5, 2.5)
		mist.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(0.3, 2.7), NumberSequenceKeypoint.new(1, 3.5)})
		mist.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.25, 0.53), NumberSequenceKeypoint.new(1, 1)})
		mist.EmissionDirection, mist.SpreadAngle = Enum.NormalId.Front, Vector2.new(18, 12)
		mist.Drag, mist.Acceleration = 0.6, Vector3.new(0, 0.35, 0)
		mist.LightEmission, mist.LightInfluence = 0.25, 0.35
		mist.Rotation, mist.RotSpeed = NumberRange.new(-180, 180), NumberRange.new(22, 40)
		mist.Parent = anchor
		table.insert(streams, {anchor = anchor, emitter = mist, phase = index * math.pi / 3})
	end
	local vortex = {}
	function vortex.step(age: number, enabled: boolean, fading: number)
		local rise = if enabled then math.clamp(age / 0.22, 0, 1) * (1 - fading) else 0
		for _, arm in arms do
			for index, node in arm.nodes do
				local t = (index - 1) / 5
				local angle = arm.phase + age * 1.55 + t * 2.4
				local distance = radius * (0.84 - t * 0.68)
				local position = Vector3.new(math.cos(angle) * distance, 0.24 + t * 0.75 + math.sin(age * 2.4 + t) * 0.09, math.sin(angle) * distance)
				node.Position = position
				node.Axis = Vector3.new(-math.sin(angle), 0.08, math.cos(angle)).Unit
			end
			for index, beam in arm.beams do
				beam.Enabled = rise > 0
				-- The veil has transparent texture and separated arms, not an opaque surface over the area.
				beam.Transparency = NumberSequence.new(1 - rise * 0.52, 1 - rise * (0.58 - index * 0.025))
			end
		end
		for _, stream in streams do
			local angle = stream.phase + age * 1.3
			local distance = radius * (0.57 + math.sin(age * 1.8 + stream.phase) * 0.13)
			local position = Vector3.new(math.cos(angle) * distance, 0.55, math.sin(angle) * distance)
			stream.anchor.CFrame = CFrame.lookAt(position, Vector3.new(-math.sin(angle) * 1.2, 0.85, math.cos(angle) * 1.2))
			stream.emitter.Rate = 3 * rise
		end
	end
	return vortex
end
return HandsVortex
