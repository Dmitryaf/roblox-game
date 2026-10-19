--!strict
local ArrowHud = {}
function ArrowHud.new(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArrowHud"
	gui.ResetOnSpawn = false
	local panel = Instance.new("TextLabel")
	panel.Name = "Ability"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -24)
	panel.Size = UDim2.new(0.9, 0, 0, 100)
	panel.BackgroundColor3 = Color3.fromRGB(22, 18, 31)
	panel.BackgroundTransparency = 0.15
	panel.TextColor3 = Color3.fromRGB(242, 232, 255)
	panel.TextSize = 18
	panel.TextWrapped = true
	panel.Font = Enum.Font.GothamMedium
	panel.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(580, 100)
	constraint.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -32, 0, 48)
	title.Position = UDim2.fromOffset(16, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(235, 225, 250)
	title.TextSize = 16
	title.Font = Enum.Font.GothamMedium
	title.TextWrapped = true
	title.Text = "Тест чернокнижника · Мишень впереди, второй игрок — соперник"
	title.Visible = game:GetService("ReplicatedStorage"):GetAttribute("MatchEnabled") ~= true
	title.Parent = gui
	gui.Parent = playerGui
	return {
		show = function(status: string, note: string)
			panel.Text = "ДЕМОНИЧЕСКАЯ СТРЕЛА\n" .. status .. "\n" .. note
		end,
		destroy = function() gui:Destroy() end,
	}
end
return ArrowHud
