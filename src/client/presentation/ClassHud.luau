--!strict
local ClassHud = {}
local StarterGui = game:GetService("StarterGui")
local names: { [string]: string } = { warlock = "Чернокнижник", warrior = "Воин" }
function ClassHud.new(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ClassHud", false, 6
	gui.Enabled = false
	local panel = Instance.new("Frame")
	panel.Name, panel.AnchorPoint = "ClassPanel", Vector2.new(1, 1)
	panel.Position, panel.Size = UDim2.new(1, -12, 1, -104), UDim2.fromOffset(220, 202)
	panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(22, 18, 31), 0.12
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 12), panel
	local function label(name: string, y: number, height: number, size: number): TextLabel
		local value = Instance.new("TextLabel")
		value.Name, value.Position, value.Size = name, UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, height)
		value.BackgroundTransparency, value.TextSize, value.TextWrapped = 1, size, true
		value.Font, value.TextColor3 = Enum.Font.GothamMedium, Color3.fromRGB(242, 232, 255)
		value.Parent = panel
		return value
	end
	local title = label("Title", 8, 22, 16)
	title.Text = "ВЫБОР КЛАССА"
	local current = label("Current", 32, 20, 14)
	local feedback = label("Feedback", 142, 52, 13)
	local buttons: { [string]: TextButton } = {}
	local connections: { RBXScriptConnection } = {}
	local callback: ((string) -> ())? = nil
	local enabled: { [string]: boolean } = {}
	for index, classId in { "warlock", "warrior" } do
		local button = Instance.new("TextButton")
		button.Name = if classId == "warlock" then "WarlockButton" else "WarriorButton"
		button.Position, button.Size = UDim2.fromOffset(12, 60 + (index - 1) * 40), UDim2.new(1, -24, 0, 34)
		button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(78, 53, 105), Color3.fromRGB(242, 232, 255)
		button.Font, button.TextSize, button.Text = Enum.Font.GothamMedium, 15, names[classId]
		button.Parent = panel
		local rounding = Instance.new("UICorner")
		rounding.CornerRadius, rounding.Parent = UDim.new(0, 8), button
		buttons[classId] = button
		table.insert(connections, button.Activated:Connect(function()
			if enabled[classId] and callback then callback(classId) end
		end))
	end
	local playerListBefore: boolean? = nil
	local function playerList(hidden: boolean)
		if hidden and playerListBefore == nil then
			local read, previous = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) end)
			if not read then return end
			local changed = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
			if changed then playerListBefore = previous end
		elseif not hidden and playerListBefore ~= nil then
			local previous = playerListBefore
			local restored = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, previous :: boolean) end)
			if restored then playerListBefore = nil end
		end
	end
	local function layout()
		local viewport = gui.AbsoluteSize
		local compact = viewport.X < 800 or viewport.Y < 560
		if compact then
			local width = math.max(1, (viewport.X - 32) / 2)
			panel.AnchorPoint = Vector2.zero
			panel.Position, panel.Size = UDim2.fromOffset(20 + width, 126), UDim2.fromOffset(width, 156)
			title.Position, title.Size, title.TextSize = UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 20), 14
			current.Position, current.Size, current.TextSize = UDim2.fromOffset(12, 30), UDim2.new(1, -24, 0, 18), 12
			feedback.Position, feedback.Size, feedback.TextSize = UDim2.fromOffset(12, 94), UDim2.new(1, -24, 0, 54), 12
			for index, classId in { "warlock", "warrior" } do
				local button = buttons[classId]
				button.Position, button.Size = UDim2.new((index - 1) / 2, if index == 1 then 12 else 4, 0, 54), UDim2.new(0.5, -16, 0, 34)
				button.TextSize = 13
			end
		else
			panel.AnchorPoint = Vector2.new(1, 1)
			panel.Position, panel.Size = UDim2.new(1, -12, 1, -104), UDim2.fromOffset(220, 202)
			title.Position, title.Size, title.TextSize = UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), 16
			current.Position, current.Size, current.TextSize = UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 20), 14
			feedback.Position, feedback.Size, feedback.TextSize = UDim2.fromOffset(12, 142), UDim2.new(1, -24, 0, 52), 13
			for index, classId in { "warlock", "warrior" } do
				local button = buttons[classId]
				button.Position, button.Size = UDim2.fromOffset(12, 60 + (index - 1) * 40), UDim2.new(1, -24, 0, 34)
				button.TextSize = 15
			end
		end
		playerList(compact and gui.Enabled)
	end
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	gui.Parent = playerGui
	layout()
	return {
		setAction = function(action: (string) -> ()) callback = action end,
		show = function(state: any, pending: boolean, note: string)
            gui.Enabled = state ~= nil and not state.locked
			current.Text = if state then "Сейчас: " .. (names[state.classId] or "Неизвестный класс") else "Подключаемся…"
			local locked = not state or state.locked or not state.alive
			feedback.Text = if note ~= "" then note else if pending then "Ожидаем подтверждения сервера…"
				else if state and not state.alive then "Дождитесь возрождения для выбора."
				else if locked then "Выбор доступен в тренировке вне очереди." else "Выберите класс перед готовностью."
			for classId, button in buttons do
				local selected = state ~= nil and state.classId == classId
				enabled[classId] = not pending and not locked and not selected and table.find(state.classes, classId) ~= nil
				button.Active, button.AutoButtonColor = enabled[classId], enabled[classId]
				button.Text = (if selected then "✓ " else "") .. names[classId]
				button.BackgroundColor3 = if selected then Color3.fromRGB(66, 93, 78) else if enabled[classId] then Color3.fromRGB(78, 53, 105) else Color3.fromRGB(49, 43, 57)
			end
			layout()
		end,
		destroy = function()
			for _, connection in connections do connection:Disconnect() end
			playerList(false)
			callback = nil; gui:Destroy()
		end,
	}
end
return ClassHud
