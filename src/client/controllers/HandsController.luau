--!strict
local RunService = game:GetService("RunService")
local HandsController = {}
local reasons: { [string]: string } = {
	blocked = "Область здесь не поместится. Выберите другое место.",
	invalid_target = "Укажите доступную поверхность земли.",
	invalid_position = "Позиция уточняется. Повторите действие.",
	no_ground = "Укажите поверхность земли под курсором.",
	out_of_range = "Слишком далеко. Подойдите ближе к выбранной точке.",
	range = "Слишком далеко. Подойдите ближе к выбранной точке.",
	dead = "Персонаж погиб. Дождитесь возрождения.",
	stale_life = "Персонаж изменился. Состояние обновляется.",
	not_ready = "Ожидаем персонажа…",
	busy = "Демонические руки уже действуют.",
	cooldown = "Демонические руки восстанавливаются.",
	paused = "Бой приостановлен. Дождитесь начала или возобновления.",
	spawn_protected = "Покиньте стартовую площадку, чтобы атаковать.",
}

function HandsController.start(player: Player, remote: RemoteEvent, hud: any, effects: any, bind: any)
	local life, requestId, readyAt = 0, 0, 0
	local alive, suspended, synced, recovering = false, false, false, false
	local phase = ""
	local areaId: number? = nil
	local expiresAt = 0
	local pending: { id: number, life: number, at: number }? = nil
	local syncId: number? = nil
	local lastSync = 0
	local ownerLives: { [number]: number } = {}
	local note, noteUntil, lastDraw = "", 0, -1
	local function now(): number return workspace:GetServerTimeNow() end
	local function send(action: string, position: Vector3?)
		if action ~= "sync" and (not synced or not alive or suspended or recovering or pending) then return end
		requestId += 1
		local message: any = { action = action, requestId = requestId, life = life }
		if action == "cast" then
			message.position = position
			pending = { id = requestId, life = life, at = now() }
			note, noteUntil = "", 0
		else syncId, lastSync = requestId, now() end
		remote:FireServer(message)
	end
	local function snapshot(state: any): boolean
		if type(state) ~= "table" or type(state.life) ~= "number" or state.life < life then return false end
		local wasRecovering = recovering
		if state.life ~= life then pending = nil end
		life, alive, suspended, readyAt = state.life, state.alive == true, state.suspended == true, state.readyAt
		synced, recovering = life > 0, false
		if wasRecovering then note, noteUntil = "Состояние обновлено. Повторите действие.", now() + 2.5 end
		ownerLives[player.UserId] = life
		phase, areaId, expiresAt = "", nil, 0
		-- Every owner has a separate life sequence. A foreign life is never compared to ours.
		for _, event in state.active do
			if event.owner ~= player.UserId then ownerLives[event.owner] = math.max(ownerLives[event.owner] or 0, event.life) end
		end
		local active = {}
		for _, event in state.active do
			if event.life ~= ownerLives[event.owner] then continue end
			table.insert(active, event)
			if event.owner == player.UserId then phase, areaId, expiresAt = event.kind, event.areaId, event.expiresAt end
		end
		effects.sync(active)
		return true
	end
	local connection = remote.OnClientEvent:Connect(function(event: any)
		if type(event) ~= "table" then return end
		if event.kind == "snapshot" then snapshot(event.state); return end
		if event.kind == "reply" then
			local matchedAction = pending ~= nil and pending.id == event.requestId
			local matchedSync = syncId ~= nil and syncId == event.requestId
			if not matchedAction and not matchedSync then return end
			local requestedLife = if pending then pending.life else life
			snapshot(event.state)
			if matchedSync then syncId = nil end
			if matchedAction then
				pending = nil
				if not event.ok and requestedLife == life and event.life == life then
					note, noteUntil = reasons[event.reason] or "Действие отклонено. Выберите место и повторите.", now() + 3
				end
			end
			return
		end
		if event.kind ~= "preparing" and event.kind ~= "active" and event.kind ~= "ended" then return end
		if event.owner == player.UserId then
			if not synced or event.life ~= life then return end
		else
			if event.life < (ownerLives[event.owner] or 0) then return end
			ownerLives[event.owner] = event.life
		end
		if event.owner == player.UserId then
			if event.kind == "ended" then
				if areaId == event.areaId then
					phase, areaId, expiresAt = "", nil, 0
					if event.readyAt then readyAt = event.readyAt end
				end
			else
				phase, areaId, expiresAt = event.kind, event.areaId, event.expiresAt
				if event.readyAt then readyAt = event.readyAt end
			end
		end
		effects.event(event)
	end)
	local unbind = bind(player, function(position: Vector3) send("cast", position) end, function()
		note, noteUntil = reasons.no_ground, now() + 2.5
	end)
	local frame = RunService.RenderStepped:Connect(function()
		local time = now()
		effects.step(time)
		if (not synced or recovering) and time - lastSync > 2 then send("sync", nil) end
		if pending and time - pending.at > 2.5 then
			pending, recovering = nil, true
			note, noteUntil = "Нет подтверждения сервера. Обновляем состояние…", time + 4
			send("sync", nil)
		end
		if time - lastDraw < 0.1 then return end
		lastDraw = time
		local status = if not synced then "Подключаемся…" else if not alive then "Ожидаем возрождения…"
			else if suspended then "Бой приостановлен" else if recovering then "Обновляем состояние…"
			else if pending then "Ожидаем подтверждения…" else if phase == "preparing" then "Собираем демонические руки…"
			else if phase == "active" then string.format("Область действует · %.1f с", math.max(0, expiresAt - time))
			else if readyAt > time then string.format("Восстановление · %.1f с", readyAt - time) else "Q — вызвать руки в точке под курсором"
		hud.show(status, if time < noteUntil then note else "Замедление и постепенный урон в области")
	end)
	hud.show("Подключаемся…", "Получаем состояние сервера…")
	send("sync", nil)
	return function()
		unbind(); connection:Disconnect(); frame:Disconnect()
		effects.destroy(); hud.destroy()
	end
end
return HandsController
