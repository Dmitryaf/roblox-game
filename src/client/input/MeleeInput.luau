--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local MeleeInput = {}
function MeleeInput.bind(player: Player, swing: (Vector3) -> ())
	local function attack(_: string, state: Enum.UserInputState)
		local character = player.Character
		if not character or character:GetAttribute("CombatClass") ~= "warrior" then return Enum.ContextActionResult.Pass end
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local root, camera = character:FindFirstChild("HumanoidRootPart"), workspace.CurrentCamera
		if not root or not root:IsA("BasePart") or not camera then return Enum.ContextActionResult.Pass end
		local mouse = UserInputService:GetMouseLocation()
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui then
			local point = mouse - GuiService:GetGuiInset()
			for _, object in gui:GetGuiObjectsAtPosition(point.X, point.Y) do
				if object:IsA("GuiButton") then return Enum.ContextActionResult.Pass end
			end
		end
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		local target = if hit then hit.Position else ray.Origin + ray.Direction * 500
		local direction = (target - root.Position) * Vector3.new(1, 0, 1)
		if direction.Magnitude < 0.1 then direction = root.CFrame.LookVector * Vector3.new(1, 0, 1) end
		if direction.Magnitude < 0.1 then return Enum.ContextActionResult.Pass end
		swing(direction.Unit)
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction("WarriorSwing", attack, false, Enum.UserInputType.MouseButton1)
	return function() ContextActionService:UnbindAction("WarriorSwing") end
end
return MeleeInput
