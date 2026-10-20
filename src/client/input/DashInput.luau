--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local DashInput = {}

function DashInput.bind(player: Player, dash: (Vector3) -> ())
	local function activate(_: string, state: Enum.UserInputState)
		local character = player.Character
		if not character or character:GetAttribute("CombatClass") ~= "warrior" then return Enum.ContextActionResult.Pass end
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return Enum.ContextActionResult.Pass end
		local direction = humanoid.MoveDirection * Vector3.new(1, 0, 1)
		if direction.Magnitude < 0.1 then direction = root.CFrame.LookVector * Vector3.new(1, 0, 1) end
		if direction.Magnitude < 0.1 then return Enum.ContextActionResult.Pass end
		dash(direction.Unit)
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction("WarriorDash", activate, false, Enum.KeyCode.E)
	return function() ContextActionService:UnbindAction("WarriorDash") end
end
return DashInput
