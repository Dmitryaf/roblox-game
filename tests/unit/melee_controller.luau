--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
local source = fs.readFile("src/client/controllers/MeleeController.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function signal()
	local listeners, event = {}, {}
	function event:Connect(callback)
		local c = { Connected = true }; function c:Disconnect() self.Connected = false end
		table.insert(listeners, { c, callback }); return c
	end
	function event.fire(...) for _, item in listeners do if item[1].Connected then item[2](...) end end end
	return event
end
local function state(life, fields)
	local value = { life = life, alive = true, suspended = false, readyAt = 0, active = {} }
	for key, item in fields or {} do value[key] = item end
	return value
end
local function swing(owner, life, id, kind)
	return { owner = owner, life = life, swingId = id, kind = kind or "preparing", readyAt = 101, expiresAt = 100.75 }
end
local function fixture()
	local f = { time = 100, classId = "warrior", sent = {}, events = {}, snapshots = {}, draws = {}, stepped = 0 }
	f.messages, f.frames = signal(), signal()
	local character = {}; function character:GetAttribute() return f.classId end
	local game = {}; function game:GetService() return { RenderStepped = f.frames } end
	local world = {}; function world:GetServerTimeNow() return f.time end
	local remote = { OnClientEvent = f.messages }; function remote:FireServer(request) table.insert(f.sent, request) end
	local hud = { show = function(status, note) f.status, f.note = status, note; table.insert(f.draws, status) end,
		destroy = function() f.hudDestroyed = true end }
	local effects = { event = function(event) table.insert(f.events, event) end,
		sync = function(active) table.insert(f.snapshots, active) end, step = function() f.stepped += 1 end,
		destroy = function() f.effectsDestroyed = true end }
	local bind = function(_, callback) f.attack = callback; return function() f.unbound = true end end
	f.stop = luau.load(source, { environment = { game = game, workspace = world } })().start(
		{ UserId = 10, Character = character }, remote, hud, effects, bind)
	function f.frame(delta) f.time += delta or 0.11; f.frames.fire() end
	function f.snapshot(value) f.messages.fire({ kind = "snapshot", state = value }) end
	function f.reply(request, value, ok, reason)
		f.messages.fire({ kind = "reply", requestId = request.requestId, life = value.life, state = value, ok = ok ~= false, reason = reason })
	end
	function f.sync(value) f.reply(f.sent[#f.sent], value); f.frame() end
	return f
end
local direction = Vector3.new(1, 0, -1).Unit

test("sync and server-owned class gate attacks before forwarding their direction", function()
	local f = fixture(); f.attack(direction); assert(#f.sent == 1 and f.sent[1].action == "sync")
	f.sync(state(50)); f.classId = "warlock"; f.attack(direction); assert(#f.sent == 1)
	f.classId = nil; f.attack(direction); assert(#f.sent == 1)
	f.classId = "warrior"; f.attack(direction)
	assert(f.sent[2].life == 50 and f.sent[2].action == "cast" and f.sent[2].direction == direction)
	f.stop()
end)
test("preparation and recovery come from the server without predicting a hit", function()
	local f = fixture(); f.sync(state(50)); f.attack(direction)
	local request = f.sent[2]; f.frame()
	assert(string.find(f.status, "подтверждения") and #f.events == 0)
	f.attack(direction); assert(#f.sent == 2)
	f.reply({ requestId = request.requestId - 1 }, state(50)); f.frame(); assert(string.find(f.status, "подтверждения"))
	f.reply(request, state(50, { active = { swing(10, 50, 1) } })); f.frame(); assert(string.find(f.status, "Подготовка"))
	f.messages.fire(swing(10, 50, 1, "struck")); f.frame(); assert(string.find(f.status, "Возвращаем"))
	f.messages.fire(swing(10, 50, 1, "ended")); f.frame(); assert(string.find(f.status, "Восстановление"))
	f.stop()
end)
test("foreign lives are independent of the local life and stale snapshots are filtered", function()
	local f = fixture(); f.sync(state(50))
	f.messages.fire(swing(10, 49, 1)); f.messages.fire(swing(10, 51, 2)); assert(#f.events == 0)
	f.messages.fire(swing(20, 1, 3)); f.messages.fire(swing(20, 2, 4)); f.messages.fire(swing(20, 1, 3, "ended"))
	assert(#f.events == 2)
	f.snapshot(state(50, { active = { swing(10, 49, 1), swing(20, 1, 3), swing(20, 2, 4), swing(30, 1, 5) } }))
	local active = f.snapshots[#f.snapshots]
	assert(#active == 2 and active[1].owner == 20 and active[1].life == 2 and active[2].owner == 30)
	f.stop()
end)
test("timeout and resync keep old replies from confirming a new attack", function()
	local f = fixture(); f.sync(state(50)); f.attack(direction)
	local old = f.sent[2]; f.frame(2.6)
	local sync = f.sent[#f.sent]; assert(sync.action == "sync")
	f.attack(direction); assert(f.sent[#f.sent] == sync)
	f.reply(old, state(50)); f.frame(); assert(string.find(f.status, "Обновляем"))
	f.reply(sync, state(50)); f.frame(); f.attack(direction)
	local retry = f.sent[#f.sent]; assert(retry.requestId > sync.requestId)
	f.reply(old, state(50)); f.frame(); assert(string.find(f.status, "подтверждения"))
	f.reply(retry, state(50), false, "busy"); f.frame(); assert(string.find(f.note, "текущий взмах"))
	f.stop()
end)
test("new life and class switch reject old replies while retaining foreign effects", function()
	local f = fixture(); f.sync(state(50)); f.attack(direction)
	local old = f.sent[2]
	f.classId = "warlock"; f.snapshot(state(51)); f.frame()
	local before = #f.sent; f.attack(direction); assert(#f.sent == before)
	f.reply(old, state(50), false, "cooldown"); f.frame(); assert(not string.find(f.note, "восстанавливается"))
	f.messages.fire(swing(20, 3, 7)); assert(#f.events == 1)
	f.stop()
end)
test("pause and death prevent swings and an unrelated end cannot alter cooldown", function()
	local f = fixture(); f.sync(state(50, { suspended = true })); f.attack(direction); assert(#f.sent == 1)
	f.snapshot(state(50, { alive = false })); f.attack(direction); assert(#f.sent == 1)
	f.snapshot(state(50)); f.messages.fire(swing(10, 50, 10, "struck")); f.frame()
	local old = swing(10, 50, 9, "ended"); old.readyAt = 999; f.messages.fire(old); f.frame()
	assert(string.find(f.status, "Возвращаем"))
	local ended = swing(10, 50, 10, "ended"); ended.readyAt = nil; f.messages.fire(ended); f.frame()
	assert(f.status == "Восстановление · 0.6 с")
	f.stop()
end)
test("cleanup disconnects input, remote events, scheduling and owned UI/effects", function()
	local f = fixture(); f.sync(state(50))
	local draws, count, stepped = #f.draws, #f.events, f.stepped
	f.stop(); f.frame(10); f.messages.fire(swing(20, 5, 8))
	assert(f.unbound and f.hudDestroyed and f.effectsDestroyed)
	assert(#f.draws == draws and #f.events == count and f.stepped == stepped)
end)
print(string.format("%d MeleeController interaction tests passed", total))
