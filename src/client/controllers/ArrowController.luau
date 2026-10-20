--!strict
local RunService = game:GetService("RunService")
local ArrowController = {}
local reasons = {
	wrong_class = "Выберите чернокнижника, чтобы использовать заклинание.",
	blocked = "Здесь нельзя переместиться: нужны свободное место и опора.",
	stale_arrow = "Стрела уже исчезла. Выпустите следующую.", expired = "Стрела уже исчезла.",
	dead = "Персонаж погиб. Ожидайте возрождения.", stale_life = "Персонаж изменился. Повторите действие.",
	preparing = "Сначала дождитесь выпуска стрелы.", cooldown = "Стрела восстанавливается.",
	busy = "Стрела уже активна.", not_ready = "Ожидаем персонажа…", invalid_position = "Позиция уточняется. Повторите действие.",
	paused = "Бой приостановлен. Дождитесь начала или возобновления.",
	spawn_protected = "Покиньте стартовую площадку, чтобы атаковать.",
}
function ArrowController.start(player: Player, remote: RemoteEvent, hud: any, effects: any, bind: any)
	local life, requestId, readyAt = 0, 0, 0
	local alive, phase, castId = false, "", nil :: number?
	local pending: { id: number, at: number }? = nil
	local note, noteUntil = "", 0
	local synced = false
	local suspended = false
	local lastSync = 0
	local function now() return workspace:GetServerTimeNow() end
	local function send(action: string, direction: Vector3?)
		local request: any = { action = action, life = life }
		if action == "cast" then request.direction = direction end
		if action == "teleport" then request.castId = castId end
		if pending and action ~= "sync" then return end
		requestId += 1
		request.requestId = requestId
		if action ~= "sync" then pending = { id = requestId, at = now() } end
		remote:FireServer(request)
	end
	local function snapshot(state: any)
		if state.life < life then return end
		if state.life ~= life then pending = nil end
		life, alive, readyAt = state.life, state.alive, state.readyAt
		suspended = state.suspended == true
		synced = life > 0
		phase, castId = "", nil
		for _, e in state.active do
			if e.owner == player.UserId and e.life == life then phase, castId = e.kind, e.castId end
		end
		effects.sync(state.active)
	end
	local connection = remote.OnClientEvent:Connect(function(e: any)
		if e.kind == "snapshot" then snapshot(e.state); return end
		if e.kind == "reply" then
			if not pending or pending.id ~= e.requestId or e.life ~= life then return end
			pending = nil
			snapshot(e.state)
			if not e.ok then note = (reasons :: { [string]: string })[e.reason] or "Действие отклонено. Повторите."; noteUntil = now() + 2.5 end
			return
		end
		if e.owner == player.UserId then
			if e.life < life then return end
			if e.kind == "ended" then
				if castId == e.castId then phase, castId = "", nil end
				if e.reason == "invalid_position" then note, noteUntil = reasons.invalid_position, now() + 2.5 end
			else
				phase, castId = if e.kind == "launched" then "flying" else e.kind, e.castId
				if e.readyAt then readyAt = e.readyAt end
			end
		end
		effects.event(e)
	end)
	local unbind = bind(player, function(direction: Vector3)
		if synced and alive and not suspended then send("cast", direction) end
	end, function()
		if phase == "flying" and castId then send("teleport", nil) end
	end)
	local frame = RunService.RenderStepped:Connect(function()
		local time = now()
		effects.step(time)
		if not synced and time - lastSync > 2 then lastSync = time; send("sync", nil) end
		if pending and time - pending.at > 2 then
			pending = nil
			note, noteUntil = "Нет подтверждения сервера. Обновляем состояние…", time + 3
			send("sync", nil)
		end
		local status = if not synced then "Подключаемся…" else if not alive then "Возрождение через несколько секунд…"
			else if suspended then "Бой приостановлен" else if pending then "Ожидаем подтверждения…" else if phase == "preparing" then "Подготовка стрелы…"
			else if phase == "flying" then "E — переместиться к стреле"
			else if readyAt > time then string.format("Восстановление · %.1f с", readyAt - time) else "ЛКМ — выпустить стрелу"
		hud.show(status, if time < noteUntil then note else "WASD — движение · Мышь — прицел · E — телепортация")
	end)
	send("sync", nil)
	return function()
		unbind(); connection:Disconnect(); frame:Disconnect()
		effects.destroy(); hud.destroy()
	end
end
return ArrowController
