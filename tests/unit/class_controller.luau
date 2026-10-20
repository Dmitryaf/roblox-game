--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local source = fs.readFile("src/client/controllers/ClassController.luau")
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
local function state(version, life, classId, fields)
	local value = { version = version, life = life, classId = classId or "warlock", alive = true, locked = false, classes = { "warlock", "warrior" } }
	for key, item in fields or {} do value[key] = item end
	return value
end
local function fixture()
	local f = { time = 100, sent = {}, draws = 0, destroyed = false }
	f.messages, f.frames = signal(), signal()
	local game = {}; function game:GetService() return { RenderStepped = f.frames } end
	local world = {}; function world:GetServerTimeNow() return f.time end
	local remote = { OnClientEvent = f.messages }; function remote:FireServer(request) table.insert(f.sent, request) end
	local hud = { setAction = function(action) f.select = action end,
		show = function(value, pending, note) f.state, f.pending, f.note = value, pending, note; f.draws += 1 end,
		destroy = function() f.destroyed = true end }
	local player = { SetAttribute = function() error("ClassController published a client-owned class") end }
	f.stop = luau.load(source, { environment = { game = game, workspace = world } })().start(player, remote, hud)
	function f.frame(delta) f.time += delta or 0.11; f.frames.fire() end
	function f.reply(request, value, ok, reason) f.messages.fire({ kind = "reply", requestId = request.requestId, state = value, ok = ok ~= false, reason = reason }) end
	function f.snapshot(value) f.messages.fire({ kind = "snapshot", state = value }) end
	function f.sync(value) f.reply(f.sent[#f.sent], value); f.frame() end
	return f
end

test("selection waits for a live server class and does not predict the new class", function()
	local f = fixture(); assert(f.sent[1].action == "sync" and f.pending)
	f.select("warrior"); assert(#f.sent == 1)
	f.sync(state(1, 10)); f.select("warrior"); f.frame()
	assert(f.sent[2].action == "select" and f.sent[2].life == 10 and f.sent[2].classId == "warrior")
	assert(f.state.classId == "warlock" and f.pending)
	f.stop()
end)
test("new-life snapshot cannot confirm select; its correlated success reply can", function()
	local f = fixture(); f.sync(state(1, 10)); f.select("warrior")
	local request = f.sent[2]
	f.snapshot(state(2, 11, "warrior")); f.frame()
	assert(f.state.classId == "warrior" and f.state.life == 11 and f.pending)
	f.select("warlock"); assert(#f.sent == 2)
	f.reply(request, state(2, 11, "warrior")); f.frame()
	assert(not f.pending and f.state.life == 11 and f.state.classId == "warrior")
	f.select("warlock"); assert(f.sent[3].life == 11)
	f.stop()
end)
test("older versions and lives cannot roll back class state", function()
	local f = fixture(); f.sync(state(3, 20, "warrior"))
	f.snapshot(state(2, 19, "warlock")); f.snapshot(state(4, 19, "warlock")); f.frame()
	assert(f.state.classId == "warrior" and f.state.version == 3 and f.state.life == 20)
	f.snapshot(state(3, 21, "warrior")); f.frame(); assert(f.state.life == 21)
	f.stop()
end)
test("locked, dead, current and unavailable classes do not send selection requests", function()
	local f = fixture(); f.sync(state(1, 10, "warlock", { locked = true })); f.select("warrior")
	f.snapshot(state(2, 10, "warlock", { alive = false })); f.select("warrior")
	f.snapshot(state(3, 10)); f.select("warlock"); f.select("mage")
	assert(#f.sent == 1)
	f.stop()
end)
test("timeout resync permits retry while late replies cannot confirm a newer choice", function()
	local f = fixture(); f.sync(state(1, 10)); f.select("warrior")
	local old = f.sent[2]; f.frame(3.1)
	local sync = f.sent[#f.sent]; assert(sync.action == "sync" and f.pending)
	f.select("warrior"); assert(f.sent[#f.sent] == sync)
	f.reply(old, state(2, 11, "warrior")); f.frame(); assert(f.state.classId == "warlock" and f.pending)
	f.reply(sync, state(1, 10)); f.frame(); assert(not f.pending)
	f.select("warrior"); local retry = f.sent[#f.sent]
	f.reply(old, state(2, 11, "warrior")); f.frame(); assert(f.pending and f.state.classId == "warlock")
	f.reply(retry, state(2, 11, "warrior")); f.frame(); assert(not f.pending and f.state.classId == "warrior")
	f.stop()
end)
test("server refusal is shown and cleanup disconnects the complete UI lifecycle", function()
	local f = fixture(); f.sync(state(1, 10)); f.select("warrior")
	f.reply(f.sent[2], state(2, 10, "warlock", { locked = true }), false, "locked"); f.frame()
	assert(not f.pending and f.state.classId == "warlock" and string.find(f.note, "вне очереди"))
	local draws = f.draws
	f.stop(); f.frame(10); f.snapshot(state(3, 11, "warrior"))
	assert(f.destroyed and f.draws == draws)
end)
print(string.format("%d ClassController interaction tests passed", total))
