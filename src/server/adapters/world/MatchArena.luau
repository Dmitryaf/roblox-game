--!strict
-- Physical bounds and spawn contracts remain explicit; original sanctuary art is separately owned.
local Stonework = require(script.Parent.ShrineStonework)
local Courtyard = require(script.Parent.ShrineCourtyard)
local Sanctum = require(script.Parent.TrainingSanctum)
local MatchArena = {}
function MatchArena.create()
	local folder = Instance.new("Folder")
	folder.Name = "ControlArena"
	local function part(name: string, size: Vector3, at: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.Position, p.Color = name, size, at, color
		p.Anchored, p.TopSurface = true, Enum.SurfaceType.Smooth
		p.Material = Enum.Material.Slate
		p.Parent = folder
		return p
	end
	local stone = Stonework.colors.stone
	part("ArenaFloor", Vector3.new(192, 2, 288), Vector3.new(0, -1, 0), stone)
	for _, x in { -97, 97 } do part("ArenaWall", Vector3.new(2, 40, 292), Vector3.new(x, 19, 0), stone) end
	for _, z in { -145, 145 } do part("ArenaWall", Vector3.new(192, 40, 2), Vector3.new(0, 19, z), stone) end
	-- Offset screens interrupt direct fire from the objective toward either spawn.
	for _, sign in { -1, 1 } do
		part("SpawnScreen", Vector3.new(42, 12, 4), Vector3.new(0, 6, sign * 80), stone)
	end
	local zone = part("ControlZone", Vector3.new(36, 0.12, 36), Vector3.new(0, 0.06, 0), Color3.fromRGB(159, 139, 186))
	zone.CanCollide, zone.CanQuery, zone.CanTouch = false, false, false
	zone.Material, zone.Transparency = Enum.Material.Neon, 0.9
	local function label(p: BasePart, text: string)
		local gui = Instance.new("BillboardGui")
		gui.Size, gui.StudsOffset, gui.AlwaysOnTop = UDim2.fromOffset(240, 50), Vector3.new(0, 5, 0), true
		gui.AlwaysOnTop, gui.MaxDistance = false, 110
		local t = Instance.new("TextLabel")
		t.Size, t.BackgroundTransparency, t.Text = UDim2.fromScale(1, 1), 1, text
		t.Font, t.TextSize, t.TextColor3 = Enum.Font.GothamBold, 18, Color3.new(1, 1, 1)
		t.Parent, gui.Parent = gui, p
	end
	label(zone, "УДЕРЖИВАЙТЕ ЗОНУ")
	for team = 1, 2 do
		local z = if team == 1 then 118 else -118
		local pad = part("Team" .. tostring(team) .. "Pad", Vector3.new(40, 0.1, 28), Vector3.new(0, 0.05, z),
			if team == 1 then Color3.fromRGB(57, 143, 196) else Color3.fromRGB(215, 133, 64))
		pad.CanCollide, pad.CanQuery, pad.CanTouch, pad.Transparency = false, false, false, 0.6
		label(pad, if team == 1 then "A · СТАРТОВАЯ ПЛОЩАДКА" else "B · СТАРТОВАЯ ПЛОЩАДКА")
	end
	part("TrainingFloor", Vector3.new(72, 2, 144), Vector3.new(230, -1, 0), stone)
	for _, x in {193, 267} do part("TrainingWall", Vector3.new(2, 32, 148), Vector3.new(x, 15, 0), stone) end
	for _, z in {-73, 73} do part("TrainingWall", Vector3.new(72, 32, 2), Vector3.new(230, 15, z), stone) end
	local target = Instance.new("Model")
	target.Name = "Мишень"
	target:SetAttribute("TrainingTarget", true)
	local root = part("HumanoidRootPart", Vector3.new(3, 5, 2), Vector3.new(230, 2.5, -38), Stonework.colors.shadow)
	root.Parent = target
	local head = part("Head", Vector3.new(2, 2, 2), Vector3.new(230, 6, -38), Stonework.colors.edge)
	head.Parent = target
	local health = Instance.new("Humanoid")
	health.RequiresNeck, health.BreakJointsOnDeath = false, false
	health.Parent, target.PrimaryPart = target, root
	target.Parent = folder
	label(root, "ТРЕНИРОВКА · МИШЕНЬ")
	Courtyard.create(folder)
	Sanctum.create(folder)
	folder.Parent = workspace
	local arena = { folder = folder }
	local slots: { [number]: { team: number, index: number } } = {}
	local trainingSlots: { [number]: number } = {}
	function arena.forget(owner: number) slots[owner] = nil; trainingSlots[owner] = nil end
	function arena.spawn(team: number?, owner: number): CFrame
		local slot = slots[owner]
		if not team then
			slots[owner] = nil
			local index = trainingSlots[owner] or 0
			if index == 0 then
				local used: { [number]: boolean } = {}
				for _, assigned in trainingSlots do used[assigned] = true end
				index = 1
				while used[index] do index += 1 end
				trainingSlots[owner] = index
			end
			local position = Vector3.new(205 + ((index - 1) % 6) * 10, 0.1, 60 - math.floor((index - 1) / 6) * 12)
			return CFrame.lookAt(position, Vector3.new(230, 0.1, -38))
		elseif not slot or slot.team ~= team then
			local used: { [number]: boolean } = {}
			for other, assigned in slots do if other ~= owner and assigned.team == team then used[assigned.index] = true end end
			local index = 1
			while used[index] and index < 3 do index += 1 end
			slot = { team = team, index = index }
			slots[owner] = slot :: { team: number, index: number }
		end
		trainingSlots[owner] = nil
		assert(slot)
		local x = (slot.index - 2) * 10
		return CFrame.lookAt(Vector3.new(x, 0.1, if team == 1 then 118 else -118), Vector3.new(x, 0.1, 0))
	end
	return arena
end
return MatchArena
