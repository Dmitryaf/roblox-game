--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
-- Execute the unchanged controller; mock only Roblox scheduling, transport and presentation.
local source = fs.readFile("src/client/controllers/HandsController.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function signal()
	local listeners = {}
	local event = {}
	function event:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, { connection, callback })
		return connection
	end
	function event.fire(...)
		for _, item in listeners do if item[1].Connected then item[2](...) end end
	end
	return event
end
local function state(life, fields)
	local result = { life = life, alive = true, suspended = false, readyAt = 0, active = {} }
	for key, value in fields or {} do result[key] = value end
	return result
end
local function area(owner, life, id, kind)
	return { owner = owner, life = life, areaId = id, kind = kind or "preparing", readyAt = 109, expiresAt = 105 }
end
local function fixture()
	local f = { time = 100, sent = {}, events = {}, snapshots = {}, draws = {}, destroyed = false, unbound = false, stepped = 0 }
	f.messages, f.frames = signal(), signal()
	local game = {}; function game:GetService() return { RenderStepped = f.frames } end
	local world = {}; function world:GetServerTimeNow() return f.time end
	local remote = { OnClientEvent = f.messages }
	function remote:FireServer(request) table.insert(f.sent, request) end
	local hud = {
		show = function(status, note) f.status, f.note = status, note; table.insert(f.draws, { status, note }) end,
		destroy = function() f.destroyed = true end,
	}
	local effects = {
		event = function(event) table.insert(f.events, event) end,
		sync = function(active) table.insert(f.snapshots, active) end,
		step = function() f.stepped += 1 end,
		destroy = function() f.effectsDestroyed = true end,
	}
	local bind = function(_, cast, invalid)
		f.cast, f.invalid = cast, invalid
		return function() f.unbound = true end
	end
	local module = luau.load(source, { environment = { game = game, workspace = world } })()
	f.stop = module.start({ UserId = 10 }, remote, hud, effects, bind)
	function f.frame(delta) f.time += delta or 0.11; f.frames.fire() end
	function f.snapshot(value) f.messages.fire({ kind = "snapshot", state = value }) end
	function f.reply(request, value, ok, reason)
		f.messages.fire({ kind = "reply", requestId = request.requestId, life = value.life, state = value, ok = ok ~= false, reason = reason })
	end
	function f.sync(value) f.reply(f.sent[#f.sent], value); f.frame() end
	return f
end
local target = Vector3.new(5, 0, -10)

test("cast waits for the initial life snapshot and forwards the exact target", function()
	local f = fixture()
	assert(#f.sent == 1 and f.sent[1].action == "sync" and f.sent[1].life == 0)
	f.cast(target); assert(#f.sent == 1)
	f.sync(state(50)); f.cast(target)
	local request = f.sent[#f.sent]
	assert(request.action == "cast" and request.life == 50 and request.position == target)
	f.stop()
end)
test("pending requests are correlated and preparation requires server confirmation", function()
	local f = fixture(); f.sync(state(50)); f.cast(target)
	local request = f.sent[#f.sent]
	f.frame(); assert(string.find(f.status, "подтверждения") and #f.events == 0)
	f.cast(target); assert(#f.sent == 2)
	f.reply({ requestId = request.requestId - 1 }, state(50)); f.frame()
	assert(string.find(f.status, "подтверждения"))
	f.reply(request, state(50, { active = { area(10, 50, 1) } })); f.frame()
	assert(string.find(f.status, "Собираем") and #f.snapshots[#f.snapshots] == 1)
	f.stop()
end)
test("foreign owners use their own life sequence; snapshots reject stale areas", function()
	local f = fixture(); f.sync(state(50))
	f.messages.fire(area(10, 49, 1)); f.messages.fire(area(10, 51, 2))
	assert(#f.events == 0)
	f.messages.fire(area(20, 1, 3)); assert(#f.events == 1)
	f.messages.fire(area(20, 2, 4)); f.messages.fire(area(20, 1, 3, "ended"))
	assert(#f.events == 2)
	f.snapshot(state(50, { active = { area(10, 49, 1), area(20, 1, 3), area(20, 2, 4), area(30, 1, 5) } }))
	local filtered = f.snapshots[#f.snapshots]
	assert(#filtered == 2 and filtered[1].owner == 20 and filtered[1].life == 2 and filtered[2].owner == 30)
	f.stop()
end)
test("timeout blocks casts until resync and late replies cannot confirm the retry", function()
	local f = fixture(); f.sync(state(50)); f.cast(target)
	local old = f.sent[#f.sent]
	f.frame(2.6)
	local sync = f.sent[#f.sent]
	assert(sync.action == "sync" and string.find(f.note, "подтверждения"))
	f.cast(target); assert(f.sent[#f.sent] == sync)
	f.reply(old, state(50)); f.frame(); assert(string.find(f.status, "Обновляем"))
	f.reply(sync, state(50)); f.frame(); assert(string.find(f.note, "обновлено"))
	f.cast(target); local retry = f.sent[#f.sent]
	assert(retry.action == "cast" and retry.requestId > sync.requestId)
	f.reply(old, state(50)); f.frame(); assert(string.find(f.status, "подтверждения"))
	f.reply(retry, state(50), false, "out_of_range"); f.frame(); assert(string.find(f.note, "Слишком далеко"))
	f.stop()
end)
test("new life clears the old pending context without accepting its late reply", function()
	local f = fixture(); f.sync(state(50)); f.cast(target)
	local old = f.sent[#f.sent]
	f.snapshot(state(51)); f.frame()
	f.cast(target); local current = f.sent[#f.sent]
	assert(current.life == 51)
	f.reply(old, state(50), false, "cooldown"); f.frame()
	assert(string.find(f.status, "подтверждения") and not string.find(f.note, "восстанавливаются"))
	f.reply(current, state(51)); f.frame(); assert(not string.find(f.status, "подтверждения"))
	f.stop()
end)
test("old area end does not replace the current area or its cooldown", function()
	local f = fixture(); f.sync(state(50))
	f.messages.fire(area(10, 50, 10, "active")); f.frame()
	assert(string.find(f.status, "Область действует"))
	local old = area(10, 50, 9, "ended"); old.readyAt = 999
	f.messages.fire(old); f.frame(); assert(string.find(f.status, "Область действует"))
	local currentEnd = area(10, 50, 10, "ended"); currentEnd.readyAt = nil
	f.messages.fire(currentEnd); f.frame()
	assert(f.status == "Восстановление · 8.6 с", "A stale area end replaced the current readyAt")
	f.stop()
end)
test("pause and death gate casts; ground failure is actionable without a network request", function()
	local f = fixture(); f.sync(state(50, { suspended = true }))
	local before = #f.sent
	f.cast(target); assert(#f.sent == before and string.find(f.status, "приостановлен"))
	f.snapshot(state(50, { alive = false })); f.frame(); f.cast(target)
	assert(#f.sent == before and string.find(f.status, "возрождения"))
	f.snapshot(state(50)); f.invalid(); f.frame()
	assert(#f.sent == before and string.find(f.note, "земли"))
	f.stop()
end)
test("cleanup disconnects input, server messages, frame updates and owned presentation", function()
	local f = fixture(); f.sync(state(50))
	local draws, events, stepped = #f.draws, #f.events, f.stepped
	f.stop(); f.frame(10); f.messages.fire(area(20, 5, 1))
	assert(f.destroyed and f.effectsDestroyed and f.unbound)
	assert(#f.draws == draws and #f.events == events and f.stepped == stepped)
end)
print(string.format("%d HandsController interaction tests passed", total))
