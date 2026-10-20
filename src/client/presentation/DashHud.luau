--!strict
local Players = game:GetService("Players")
local DashHud = {}

function DashHud.new(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.Enabled = "DashHud", false, false
	local panel = Instance.new("TextLabel")
	panel.Name, panel.AnchorPoint = "Ability", Vector2.new(0.5, 1)
	panel.Position, panel.Size = UDim2.new(0.5, 0, 1, -132), UDim2.new(0.9, 0, 0, 60)
	panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(30, 25, 23), 0.15
	panel.TextColor3, panel.TextSize = Color3.fromRGB(224, 235, 240), 15
	panel.Font, panel.TextWrapped = Enum.Font.GothamMedium, true
	panel.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize, limit.Parent = Vector2.new(580, 60), panel
	local rounding = Instance.new("UICorner")
	rounding.CornerRadius, rounding.Parent = UDim.new(0, 12), panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight, padding.Parent = UDim.new(0, 12), UDim.new(0, 12), panel
	gui.Parent = playerGui
	return {
		show = function(status: string, note: string)
			local player = Players.LocalPlayer
			local character = if player then player.Character else nil
			gui.Enabled = character ~= nil and character:GetAttribute("CombatClass") == "warrior"
			panel.Text = "E · РЫВОК · " .. status .. "\n" .. note
		end,
		destroy = function() gui:Destroy() end,
	}
end
return DashHud
