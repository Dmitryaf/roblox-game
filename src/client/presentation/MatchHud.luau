--!strict
local MatchHud = {}
local ink = Color3.fromRGB(242, 232, 255)
local background = Color3.fromRGB(22, 18, 31)
local waitingReasons: { [string]: string } = {
	waiting_pair = "Ждём второго игрока для равных составов. Пока можно тренироваться.",
	pair_preparing = "Пара собрана. Готовимся к входу в матч…",
	match_full = "Матч заполнен. Вы в очереди на следующий вход.",
	gathering = "Собираем готовых игроков для начала матча.",
	last_seconds = "Матч скоро закончится. Вы в очереди на следующий.",
	replacement = "Ждём замену выбывшему участнику.",
}

local function label(parent: Instance, name: string, y: number, height: number, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Position = UDim2.fromOffset(14, y)
	text.Size = UDim2.new(1, -28, 0, height)
	text.BackgroundTransparency = 1
	text.TextColor3 = ink
	text.TextSize = size
	text.TextWrapped = true
	text.Font = Enum.Font.GothamMedium
	text.Parent = parent
	return text
end

local function panel(parent: Instance, name: string, width: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(0.94, 0, 0, 104)
	frame.BackgroundColor3 = background
	frame.BackgroundTransparency = 0.12
	frame.Parent = parent
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, 1000)
	limit.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	return frame
end

local function button(parent: Instance, name: string): TextButton
	local action = Instance.new("TextButton")
	action.Name = name
	action.Size = UDim2.new(1, -28, 0, 38)
	action.Position = UDim2.fromOffset(14, 140)
	action.BackgroundColor3 = Color3.fromRGB(91, 58, 135)
	action.TextColor3 = ink
	action.Font = Enum.Font.GothamMedium
	action.TextSize = 16
	action.TextWrapped = true
	action.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = action
	return action
end

local function clock(seconds: number): string
	local value = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(value / 60), value % 60)
end

function MatchHud.new(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	local header = panel(gui, "ScorePanel", 640)
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 10)
	local goal = label(header, "Goal", 6, 22, 14)
	goal.Text = "ЗОНА КОНТРОЛЯ · до 150 очков или 5 минут"
	local score = label(header, "Score", 29, 33, 25)
	for _, text in { goal, score } do
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize, limit.MaxTextSize = if text == goal then 10 else 14, text.TextSize
		limit.Parent = text
		text.TextScaled = true
	end
	local objective = label(header, "Objective", 65, 32, 15)
	local actions = panel(gui, "ActionPanel", 330)
	actions.Position = UDim2.fromOffset(12, 126)
	actions.Size = UDim2.new(0.94, 0, 0, 214)
	local title = label(actions, "Title", 10, 25, 18)
	local status = label(actions, "Status", 39, 77, 15)
	local feedback = label(actions, "Feedback", 116, 51, 14)
	local readyButton = button(actions, "ReadyButton")
	local exitButton = button(actions, "ExitButton")
	readyButton.Position = UDim2.fromOffset(14, 168)
	exitButton.Position = UDim2.fromOffset(14, 168)
	local callback: ((string) -> ())? = nil
	local readyAction = "ready"
	local pendingAction = true
	local readyConnection = readyButton.Activated:Connect(function()
		if not pendingAction and callback then callback(readyAction) end
	end)
	local exitConnection = exitButton.Activated:Connect(function()
		if not pendingAction and callback then callback("exit") end
	end)
	gui.Parent = playerGui
	return {
		setAction = function(action: (string) -> ()) callback = action end,
		show = function(state: any, pending: boolean, note: string)
			local character = game:GetService("Players").LocalPlayer.Character
			local className = if character and character:GetAttribute("CombatClass") == "warrior" then "Воин" else "Чернокнижник"
			pendingAction = pending
			readyButton.Active, exitButton.Active = not pending, not pending
			readyButton.AutoButtonColor, exitButton.AutoButtonColor = not pending, not pending
			feedback.Text = note
			feedback.TextColor3 = Color3.fromRGB(255, 216, 153)
			if not state then
				score.Text, objective.Text = "Подключаемся…", "Удерживайте центральную зону своей командой."
				title.Text, status.Text = "Тренировка · " .. className, "Получаем состояние сервера…"
				readyButton.Visible, exitButton.Visible = false, false
				return
			end
			local participant = state.mode == "match"
			goal.Text = string.format("ЗОНА КОНТРОЛЯ · до %d очков или %s", state.target or 150, clock(state.duration or 300))
			local phase = state.phase
			score.Text = string.format("A  %d  :  %d  B   ·   %s", state.scoreA, state.scoreB, clock(state.displayRemaining or state.remaining))
			local zoneText = if state.zone == "contested" then "Спорная зона · очки не начисляются"
				else if state.zone == "A" then "Команда A удерживает зону"
				else if state.zone == "B" then "Команда B удерживает зону" else "Зона свободна · займите её"
			objective.Text = if phase == "active" then zoneText else if phase == "paused" then "Матч на паузе · счёт и время остановлены"
				else if phase == "countdown" or phase == "resuming" then "Начало боя через " .. clock(state.displayDeadline or 0)
				else if phase == "gathering" then "Сбор участников · " .. clock(state.displayDeadline or 0)
				else if phase == "finished" then "Матч завершён" else "Удерживайте центральную зону своей командой."
			readyButton.Visible, exitButton.Visible = not participant, participant
			readyAction = if state.ready then "cancel" else "ready"
			readyButton.Text = if pending then "Ожидаем сервер…" else if state.ready then "R · Отменить готовность"
				else if state.result then "R · Играть снова" else "R · Готов к матчу"
			exitButton.Text = if pending then "Ожидаем сервер…" else "B · Выйти в тренировку"
			if participant then
				title.Text = "Команда " .. (if state.team == 1 then "A" else "B") .. " · " .. className
				status.Text = if phase == "paused" then "Ждём замену · " .. clock(state.displayDeadline or 0)
					else if state.pairDeadline then "Вход парой через " .. clock(state.displayPairDeadline or 0) .. ". R — отменить вход."
					else if phase == "countdown" or phase == "resuming" then "Вы на стартовой площадке. Бой скоро начнётся."
					else "Займите зону. Убийства помогают удержанию, но не дают очков."
			else
				title.Text = "Тренировка · " .. className
				if state.ready then
					local reason = waitingReasons[state.waitingReason] or "Ожидаем входа в равные составы."
					if state.waitingReason == "pair_preparing" then reason ..= " " .. clock(state.displayPairDeadline or 0) end
					status.Text = reason .. (if state.queuePosition then "\nМесто в очереди: " .. tostring(state.queuePosition) else "")
				elseif state.result then
					local result = state.result
					local outcome = if result.reason == "interrupted" then "Матч прерван: не хватает игроков"
						else if result.winner == nil then "Ничья" else "Победила команда " .. (if result.winner == 1 then "A" else "B")
					status.Text = string.format("%s · %d : %d\nНажмите «Играть снова» для нового матча.", outcome, result.scoreA, result.scoreB)
				else
					status.Text = "Испытайте способности на мишени. Нажмите «Готов», чтобы войти в матч за зону."
				end
			end
		end,
		destroy = function()
			readyConnection:Disconnect(); exitConnection:Disconnect()
			callback = nil
			gui:Destroy()
		end,
	}
end
return MatchHud
