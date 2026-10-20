--!strict
-- Local material vocabulary for the arrow. Every instance is owned by its effect root.
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local Matter = {}

function Matter.part(parent: Instance, name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.TopSurface, p.BottomSurface = Enum.Material.Neon, Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function Matter.light(parent: BasePart, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, brightness, range
	light.Shadows, light.Parent = false, parent
	return light
end

function Matter.particles(parent: Instance, smoke: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = if smoke then "ShadowVapour" else "TornFlame"
	e.Texture = if smoke then Style.textures.smoke else Style.textures.flame
	e.Color = ColorSequence.new(if smoke then Style.color else Style.flame)
	e.LightEmission = if smoke then 0.15 else 0.8
	e.LightInfluence = if smoke then 0.6 else 0
	e.Lifetime = NumberRange.new(0.25, if smoke then 0.8 else 0.45)
	e.Speed, e.SpreadAngle = NumberRange.new(0.3, 1.5), Vector2.new(45, 45)
	e.Rotation, e.RotSpeed = NumberRange.new(-180, 180), NumberRange.new(-75, 75)
	e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.25, 0.25), NumberSequenceKeypoint.new(1, 1)})
	e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.25, 1.7), NumberSequenceKeypoint.new(1, 0.1)})
	e.Rate, e.Parent = 0, parent
	return e
end

function Matter.trail(parent: BasePart, color: Color3, width: number, lifetime: number)
	local a, b = Instance.new("Attachment"), Instance.new("Attachment")
	a.Position, b.Position = Vector3.new(-width / 2, 0, 0), Vector3.new(width / 2, 0, 0)
	a.Parent, b.Parent = parent, parent
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a, b
	trail.Color, trail.LightEmission, trail.FaceCamera = ColorSequence.new(color), 0.75, true
	trail.Lifetime, trail.MinLength = lifetime, 0.08
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Texture, trail.TextureMode = Style.textures.flame, Enum.TextureMode.Stretch
	trail.Parent = parent
	return trail
end
return Matter
