--!strict
local RunService = game:GetService("RunService")
local MeleeController = {}
local reasons: { [string]: string } = {
	wrong_class = "Выберите воина, чтобы атаковать мечом.",
	dead = "Персонаж погиб. Дождитесь возрождения.",
	stale_life = "Персонаж изменился. Повторите удар.",
	not_ready = "Ожидаем персонажа…",
	busy = "Завершите текущий взмах.",
	cooldown = "Меч ещё восстанавливается.",
	paused = "Бой приостановлен. Дождитесь начала или возобновления.",
	spawn_protected = "Покиньте стартовую площадку, чтобы атаковать.",
	invalid_position = "Позиция уточняется. Повторите удар.",
	invalid_aim = "Укажите направление удара курсором.",
}
function MeleeController.start(player: Player, remote: RemoteEvent, hud: any, effects: any, bind: any)
	local life, requestId, readyAt = 0, 0, 0
	local alive, suspended, synced, recovering = false, false, false, false
	local phase = ""
	local swingId: number? = nil
	local pending: { id: number, life: number, at: number }? = nil
	local syncId: number? = nil
	local lastSync, lastDraw = 0, -1
	local note, noteUntil = "", 0
	local ownerLives: { [number]: number } = {}
	local function now(): number return workspace:GetServerTimeNow() end
	local function warrior(): boolean
		local character = player.Character
		return character ~= nil and character:GetAttribute("CombatClass") == "warrior"
	end
	local function send(action: string, direction: Vector3?)
		if action ~= "sync" and (not warrior() or not synced or not alive or suspended or recovering or pending) then return end
		requestId += 1
		local request: any = { action = action, requestId = requestId, life = life }
		if action == "cast" then
			request.direction = direction
			pending = { id = requestId, life = life, at = now() }
			note, noteUntil = "", 0
		else syncId, lastSync = requestId, now() end
		remote:FireServer(request)
	end
	local function snapshot(state: any): boolean
		if type(state) ~= "table" or type(state.life) ~= "number" or state.life < life then return false end
		if state.life ~= life then pending = nil end
		life, alive, suspended, readyAt = state.life, state.alive == true, state.suspended == true, state.readyAt
		if recovering then note, noteUntil = "Состояние обновлено. Повторите удар.", now() + 2.5 end
		synced, recovering = life > 0, false
		ownerLives[player.UserId] = life
		phase, swingId = "", nil
		for _, event in state.active do
			if event.owner ~= player.UserId then ownerLives[event.owner] = math.max(ownerLives[event.owner] or 0, event.life) end
		end
		local active = {}
		for _, event in state.active do
			if event.life ~= ownerLives[event.owner] then continue end
			table.insert(active, event)
			if event.owner == player.UserId then phase, swingId = event.kind, event.swingId end
		end
		effects.sync(active)
		return true
	end
	local connection = remote.OnClientEvent:Connect(function(event: any)
		if type(event) ~= "table" then return end
		if event.kind == "snapshot" then snapshot(event.state); return end
		if event.kind == "reply" then
			local actionReply = pending ~= nil and pending.id == event.requestId
			local syncReply = syncId ~= nil and syncId == event.requestId
			if not actionReply and not syncReply then return end
			local requestedLife = if pending then pending.life else life
			snapshot(event.state)
			if syncReply then syncId = nil end
			if actionReply then
				pending = nil
				if not event.ok and requestedLife == life and (event.life == nil or event.life == life) then
					note, noteUntil = reasons[event.reason] or "Удар отклонён. Повторите попытку.", now() + 3
				end
			end
			return
		end
		if event.kind ~= "preparing" and event.kind ~= "struck" and event.kind ~= "ended" then return end
		if event.owner == player.UserId then
			if not synced or event.life ~= life then return end
		else
			if event.life < (ownerLives[event.owner] or 0) then return end
			ownerLives[event.owner] = event.life
		end
		if event.owner == player.UserId then
			if event.kind == "ended" then
				if event.swingId == swingId then
					phase, swingId = "", nil
					if event.readyAt then readyAt = event.readyAt end
				end
			else
				phase, swingId = event.kind, event.swingId
				if event.readyAt then readyAt = event.readyAt end
			end
		end
		effects.event(event)
	end)
	local unbind = bind(player, function(direction: Vector3) send("cast", direction) end)
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
			else if pending then "Ожидаем подтверждения…" else if phase == "preparing" then "Подготовка взмаха…"
			else if phase == "struck" then "Возвращаем меч в стойку…"
			else if readyAt > time then string.format("Восстановление · %.1f с", readyAt - time) else "ЛКМ — взмах мечом в направлении курсора"
		hud.show(status, if time < noteUntil then note else "WASD — движение · Мышь — направление удара")
	end)
	hud.show("Подключаемся…", "Получаем состояние сервера…")
	send("sync", nil)
	return function()
		unbind(); connection:Disconnect(); frame:Disconnect()
		effects.destroy(); hud.destroy()
	end
end
return MeleeController
