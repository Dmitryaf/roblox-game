--!strict
-- A small vocabulary of original masonry. Decorative geometry never participates in combat queries.
local Stonework = {}
Stonework.colors = {
	stone = Color3.fromRGB(91, 104, 99), shadow = Color3.fromRGB(55, 67, 66),
	edge = Color3.fromRGB(155, 145, 119), light = Color3.fromRGB(127, 137, 124),
	ink = Color3.fromRGB(43, 38, 62), emerald = Color3.fromRGB(75, 179, 130),
	violet = Color3.fromRGB(123, 84, 159), moss = Color3.fromRGB(71, 94, 65),
	leaf = Color3.fromRGB(100, 119, 75), bronze = Color3.fromRGB(119, 99, 66),
}
function Stonework.block(parent: Instance, name: string, size: Vector3, frame: CFrame,
	color: Color3, material: Enum.Material?, physical: boolean?): Part
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame = name, size, frame
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch = physical == true, physical == true, false
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part.Material, part.Color = material or Enum.Material.Slate, color
	part.CastShadow = physical == true or size.Y > 0.3
	part.Parent = parent
	return part
end
function Stonework.round(parent: Instance, name: string, center: Vector3, diameter: number, height: number,
	color: Color3, material: Enum.Material?): Part
	local part = Stonework.block(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end
function Stonework.ring(parent: Instance, name: string, center: Vector3, radius: number, width: number,
	color: Color3, segments: number, material: Enum.Material?)
	for index = 1, segments do
		local angle = (index - 0.5) * math.pi * 2 / segments
		local p = center + Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		Stonework.block(parent, name, Vector3.new(width, 0.035, radius * 2 * math.tan(math.pi / segments) + 0.04),
			CFrame.new(p) * CFrame.Angles(0, angle + math.pi / 2, 0), color, material)
	end
end
function Stonework.pillar(parent: Instance, center: Vector3, height: number, width: number, broken: boolean)
	local c = Stonework.colors
	Stonework.block(parent, "Footing", Vector3.new(width + 2, 0.7, width + 2), CFrame.new(center + Vector3.new(0, 0.35, 0)), c.shadow)
	Stonework.block(parent, "WarmFootEdge", Vector3.new(width + 1.5, 0.35, width + 1.5), CFrame.new(center + Vector3.new(0, 0.9, 0)), c.edge)
	local courses = math.max(2, math.floor(height / 3.5))
	for course = 1, courses do
		local h = (height - 2) / courses
		local skew = if broken and course == courses then CFrame.Angles(0.04, 0.08, -0.07) else CFrame.identity
		Stonework.block(parent, "DressedStone", Vector3.new(width, h - 0.12, width),
			CFrame.new(center + Vector3.new(0, 1.2 + (course - 0.5) * h, 0)) * skew,
			if course % 2 == 0 then c.stone else c.light)
	end
	for _, sign in {-1, 1} do
		Stonework.block(parent, "RecessedFlute", Vector3.new(0.28, height - 3, 0.12),
			CFrame.new(center + Vector3.new(sign * width * 0.29, height / 2 + 0.5, width / 2 + 0.03)), c.shadow)
	end
	if not broken then
		Stonework.block(parent, "CapitalShadow", Vector3.new(width + 0.8, 0.6, width + 0.8), CFrame.new(center + Vector3.new(0, height, 0)), c.shadow)
		Stonework.block(parent, "CrownedStone", Vector3.new(width + 1.6, 0.8, width + 1.6), CFrame.new(center + Vector3.new(0, height + 0.7, 0)), c.edge)
	end
end
function Stonework.arch(parent: Instance, center: Vector3, radius: number, spring: number, thickness: number, facing: number)
	local c = Stonework.colors
	local frame = CFrame.new(center) * CFrame.Angles(0, facing, 0)
	for _, sign in {-1, 1} do
		Stonework.pillar(parent, (frame * CFrame.new(sign * radius, 0, 0)).Position, spring, thickness + 1, false)
	end
	for index = 0, 12 do
		local angle = math.pi * index / 12
		local pos = Vector3.new(math.cos(angle) * radius, spring + math.sin(angle) * radius, 0)
		Stonework.block(parent, "ArchVoussoir", Vector3.new(thickness, radius * math.pi / 12 - 0.1, thickness + 0.7),
			frame * CFrame.new(pos) * CFrame.Angles(0, 0, angle), if index == 6 then c.edge else c.stone)
	end
end
function Stonework.growth(parent: Instance, center: Vector3, scale: number, seed: number)
	local c = Stonework.colors
	for index = 1, 5 do
		local angle = index * 2.4 + seed
		local part = Stonework.block(parent, "FernFrond", Vector3.new(0.6, 2.2, 2.8) * scale,
			CFrame.new(center + Vector3.new(math.sin(angle) * scale, scale * 0.85, math.cos(angle) * scale))
			* CFrame.Angles(-0.45, angle, 0.2), if index % 2 == 0 then c.leaf else c.moss, Enum.Material.Grass)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType, mesh.Parent = Enum.MeshType.Wedge, part
	end
end
function Stonework.flame(parent: Instance, center: Vector3, color: Color3)
	local c = Stonework.colors
	Stonework.round(parent, "BrazierFoot", center, 2.8, 0.4, c.shadow)
	Stonework.round(parent, "BronzeBowl", center + Vector3.new(0, 0.5, 0), 2.4, 0.6, c.bronze, Enum.Material.Metal)
	local heart = Stonework.block(parent, "BoundEmber", Vector3.new(0.65, 1.5, 0.65),
		CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.6, 0.16), color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = color, 0.7, 13, false
	light.Parent = heart
	for _, sign in {-1, 1} do
		Stonework.block(parent, "EmberShard", Vector3.new(0.3, 0.8, 0.3),
			CFrame.new(center + Vector3.new(sign * 0.55, 1.3, 0)) * CFrame.Angles(0, 0, sign * 0.4), color, Enum.Material.Neon)
	end
end
return Stonework
