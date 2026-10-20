--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
local source = fs.readFile("src/client/controllers/DashController.luau")
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
local function dash(owner, life, id, kind)
	return { owner = owner, life = life, dashId = id, kind = kind or "started", readyAt = 105, expiresAt = 100.28 }
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
	local bind = function(_, callback) f.cast = callback; return function() f.unbound = true end end
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
test("only a synced living warrior can forward a dash direction", function()
	local f = fixture(); f.cast(direction); assert(#f.sent == 1 and f.sent[1].action == "sync")
	f.sync(state(50)); f.classId = "warlock"; f.cast(direction); assert(#f.sent == 1)
	f.classId = nil; f.cast(direction); assert(#f.sent == 1)
	f.classId = "warrior"; f.cast(direction)
	assert(f.sent[2].life == 50 and f.sent[2].action == "cast" and f.sent[2].direction == direction)
	f.stop()
end)
test("only the correlated reply confirms a pending request; snapshots preserve newer pending input", function()
	local f = fixture(); f.sync(state(50)); f.cast(direction)
	local request = f.sent[2]; f.frame(); assert(string.find(f.status, "подтверждения") and #f.events == 0)
	f.snapshot(state(50)); f.reply({ requestId = request.requestId - 1 }, state(50)); f.frame()
	assert(string.find(f.status, "подтверждения")); f.cast(direction); assert(#f.sent == 2)
	f.reply(request, state(50, { readyAt = 105, active = { dash(10, 50, 1) } })); f.frame()
	assert(string.find(f.status, "Восстановление")) -- Server clock already passed this short dash.
	f.stop()
end)
test("timeout resync blocks retry and old action replies cannot confirm a new request", function()
	local f = fixture(); f.sync(state(50)); f.cast(direction); local old = f.sent[2]
	f.frame(2.6); local sync = f.sent[#f.sent]; assert(sync.action == "sync")
	f.cast(direction); assert(f.sent[#f.sent] == sync)
	f.reply(old, state(50)); f.frame(); assert(string.find(f.status, "Обновляем"))
	f.reply(sync, state(50)); f.frame(); f.cast(direction); local retry = f.sent[#f.sent]
	f.reply(old, state(50)); f.frame(); assert(string.find(f.status, "подтверждения"))
	f.reply(retry, state(50), false, "blocked"); f.frame(); assert(string.find(f.note, "препятствие")); f.stop()
end)
test("new local life invalidates old replies while foreign owner lives remain independent", function()
	local f = fixture(); f.sync(state(50)); f.cast(direction); local old = f.sent[2]
	f.snapshot(state(51)); f.cast(direction); local current = f.sent[3]
	f.reply(old, state(50), false, "cooldown"); f.frame(); assert(string.find(f.status, "подтверждения"))
	f.reply(current, state(51)); f.messages.fire(dash(10, 50, 1)); assert(#f.events == 0)
	f.messages.fire(dash(20, 1, 2)); f.messages.fire(dash(20, 2, 3)); f.messages.fire(dash(20, 1, 2, "ended"))
	assert(#f.events == 2)
	f.snapshot(state(51, { active = { dash(10, 50, 1), dash(20, 1, 2), dash(20, 2, 3), dash(30, 1, 4) } }))
	local active = f.snapshots[#f.snapshots]
	assert(#active == 2 and active[1].owner == 20 and active[1].life == 2 and active[2].owner == 30); f.stop()
end)
test("ended-before-started and late active snapshots cannot resurrect completed dash effects", function()
	local f = fixture(); f.sync(state(50))
	local ended = dash(10, 50, 10, "ended"); ended.reason = "expired"
	f.messages.fire(ended); f.messages.fire(dash(10, 50, 10)); assert(#f.events == 1)
	f.snapshot(state(50, { readyAt = 105, active = { dash(10, 50, 10) } }))
	assert(#f.snapshots[#f.snapshots] == 0)
	f.messages.fire(dash(10, 50, 11)); f.frame(); assert(string.find(f.status, "Рывок"))
	local unrelated = dash(10, 50, 9, "ended"); unrelated.readyAt = 999
	f.messages.fire(unrelated); f.frame(); assert(string.find(f.status, "Восстановление 4."))
	f.stop()
end)
test("pause death and class change block input and clear local active presentation", function()
	local f = fixture(); f.sync(state(50, { suspended = true })); f.cast(direction); assert(#f.sent == 1)
	f.snapshot(state(50, { alive = false, active = { dash(10, 50, 1) } })); f.cast(direction)
	assert(#f.sent == 1 and #f.snapshots[#f.snapshots] == 0)
	f.classId = "warlock"; f.snapshot(state(51)); f.cast(direction); assert(#f.sent == 1); f.stop()
end)
test("cleanup disconnects input events scheduling and all owned presentation", function()
	local f = fixture(); f.sync(state(50)); local draws, count, stepped = #f.draws, #f.events, f.stepped
	f.stop(); f.frame(10); f.messages.fire(dash(20, 5, 8))
	assert(f.unbound and f.hudDestroyed and f.effectsDestroyed)
	assert(#f.draws == draws and #f.events == count and f.stepped == stepped)
end)
print(string.format("%d DashController interaction tests passed", total))
