--!strict
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local MatchController = {}
local reasons: { [string]: string } = {
	stale_match = "Матч уже изменился. Состояние обновлено — повторите действие.",
	rate_limit = "Слишком много действий. Подождите немного.",
	invalid = "Не удалось выполнить действие. Повторите.",
	not_ready = "Персонаж ещё не готов. Дождитесь возрождения.",
	not_participant = "Вы уже в тренировке.",
	participant = "Сначала выйдите из текущего матча.",
	already_playing = "Вы уже участвуете в матче.",
	unknown_player = "Подключение ещё не завершено. Повторите через несколько секунд.",
}

function MatchController.start(_player: Player, remote: RemoteEvent, hud: any)
	local state: any = nil
	local receivedAt, requestId, lastSync = 0, 0, 0
	local pending: { id: number, at: number }? = nil
	local syncId: number? = nil
	local syncing = true
	local note, noteUntil = "", 0
	local lastDraw = -1
	local function now(): number return workspace:GetServerTimeNow() end
	local function snapshot(value: any): boolean
		if type(value) ~= "table" or type(value.version) ~= "number" or type(value.matchId) ~= "number" then return false end
		if state and (value.matchId < state.matchId or value.version <= state.version) then return false end
		if state and value.matchId ~= state.matchId then pending = nil end
		state, receivedAt = value, now()
		syncing = false
		return true
	end
	local function send(action: string)
		if action ~= "sync" and (pending or syncing or not state) then return end
		requestId += 1
		local time = now()
		if action == "sync" then syncId, lastSync = requestId, time
		else pending = { id = requestId, at = time }; note, noteUntil = "", 0 end
		remote:FireServer({ action = action, requestId = requestId, matchId = if state then state.matchId else 0 })
	end
	local connection = remote.OnClientEvent:Connect(function(event: any)
		if type(event) ~= "table" then return end
		if event.kind == "snapshot" then snapshot(event.state); return end
		if event.kind ~= "reply" then return end
		local matchesAction = pending ~= nil and pending.id == event.requestId
		local matchesSync = syncId ~= nil and syncId == event.requestId
		if not matchesAction and not matchesSync then return end
		snapshot(event.state)
		if matchesSync then
			syncId = nil
			-- An equal-version reply still confirms that the retained snapshot is current.
			if state and event.state and event.state.version == state.version and event.state.matchId == state.matchId then syncing = false end
		end
		if matchesAction then
			pending = nil
			if not event.ok then
				note = reasons[event.reason] or "Действие отклонено. Состояние обновлено, повторите попытку."
				noteUntil = now() + 4
			end
		end
	end)
	local function action(value: string)
		if not state then return end
		if value == "exit" and state.mode ~= "match" then return end
		if (value == "ready" or value == "cancel") and state.mode == "match" and not state.ready then return end
		send(value)
	end
	hud.setAction(action)
	local keyboard = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() or not state then return end
		if input.KeyCode == Enum.KeyCode.R and (state.mode ~= "match" or state.ready) then action(if state.ready then "cancel" else "ready")
		elseif input.KeyCode == Enum.KeyCode.B and state.mode == "match" then action("exit") end
	end)
	local frame = RunService.RenderStepped:Connect(function()
		local time = now()
		if syncing and time - lastSync > 2 then send("sync") end
		if pending and time - pending.at > 3 then
			pending, syncing = nil, true
			note, noteUntil = "Нет подтверждения сервера. Обновляем состояние…", time + 6
			send("sync")
		end
		if time - lastDraw < 0.1 then return end
		lastDraw = time
		local display: any = nil
		if state then
			display = table.clone(state)
			display.displayRemaining = math.max(0, state.remaining - (if state.phase == "active" then time - receivedAt else 0))
			display.displayDeadline = if state.deadline then math.max(0, state.deadline - time) else 0
			display.displayPairDeadline = if state.pairDeadline then math.max(0, state.pairDeadline - time) else 0
		end
		hud.show(display, syncing or pending ~= nil, if time < noteUntil then note else if syncing then "Обновляем состояние сервера…" else "")
	end)
	hud.show(nil, true, "")
	send("sync")
	return function()
		connection:Disconnect(); keyboard:Disconnect(); frame:Disconnect()
		hud.destroy()
	end
end
return MatchController
