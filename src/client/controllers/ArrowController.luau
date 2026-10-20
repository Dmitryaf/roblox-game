--!strict
local RunService = game:GetService("RunService")
local ArrowController = {}
local reasons = {
    no_area = "Сначала призовите руки клавишей Q.", inactive_area = "Дождитесь появления рук.",
    expiring_area = "Руки уже исчезают — перенос недоступен.",
    transferring = "Область уже переносится.",
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
	local pending: { id: number, at: number, action: string }? = nil
	local note, noteUntil = "", 0
	local synced = false
	local suspended = false
	local lastSync = 0
	local ownerLives: { [number]: number } = {}
	local function now() return workspace:GetServerTimeNow() end
	local function send(action: string, direction: Vector3?)
		local predictCast = action == "cast"
		local request: any = { action = action, life = life }
		if action == "cast" then request.direction = direction end
		if action == "teleport" or action == "transfer" then request.castId = castId end
		if pending and action ~= "sync" then return end
		requestId += 1
		request.requestId = requestId
		if action ~= "sync" then pending = { id = requestId, at = now(), action = action } end
        if predictCast and effects.preview and phase == "" and now() >= readyAt then effects.preview(requestId, life, direction) end
		remote:FireServer(request)
	end
	local function snapshot(state: any)
		if state.life < life then return end
		if state.life ~= life or not state.alive or state.suspended then
            if effects.cancelPreview then effects.cancelPreview() end
            pending = nil
        end
		life, alive, readyAt = state.life, state.alive, state.readyAt
		suspended = state.suspended == true
		synced = life > 0
		ownerLives[player.UserId] = life
		phase, castId = "", nil
		for _, e in state.active do
			if e.owner ~= player.UserId then ownerLives[e.owner] = math.max(ownerLives[e.owner] or 0, e.life) end
		end
		local active = {}
		for _, e in state.active do
			if e.life ~= ownerLives[e.owner] then continue end
			table.insert(active, e)
			if e.owner == player.UserId and e.life == life then phase, castId = e.kind, e.castId end
		end
		effects.sync(active)
	end
	local connection = remote.OnClientEvent:Connect(function(e: any)
		if e.kind == "snapshot" then snapshot(e.state); return end
		if e.kind == "reply" then
			if not pending or pending.id ~= e.requestId or e.life ~= life then return end
			local requestedAction = pending.action
			pending = nil
			snapshot(e.state)
			if not e.ok and effects.cancelPreview then effects.cancelPreview(e.requestId) end
			if not e.ok then
                if requestedAction == "transfer" and (e.reason == "out_of_range" or e.reason == "invalid_target") then
                    note = "Для переноса нужна свободная ровная земля не дальше 30 от персонажа."
                elseif requestedAction == "transfer" and e.reason == "busy" then
                    note = "Дождитесь появления рук или завершения переноса."
                else note = (reasons :: { [string]: string })[e.reason] or "Действие отклонено. Повторите." end
                noteUntil = now() + 2.5
            end
			return
		end
		if e.owner == player.UserId then
			if e.life ~= life then return end
			if e.kind == "ended" then
				if castId == e.castId then phase, castId = "", nil end
				if e.reason == "invalid_position" then note, noteUntil = reasons.invalid_position, now() + 2.5 end
			else
				phase, castId = if e.kind == "launched" then "flying" else e.kind, e.castId
				if e.readyAt then readyAt = e.readyAt end
			end
		else
			if e.life < (ownerLives[e.owner] or 0) and e.kind ~= "ended" then return end
			ownerLives[e.owner] = math.max(ownerLives[e.owner] or 0, e.life)
		end
		effects.event(e)
	end)
	local unbind = bind(player, function(direction: Vector3)
		if synced and alive and not suspended then send("cast", direction) end
	end, function()
		if phase == "flying" and castId then send("teleport", nil) end
	end, function()
        if phase == "flying" and castId then send("transfer", nil) end
    end)
	local frame = RunService.RenderStepped:Connect(function()
		local time = now()
		effects.step(time)
		if not synced and time - lastSync > 2 then lastSync = time; send("sync", nil) end
		if pending and time - pending.at > 2 then
			if effects.cancelPreview then effects.cancelPreview(pending.id) end
			pending = nil
			note, noteUntil = "Нет подтверждения сервера. Обновляем состояние…", time + 3
			send("sync", nil)
		end
		local status = if not synced then "Подключаемся…" else if not alive then "Возрождение через несколько секунд…"
			else if suspended then "Бой приостановлен" else if pending then "Ожидаем подтверждения…" else if phase == "preparing" then "Подготовка стрелы…"
			else if phase == "flying" then "E — телепортация · F — перенести активные руки"
			else if readyAt > time then string.format("Восстановление · %.1f с", readyAt - time) else "ЛКМ — выпустить стрелу"
		hud.show(status, if time < noteUntil then note else "WASD — движение · Мышь — прицел · E — телепортация · Q → ЛКМ → F — перенос рук")
	end)
	send("sync", nil)
	return function()
		unbind(); connection:Disconnect(); frame:Disconnect()
        if effects.cancelPreview then effects.cancelPreview() end
		effects.destroy(); hud.destroy()
	end
end
return ArrowController
