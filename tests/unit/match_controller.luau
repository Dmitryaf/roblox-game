--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
-- Compile the production source without editing it; only the Roblox boundary is mocked.
local source = fs.readFile("src/client/controllers/MatchController.luau")
local total = 0
local function test(name, run)
	run()
	total += 1
	print("PASS", name)
end
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
local function state(version, fields)
	local value = { version = version, matchId = 0, phase = "idle", mode = "training", ready = false,
		scoreA = 0, scoreB = 0, remaining = 300, zone = "neutral", countA = 0, countB = 0, frozen = false }
	for key, field in fields or {} do value[key] = field end
	return value
end
local function fixture()
	local f = { time = 100, sent = {}, focused = nil, draws = {}, destroyed = false }
	f.input, f.render, f.messages = signal(), signal(), signal()
	local inputService = { InputBegan = f.input }
	function inputService:GetFocusedTextBox() return f.focused end
	local services = { RunService = { RenderStepped = f.render }, UserInputService = inputService }
	local game = {}
	function game:GetService(name) return assert(services[name]) end
	local world = {}
	function world:GetServerTimeNow() return f.time end
	local remote = { OnClientEvent = f.messages }
	function remote:FireServer(request) table.insert(f.sent, request) end
	local hud = {}
	function hud.setAction(callback) f.action = callback end
	function hud.show(snapshot, pending, note)
		f.shown = { state = snapshot, pending = pending, note = note }
		table.insert(f.draws, f.shown)
	end
	function hud.destroy() f.destroyed = true end
	local Controller = luau.load(source, { debugName = "MatchController", environment = {
		game = game, workspace = world, Enum = { KeyCode = { R = "R", B = "B" } },
	} })()
	f.stop = Controller.start({}, remote, hud)
	function f.frame(delta) f.time += delta or 0.11; f.render.fire() end
	function f.reply(request, snapshot, ok, reason)
		f.messages.fire({ kind = "reply", requestId = request.requestId, state = snapshot, ok = ok ~= false, reason = reason })
	end
	function f.snapshot(snapshot) f.messages.fire({ kind = "snapshot", state = snapshot }) end
	function f.key(key, processed) f.input.fire({ KeyCode = key }, processed == true) end
	function f.sync(snapshot)
		f.reply(f.sent[#f.sent], snapshot)
		f.frame()
	end
	return f
end

test("load waits for server confirmation; input is gated until synced", function()
	local f = fixture()
	assert(#f.sent == 1 and f.sent[1].action == "sync" and f.shown.pending)
	f.action("ready"); f.key("R")
	assert(#f.sent == 1)
	f.sync(state(1))
	assert(not f.shown.pending and f.shown.state.mode == "training")
	f.key("R")
	assert(#f.sent == 2 and f.sent[2].action == "ready" and f.sent[2].matchId == 0)
	f.stop()
end)

test("periodic snapshots and unrelated replies cannot confirm a pending action", function()
	local f = fixture(); f.sync(state(1)); f.action("ready")
	local request = f.sent[#f.sent]
	f.snapshot(state(2, { ready = true })); f.frame()
	assert(f.shown.pending and f.shown.state.ready)
	f.reply({ requestId = request.requestId - 1 }, state(1)); f.frame()
	assert(f.shown.pending and f.shown.state.ready)
	f.action("cancel"); assert(#f.sent == 2)
	f.reply(request, state(2, { ready = true })); f.frame()
	assert(not f.shown.pending and f.shown.state.ready)
	f.stop()
end)

test("timeout blocks new actions; equal-version sync restores access; old reply is ignored", function()
	local f = fixture(); f.sync(state(4)); f.action("ready")
	local old = f.sent[#f.sent]
	f.frame(3.1)
	local sync = f.sent[#f.sent]
	assert(sync.action == "sync" and f.shown.pending and string.find(f.shown.note, "подтверждения"))
	f.action("ready"); assert(f.sent[#f.sent] == sync)
	f.reply(old, state(4), false, "invalid"); f.frame()
	assert(f.shown.pending)
	f.reply(sync, state(4)); f.frame()
	assert(not f.shown.pending)
	f.action("ready")
	assert(f.sent[#f.sent].action == "ready" and f.sent[#f.sent].requestId > sync.requestId)
	f.reply(old, state(4)); f.frame()
	assert(f.shown.pending)
	f.stop()
end)

test("newer match supersedes pending context; delayed old match cannot replace it", function()
	local f = fixture(); f.sync(state(5)); f.action("ready")
	local old = f.sent[#f.sent]
	f.snapshot(state(6, { matchId = 1, phase = "countdown", mode = "match", team = 1 })); f.frame()
	assert(not f.shown.pending and f.shown.state.matchId == 1)
	f.key("B")
	local exit = f.sent[#f.sent]
	assert(exit.action == "exit" and exit.matchId == 1)
	f.reply(old, state(5), false, "stale_match"); f.frame()
	assert(f.shown.pending and f.shown.state.matchId == 1 and f.shown.note == "")
	f.reply(exit, state(7, { matchId = 1 })); f.frame()
	assert(not f.shown.pending and f.shown.state.mode == "training")
	f.stop()
end)

test("clock advances only while active; pause freezes it and uses authoritative deadlines", function()
	local f = fixture(); f.sync(state(10, { matchId = 1, phase = "active", mode = "match", remaining = 50 }))
	f.frame(2)
	assert(math.abs(f.shown.state.displayRemaining - 47.89) < 0.001)
	f.snapshot(state(11, { matchId = 1, phase = "paused", mode = "match", remaining = 47, deadline = f.time + 15 }))
	f.frame(5)
	assert(f.shown.state.displayRemaining == 47 and f.shown.state.displayDeadline == 10)
	f.snapshot(state(10, { matchId = 1, phase = "active", remaining = 50 })); f.frame()
	assert(f.shown.state.phase == "paused" and f.shown.state.displayRemaining == 47)
	f.stop()
end)

test("reserved pair can cancel with R; active participant exits with B; typing is respected", function()
	local f = fixture()
	f.sync(state(2, { matchId = 1, phase = "active", mode = "match", ready = true, frozen = true, pairDeadline = 103 }))
	f.key("R", true); f.focused = {}; f.key("R"); f.key("B"); f.focused = nil
	assert(#f.sent == 1)
	f.key("R"); local cancel = f.sent[#f.sent]
	assert(cancel.action == "cancel" and cancel.matchId == 1)
	f.reply(cancel, state(3, { matchId = 1 })); f.frame()
	f.snapshot(state(4, { matchId = 1, phase = "active", mode = "match", team = 2 })); f.frame()
	f.key("R"); assert(#f.sent == 2)
	f.key("B"); assert(f.sent[#f.sent].action == "exit")
	f.stop()
end)

test("decline is correlated, shown without optimistic success and can be retried", function()
	local f = fixture(); f.sync(state(1)); f.action("ready")
	local request = f.sent[#f.sent]
	f.reply(request, state(1), false, "stale_match"); f.frame()
	assert(not f.shown.pending and not f.shown.state.ready and string.find(f.shown.note, "повторите"))
	f.action("ready"); assert(#f.sent == 3)
	f.stop()
end)

test("cleanup disconnects input, remote and frame and destroys the HUD", function()
	local f = fixture(); f.sync(state(1))
	local sent, draws = #f.sent, #f.draws
	f.stop(); f.key("R"); f.frame(10); f.snapshot(state(100))
	assert(f.destroyed and #f.sent == sent and #f.draws == draws)
end)
print(string.format("%d MatchController interaction tests passed", total))
