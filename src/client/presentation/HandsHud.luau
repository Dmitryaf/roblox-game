--!strict
local HandsHud = {}
function HandsHud.new(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn = "HandsHud", false
	local panel = Instance.new("TextLabel")
	panel.Name = "Ability"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -132)
	panel.Size = UDim2.new(0.9, 0, 0, 78)
	panel.BackgroundColor3 = Color3.fromRGB(22, 18, 31)
	panel.BackgroundTransparency = 0.15
	panel.TextColor3 = Color3.fromRGB(222, 239, 229)
	panel.TextSize, panel.TextWrapped = 15, true
	panel.Font = Enum.Font.GothamMedium
	panel.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize, constraint.Parent = Vector2.new(580, 78), panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	padding.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 12), panel
	gui.Parent = playerGui
	return {
		show = function(status: string, note: string)
			panel.Text = "Q · ДЕМОНИЧЕСКИЕ РУКИ\n" .. status .. "\n" .. note
		end,
		destroy = function() gui:Destroy() end,
	}
end
return HandsHud
