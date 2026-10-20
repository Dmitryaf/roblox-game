--!strict
-- Client-only geometry follows the existing rig; it never participates in physics.
local WarlockCostume = {}
local cloth = Color3.fromRGB(28, 23, 35)
local purple = Color3.fromRGB(51, 32, 65)
local edge = Color3.fromRGB(117, 94, 64)
local iron = Color3.fromRGB(45, 43, 46)
local green = Color3.fromRGB(65, 167, 104)
type Piece = { part: BasePart, anchor: BasePart, offset: CFrame, drop: number, sway: number }

function WarlockCostume.new(character: Model): any
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	-- CharacterAdded precedes complete body replication. Do not hide a partial rig,
	-- infer its type from missing parts, or permanently omit a late limb.
	local required: { string } = if r15 then {
		"HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "RightUpperArm", "RightLowerArm", "RightHand", "RightFoot",
		"LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftFoot",
	} else { "HumanoidRootPart", "Head", "Torso", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
	for _, name in required do
		local body = character:FindFirstChild(name)
		if not body or not body:IsA("BasePart") then return nil end
	end
	local torso = character:FindFirstChild(if r15 then "UpperTorso" else "Torso") :: BasePart
	local head = character:FindFirstChild("Head") :: BasePart
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local pelvis = if r15 then character:FindFirstChild("LowerTorso") :: BasePart else torso
	local scale = math.clamp(torso.Size.X / 2, 0.8, 1.3)
	local folder = Instance.new("Folder")
	folder.Name = "WarlockCostume"
	folder.Parent = character
	local pieces: { Piece } = {}
	local hiddenParts: { [BasePart]: number } = {}
	local hiddenDecals: { [Decal]: number } = {}
	local function hide(item: Instance)
		if item:IsDescendantOf(folder) then return end
		if item:IsA("BasePart") then
			-- The camera owns LocalTransparencyModifier and resets it when its cache changes.
			-- A client-side Transparency override survives that update without changing the server.
			if hiddenParts[item] == nil then hiddenParts[item] = item.Transparency end
			item.Transparency = 1
		elseif item:IsA("Decal") then
			if hiddenDecals[item] == nil then hiddenDecals[item] = item.Transparency end
			item.Transparency = 1
		end
	end
	for _, item in character:GetDescendants() do hide(item) end
	local added = character.DescendantAdded:Connect(hide)
	local function piece(name: string, anchor: BasePart, size: Vector3, offset: CFrame, color: Color3, shape: string?, drop: number?, sway: number?): BasePart
		local p: BasePart = if shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
		p.Name, p.Size, p.Color = name, size * scale, color
		p.Anchored, p.Massless = true, true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Material = if color == edge or color == iron then Enum.Material.Metal else Enum.Material.Fabric
		p.CastShadow = true
		if shape == "round" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		local localOffset = CFrame.new(offset.Position * scale) * offset.Rotation
		p.CFrame = anchor.CFrame * localOffset * CFrame.new(0, -(drop or 0) * scale, 0)
		p.Parent = folder
		table.insert(pieces, { part = p, anchor = anchor, offset = localOffset, drop = (drop or 0) * scale, sway = sway or 0 })
		return p
	end
	-- The dark oval is recessed into a deep cloth hood, with a narrow brow opening.
	piece("HoodShell", head, Vector3.new(1.49, 1.65, 1.22), CFrame.new(0, 0.12, 0.08), cloth, "round")
	piece("HoodCrown", head, Vector3.new(1.1, 0.49, 0.92), CFrame.new(0, 0.8, 0.17) * CFrame.Angles(-0.15, 0, 0), purple, "wedge")
	piece("ShadowedMask", head, Vector3.new(1.06, 1.24, 0.16), CFrame.new(0, 0.05, -0.55), Color3.fromRGB(8, 10, 12), "round")
	for _, side in { -1, 1 } do
		piece("HoodFold", head, Vector3.new(0.23, 1.3, 0.34), CFrame.new(side * 0.59, -0.01, -0.46) * CFrame.Angles(0, side * 0.12, side * -0.18), purple, "wedge")
		piece("BrowEdge", head, Vector3.new(0.63, 0.08, 0.13), CFrame.new(side * 0.27, 0.55, -0.61) * CFrame.Angles(0, 0, side * 0.12), edge)
		local eye = piece("DemonicEye", head, Vector3.new(0.25, 0.065, 0.055), CFrame.new(side * 0.23, 0.16, -0.65) * CFrame.Angles(0, 0, side * 0.13), green)
		eye.Material = Enum.Material.Neon
	end
	piece("RobeTorso", torso, Vector3.new(1.91, if r15 then 1.55 else 1.9, 0.98), CFrame.new(0, -0.05, 0), cloth, "round")
	for _, side in { -1, 1 } do
		piece("CrossedLapel", torso, Vector3.new(0.67, 1.6, 0.13), CFrame.new(side * 0.36, -0.05, -0.51) * CFrame.Angles(0, 0, side * -0.2), purple)
		piece("LapelBinding", torso, Vector3.new(0.045, 1.52, 0.045), CFrame.new(side * 0.11, -0.06, -0.6) * CFrame.Angles(0, 0, side * -0.2), edge)
		piece("Mantle", torso, Vector3.new(0.94, 0.58, 1.21), CFrame.new(side * 0.99, 0.48, 0.04) * CFrame.Angles(0, 0, side * -0.23), purple, "wedge")
		piece("Pauldron", torso, Vector3.new(0.94, 0.27, 1.12), CFrame.new(side * 1.05, 0.68, 0.01) * CFrame.Angles(0, 0, side * -0.2), iron, "wedge")
		piece("PauldronRim", torso, Vector3.new(0.065, 0.21, 1.02), CFrame.new(side * 1.45, 0.54, 0.01) * CFrame.Angles(0, 0, side * -0.2), edge)
	end
	local beltY = if r15 then 0.12 else -0.63
	piece("Belt", pelvis, Vector3.new(1.96, 0.27, 1.06), CFrame.new(0, beltY, 0), iron)
	piece("Buckle", pelvis, Vector3.new(0.42, 0.38, 0.13), CFrame.new(0, beltY, -0.6), edge)
	local emblem = piece("BeltSigil", pelvis, Vector3.new(0.14, 0.25, 0.05), CFrame.new(0, beltY, -0.69) * CFrame.Angles(0, 0, 0.25), green, "wedge")
	emblem.Material = Enum.Material.Neon
	-- Separate overlapping gores expose the stride while reading as a long, split robe.
	local top = if r15 then 0.0 else -0.58
	for index, panel in {
		{ -0.48, -0.53, -0.08 }, { 0.48, -0.53, 0.08 },
		{ -0.88, 0.05, -0.12 }, { 0.88, 0.05, 0.12 },
		{ -0.55, 0.52, -0.07 }, { 0, 0.59, 0 }, { 0.55, 0.52, 0.07 },
	} do
		local pivot = CFrame.new(panel[1], top, panel[2]) * CFrame.Angles(panel[2] * 0.09, 0, panel[3])
		piece("RobeGore" .. index, pelvis, Vector3.new(0.76, 2.15, 0.13), pivot, if index % 2 == 0 then purple else cloth, nil, 1.075, index)
		if index == 1 or index == 2 or index == 6 then
			piece("GoreHem" .. index, pelvis, Vector3.new(0.7, 0.045, 0.15), pivot, edge, nil, 2.075, index)
		end
	end
	for _, side in { "Right", "Left" } do
		local arm = character:FindFirstChild(side .. "UpperArm") or character:FindFirstChild(side .. " Arm")
		local forearm = character:FindFirstChild(side .. "LowerArm") or arm
		local hand = character:FindFirstChild(side .. "Hand") or forearm
		if arm and arm:IsA("BasePart") then
			piece("Sleeve" .. side, arm, Vector3.new(0.82, arm.Size.Y / scale + 0.16, 0.87), CFrame.identity, purple, "round")
		end
		if forearm and forearm:IsA("BasePart") then
			piece("Bracer" .. side, forearm, Vector3.new(0.65, if r15 then 0.87 else 0.7, 0.72), CFrame.new(0, if r15 then 0 else -0.5, 0), iron)
			piece("BracerBinding" .. side, forearm, Vector3.new(0.68, 0.08, 0.74), CFrame.new(0, if r15 then 0.26 else -0.3, 0), edge)
		end
		if hand and hand:IsA("BasePart") then
			piece("Glove" .. side, hand, Vector3.new(0.58, if r15 then 0.5 else 0.42, 0.65), CFrame.new(0, if r15 then 0 else -0.85, 0), cloth, "round")
		end
		local foot = character:FindFirstChild(side .. "Foot") or character:FindFirstChild(side .. " Leg")
		if foot and foot:IsA("BasePart") then
			piece("Boot" .. side, foot, Vector3.new(0.68, if r15 then 0.5 else 0.65, 0.98), CFrame.new(0, if r15 then 0 else -0.7, -0.12), iron)
		end
	end
	local lastTime = 0
	local lean = 0
	return {
		folder = folder,
		step = function(now: number, castWeight: number)
			local delta = if lastTime == 0 then 1 / 60 else math.clamp(now - lastTime, 0, 0.1)
			lastTime = now
			local speed = math.min(root.AssemblyLinearVelocity.Magnitude, 22)
			lean += ((speed / 22) - lean) * math.min(1, delta * 9)
			for _, item in pieces do
				if not item.anchor.Parent then continue end
				local flutter = if item.sway == 0 then 0 else math.sin(now * 7 + item.sway * 1.7) * (0.025 + lean * 0.08)
				local fold = if item.sway == 0 then CFrame.identity else CFrame.Angles(lean * 0.16 + castWeight * 0.18 + flutter, 0, flutter * 0.35)
				item.part.CFrame = item.anchor.CFrame * item.offset * fold * CFrame.new(0, -item.drop, 0)
			end
		end,
		destroy = function()
			added:Disconnect()
			folder:Destroy()
			for item, original in hiddenParts do if item.Parent then item.Transparency = original end end
			for item, original in hiddenDecals do if item.Parent then item.Transparency = original end end
		end,
	}
end
return WarlockCostume
