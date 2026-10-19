--!strict
-- Disposable Studio fixture. No match scoring or public-game map is implied.
local TestArena = {}
function TestArena.create()
	local folder = Instance.new("Folder")
	local spawns: { CFrame } = {}
	folder.Name = "WarlockTestArena"
	local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.Position, p.Color = name, size, position, color
		p.Anchored = true
		p.Material = Enum.Material.Slate
		p.TopSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end
	local stone = Color3.fromRGB(57, 53, 68)
	part("Floor", Vector3.new(160, 2, 160), Vector3.new(0, -1, 0), stone)
	for _, x in { -81, 81 } do part("Wall", Vector3.new(2, 24, 164), Vector3.new(x, 11, 0), stone) end
	for _, z in { -81, 81 } do part("Wall", Vector3.new(160, 24, 2), Vector3.new(0, 11, z), stone) end
	part("Cover", Vector3.new(18, 10, 3), Vector3.new(-23, 5, -15), stone)
	part("Cover", Vector3.new(3, 10, 18), Vector3.new(23, 5, 12), stone)
	for _, x in { -45, 45 } do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "TestSpawn"
		spawn.Size = Vector3.new(10, 1, 10)
		spawn.Position = Vector3.new(x, 0.5, 40)
		spawn.Anchored, spawn.Neutral = true, true
		spawn.Duration = 0
		spawn.Material = Enum.Material.Slate
		spawn.Color = Color3.fromRGB(92, 69, 119)
		spawn.Parent = folder
		table.insert(spawns, spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2, 0))
	end
	local target = Instance.new("Model")
	target.Name = "Мишень"
	target:SetAttribute("TrainingTarget", true)
	local root = part("HumanoidRootPart", Vector3.new(3, 5, 2), Vector3.new(0, 2.5, -36), Color3.fromRGB(160, 90, 100))
	root.Parent = target
	local head = part("Head", Vector3.new(2, 2, 2), Vector3.new(0, 6, -36), Color3.fromRGB(205, 155, 115))
	head.Parent = target
	local health = Instance.new("Humanoid")
	health.RequiresNeck = false
	health.BreakJointsOnDeath = false
	health.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	health.Parent = target
	target.PrimaryPart = root
	target.Parent = folder
	folder.Parent = workspace
	return folder, spawns
end
return TestArena
