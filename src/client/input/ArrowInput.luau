--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ArrowInput = {}
function ArrowInput.bind(player: Player, cast: (Vector3) -> (), teleport: () -> ())
	local function onCast(_: string, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local camera = workspace.CurrentCamera
		local character = player.Character
		if character and character:GetAttribute("CombatClass") == "warrior" then return Enum.ContextActionResult.Pass end
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not camera or not root or not root:IsA("BasePart") then return Enum.ContextActionResult.Pass end
		local mouse = UserInputService:GetMouseLocation()
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui then
			local guiPosition = mouse - GuiService:GetGuiInset()
			for _, object in gui:GetGuiObjectsAtPosition(guiPosition.X, guiPosition.Y) do
				if object:IsA("GuiButton") then return Enum.ContextActionResult.Pass end
			end
		end
		-- GetMouseLocation includes the top bar inset; viewport coordinates use the same origin.
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character :: Model }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		local target = if hit then hit.Position else ray.Origin + ray.Direction * 500
		local direction = target - (root.Position + Vector3.new(0, 1, 0))
		if direction.Magnitude > 0.1 then cast(direction.Unit) end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction("CastArrow", onCast, false, Enum.UserInputType.MouseButton1)
	ContextActionService:BindAction("TeleportArrow", function(_, state)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		if player.Character and player.Character:GetAttribute("CombatClass") == "warrior" then return Enum.ContextActionResult.Pass end
		teleport()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E)
	return function()
		ContextActionService:UnbindAction("CastArrow")
		ContextActionService:UnbindAction("TeleportArrow")
	end
end
return ArrowInput
