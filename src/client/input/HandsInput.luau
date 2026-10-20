--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local HandsInput = {}

function HandsInput.bind(player: Player, cast: (Vector3) -> (), invalid: (() -> ())?)
	local function onCast(_: string, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local character, camera = player.Character, workspace.CurrentCamera
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not camera or not character or not root or not root:IsA("BasePart") then return Enum.ContextActionResult.Pass end
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
		local ignored: { Instance } = { character }
		for _, visitor in Players:GetPlayers() do
			if visitor.Character and visitor.Character ~= character then table.insert(ignored, visitor.Character) end
		end
		params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignored
		params.IgnoreWater = true
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		if hit then
			local target = hit.Instance:FindFirstAncestorOfClass("Model")
			if target and target:GetAttribute("TrainingTarget") == true and target:FindFirstChildOfClass("Humanoid") then
				table.insert(ignored, target)
				params.FilterDescendantsInstances = ignored
				hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
			end
		end
		if hit and hit.Normal.Y >= 0.65 then cast(hit.Position)
		elseif invalid then invalid() end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction("CastHands", onCast, false, Enum.KeyCode.Q)
	return function() ContextActionService:UnbindAction("CastHands") end
end
return HandsInput
