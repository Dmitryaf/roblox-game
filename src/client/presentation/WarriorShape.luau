--!strict
-- Original local armour and sword. The underlying avatar and every authoritative joint stay intact.
local WarriorShape = {}
local steel = Color3.fromRGB(119, 132, 141)
local dark = Color3.fromRGB(45, 52, 59)
local silver = Color3.fromRGB(207, 218, 222)
local red = Color3.fromRGB(117, 35, 37)

function WarriorShape.new(character: Model): any
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local required: { string } = if r15 then {"Head", "UpperTorso", "LowerTorso", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "RightHand", "LeftHand", "RightFoot", "LeftFoot"}
		else {"Head", "Torso", "Right Arm", "Left Arm", "Right Leg", "Left Leg"}
	for _, name in required do
		local body = character:FindFirstChild(name)
		if not body or not body:IsA("BasePart") then return nil end
	end
	local torso = character:FindFirstChild(if r15 then "UpperTorso" else "Torso") :: BasePart
	local pelvis = if r15 then character:FindFirstChild("LowerTorso") :: BasePart else torso
	local head = character:FindFirstChild("Head") :: BasePart
	local scale = math.clamp(torso.Size.X / 2, 0.8, 1.25)
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "WarriorArmour", character
	local function piece(name: string, anchor: BasePart, size: Vector3, offset: CFrame, color: Color3, fabric: boolean?, wedge: boolean?): BasePart
		local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
		p.Name, p.Size, p.Color = name, size * scale, color
		p.Anchored, p.Massless, p.CanCollide, p.CanQuery, p.CanTouch = false, true, false, false, false
		p.Material, p.CastShadow = if fabric then Enum.Material.Fabric else Enum.Material.Metal, true
		local frame = CFrame.new(offset.Position * scale) * offset.Rotation
		p.CFrame, p.Parent = anchor.CFrame * frame, folder
		local weld = Instance.new("Weld")
		weld.Name, weld.Part0, weld.Part1 = "WarriorVisualWeld", anchor, p
		weld.C0, weld.C1, weld.Parent = frame, CFrame.identity, p
		return p
	end
	piece("SteelBreastplate", torso, Vector3.new(1.95, if r15 then 1.45 else 1.9, 1.16), CFrame.new(0, 0, 0.01), dark)
	piece("RaisedChestPlate", torso, Vector3.new(1.55, 1.1, 0.18), CFrame.new(0, 0.12, -0.64), steel)
	piece("RedChestTabard", torso, Vector3.new(0.62, 1.45, 0.08), CFrame.new(0, -0.08, -0.75), red, true)
	piece("SilverChestClasp", torso, Vector3.new(0.38, 0.18, 0.08), CFrame.new(0, 0.48, -0.82), silver)
	piece("WarriorBelt", pelvis, Vector3.new(1.98, 0.3, 1.17), CFrame.new(0, if r15 then 0.12 else -0.65, 0), dark)
	for _, sign in {-1, 1} do
		piece("TabardTail", pelvis, Vector3.new(0.52, 1.35, 0.1), CFrame.new(sign * 0.3, if r15 then -0.77 else -1.5, -0.58) * CFrame.Angles(0, 0, sign * -0.05), red, true)
		piece("SteelPauldron", torso, Vector3.new(1.06, 0.5, 1.23), CFrame.new(sign * 1.05, 0.67, 0) * CFrame.Angles(0, 0, sign * -0.12), steel, false, true)
		piece("PauldronRedBinding", torso, Vector3.new(0.16, 0.36, 1.25), CFrame.new(sign * 1.38, 0.55, 0), red)
	end
	piece("SteelHelmetCrown", head, Vector3.new(1.9, 0.44, 1.55), CFrame.new(0, 0.7, 0.03), steel)
	piece("HelmetBrow", head, Vector3.new(1.86, 0.23, 0.18), CFrame.new(0, 0.37, -0.76), dark)
	piece("RedHelmetRidge", head, Vector3.new(0.27, 0.25, 1.35), CFrame.new(0, 1.01, 0.08), red)
	for _, side in {"Right", "Left"} do
		local arm = character:FindFirstChild(if r15 then side .. "UpperArm" else side .. " Arm") :: BasePart
		local forearm = if r15 then character:FindFirstChild(side .. "LowerArm") :: BasePart else arm
		local foot = character:FindFirstChild(if r15 then side .. "Foot" else side .. " Leg") :: BasePart
		piece("SteelVambrace" .. side, forearm, Vector3.new(0.8, if r15 then 0.9 else 0.8, 0.83), CFrame.new(0, if r15 then 0 else -0.5, 0), steel)
		piece("WarriorBoot" .. side, foot, Vector3.new(0.82, if r15 then 0.55 else 0.8, 1.13), CFrame.new(0, if r15 then 0 else -0.66, -0.14), dark)
	end
	local hand = character:FindFirstChild(if r15 then "RightHand" else "Right Arm") :: BasePart
	local grip = CFrame.new(0, if r15 then -0.08 else -0.9, -0.1) * CFrame.Angles(-math.pi / 2, 0, -0.15)
	piece("WarriorSwordGrip", hand, Vector3.new(0.22, 0.8, 0.24), grip, red, true)
	piece("WarriorSwordPommel", hand, Vector3.new(0.38, 0.27, 0.36), grip * CFrame.new(0, -0.52, 0), dark)
	piece("WarriorSwordGuard", hand, Vector3.new(1.17, 0.16, 0.3), grip * CFrame.new(0, 0.46, 0), dark)
	piece("WarriorSwordBlade", hand, Vector3.new(0.39, 2.95, 0.1), grip * CFrame.new(0, 2.02, 0), silver)
	piece("WarriorSwordFuller", hand, Vector3.new(0.075, 2.64, 0.11), grip * CFrame.new(0, 1.95, 0), steel)
	piece("WarriorSwordTip", hand, Vector3.new(0.39, 0.48, 0.1), grip * CFrame.new(0, 3.73, 0) * CFrame.Angles(0, math.pi / 2, 0), silver, false, true)
	local shape = {folder = folder}
	function shape.step(_now: number)
		-- Native joints follow animation in the same simulation/render pass; no delayed CFrame copying.
	end
	function shape.destroy() folder:Destroy() end
	return shape
end
return WarriorShape
