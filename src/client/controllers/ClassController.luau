--!strict
local RunService = game:GetService("RunService")
local ClassController = {}
local reasons: { [string]: string } = {
	locked = "Класс можно сменить в тренировке вне очереди.",
	class_locked = "Класс можно сменить в тренировке вне очереди.",
	dead = "Дождитесь возрождения, чтобы сменить класс.",
	stale_life = "Персонаж изменился. Повторите выбор.",
	unknown_class = "Этот класс сейчас недоступен.",
	invalid_class = "Этот класс сейчас недоступен.",
	not_ready = "Ожидаем персонажа. Повторите выбор после появления.",
	unknown_player = "Подключение ещё не завершено. Повторите выбор.",
}

function ClassController.start(_player: Player, remote: RemoteEvent, hud: any)
	local state: any = nil
	local requestId, lastSync, lastDraw = 0, 0, -1
	local syncId: number? = nil
	local pending: { id: number, at: number }? = nil
	local recovering = false
	local note, noteUntil = "", 0
	local function now(): number return workspace:GetServerTimeNow() end
	local function snapshot(value: any): boolean
		if type(value) ~= "table" or type(value.version) ~= "number" or type(value.life) ~= "number" then return false end
		if state and (value.version < state.version or value.life < state.life) then return false end
		if not state or value.version > state.version or value.life > state.life then state = value end
		if recovering then note, noteUntil = "Состояние обновлено. Повторите выбор.", now() + 2.5 end
		recovering = false
		-- A class change can publish its new life before the correlated select reply.
		-- Neither this snapshot nor that life change confirms a pending action.
		return true
	end
	local function send(action: string, classId: string?)
		if action ~= "sync" then
			if not state or state.life <= 0 or not state.alive or state.locked or pending or recovering then return end
			if classId == state.classId or not table.find(state.classes, classId) then return end
		end
		requestId += 1
		local message: any = { action = action, requestId = requestId, life = if state then state.life else 0 }
		if action == "select" then
			message.classId = classId
			pending = { id = requestId, at = now() }
			note, noteUntil = "", 0
		else syncId, lastSync = requestId, now() end
		remote:FireServer(message)
	end
	local connection = remote.OnClientEvent:Connect(function(event: any)
		if type(event) ~= "table" then return end
		if event.kind == "snapshot" then snapshot(event.state); return end
		if event.kind ~= "reply" then return end
		local actionReply = pending ~= nil and pending.id == event.requestId
		local syncReply = syncId ~= nil and syncId == event.requestId
		if not actionReply and not syncReply then return end
		snapshot(event.state)
		if syncReply then syncId = nil end
		if actionReply then
			pending = nil
			if not event.ok then note, noteUntil = reasons[event.reason] or "Не удалось сменить класс. Повторите выбор.", now() + 3.5 end
		end
	end)
	hud.setAction(function(classId: string) send("select", classId) end)
	local frame = RunService.RenderStepped:Connect(function()
		local time = now()
		if (not state or state.life <= 0 or recovering) and time - lastSync > 2 then send("sync", nil) end
		if pending and time - pending.at > 3 then
			pending, recovering = nil, true
			note, noteUntil = "Нет подтверждения. Обновляем выбор класса…", time + 5
			send("sync", nil)
		end
		if time - lastDraw < 0.1 then return end
		lastDraw = time
		hud.show(state, not state or recovering or pending ~= nil, if time < noteUntil then note else "")
	end)
	hud.show(nil, true, "Получаем классы сервера…")
	send("sync", nil)
	return function()
		connection:Disconnect(); frame:Disconnect()
		hud.destroy()
	end
end
return ClassController
