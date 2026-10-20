--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Service = require("../../build/test-source/server/application/lobby/ClassService")
local Requests = luau.load(fs.readFile("src/shared/contracts/ClassRequests.luau"), { debugName = "ClassRequests" })()
local module = {}
local game = {}
function game:GetService(name)
	assert(name == "ReplicatedStorage")
	return { Shared = { contracts = { ClassRequests = module } } }
end
local Gateway = luau.load(fs.readFile("src/server/adapters/networking/ClassGateway.luau"), {
	debugName = "ClassGateway", environment = {
		game = game, require = function(value) assert(value == module); return Requests end,
	},
})()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
	local f: any = { now = 100, lives = { [1] = 10, [2] = 20 }, locked = {}, changes = {},
		replies = {}, selected = 0, snapshots = 0, disconnected = 0 }
	f.core = Service.new({
		life = function(owner) return f.lives[owner] or 0 end,
		alive = function(owner) return f.lives[owner] ~= nil end,
		locked = function(owner) return f.locked[owner] == true end,
		changed = function(owner, classId)
			assert(f.core.get(owner) == classId)
			f.lives[owner] += 1
			table.insert(f.changes, { owner = owner, classId = classId })
		end,
	})
	f.core.join(1); f.core.join(2)
	local service = {
		select = function(...) f.selected += 1; return f.core.select(...) end,
		snapshot = function(owner) f.snapshots += 1; return f.core.snapshot(owner) end,
	}
	local receive, connection
	local remote = { OnServerEvent = { Connect = function(_, callback)
		receive, connection = callback, { Connected = true }
		function connection:Disconnect() self.Connected = false; f.disconnected += 1 end
		return connection
	end }, FireClient = function(_, player, payload) table.insert(f.replies, { player = player, payload = payload }) end }
	f.gateway = Gateway.new(remote, service, function() return f.now end); f.gateway.start()
	function f.send(owner, request)
		local before = #f.replies
		if connection.Connected then receive({ UserId = owner }, request) end
		return if #f.replies > before then f.replies[#f.replies].payload else nil
	end
	return f
end
local function select(id, life, classId)
	return { action = "select", requestId = id, life = life or 10, classId = classId or "warrior" }
end
test("allowlist and schema accept only finite bounded IDs and exact select/sync shapes", function()
	for _, classId in { "warlock", "warrior" } do assert(Requests.valid(select(0, 0, classId))) end
	assert(Requests.valid(select(2147483647, 2147483647)))
	assert(Requests.valid({ action = "sync", requestId = 1, life = 0 }))
	assert(not Requests.valid(nil))
	local invalid = {
		false, 4, "select", {}, { action = "select", requestId = 1, life = 10 },
		{ action = "sync", requestId = 1, life = 10, classId = "warrior" },
		{ action = "select", requestId = 1, life = 10, classId = "warrior", owner = 2 },
		{ action = "select", requestId = 1, life = 10, classId = "warrior", class = "warlock" },
		select(1, 10, "archon"), select(1, 10, "Warrior"), select(1, 10, 3),
		select(0/0), select(math.huge), select(-1), select(1.5), select(2147483648),
		select(1, 0/0), select(1, math.huge), select(1, -1), select(1, "10"),
		{ action = "reset", requestId = 1, life = 10, classId = "warrior" },
	}
	for _, request in invalid do
		assert(not Requests.valid(request))
		local f = fixture()
		assert(f.send(1, request) == nil and f.selected == 0 and f.snapshots == 0 and #f.changes == 0)
	end
end)
test("authenticated selection returns correlated new life and changes only its owner", function()
	local f = fixture(); local reply = f.send(1, select(71))
	assert(reply.kind == "reply" and reply.requestId == 71 and reply.ok)
	assert(reply.state.classId == "warrior" and reply.state.life == 11 and #f.changes == 1)
	assert(f.replies[1].player.UserId == 1 and f.core.get(2) == "warlock" and f.lives[2] == 20)
	reply = f.send(1, select(72, 10, "warlock"))
	assert(not reply.ok and reply.reason == "stale_life" and reply.requestId == 72 and reply.state.life == 11)
	assert(f.core.get(1) == "warrior" and #f.changes == 1)
end)
test("dynamic lock rejects a valid network command without resetting or changing selection", function()
	local f = fixture(); f.locked[1] = true
	local reply = f.send(1, select(1))
	assert(not reply.ok and reply.reason == "locked" and reply.requestId == 1 and reply.state.locked)
	assert(reply.state.classId == "warlock" and reply.state.life == 10 and #f.changes == 0)
	f.locked[1] = false
	assert(f.send(1, select(2)).ok and #f.changes == 1)
end)
test("duplicate/lower IDs and malformed high ID cannot replay or suppress selection", function()
	local f = fixture()
	assert(f.send(1, { action = "select", requestId = 9999, life = 10, classId = "warrior", owner = 2 }) == nil)
	assert(f.send(1, select(7)).ok)
	assert(f.send(1, select(7, 11, "warlock")) == nil and f.send(1, select(6, 11, "warlock")) == nil)
	assert(f.selected == 1 and #f.changes == 1)
	assert(f.send(2, select(7, 20)).ok and #f.changes == 2)
	assert(f.send(1, select(8, 11, "warlock")).ok and f.lives[1] == 12 and #f.changes == 3)
end)
test("requested sync is correlated; unsolicited sync is a separate snapshot", function()
	local f = fixture(); local reply = f.send(1, { action = "sync", requestId = 37, life = 0 })
	assert(reply.kind == "reply" and reply.ok and reply.requestId == 37 and reply.state.life == 10)
	f.gateway.sync({ UserId = 2 })
	local latest = f.replies[#f.replies]
	assert(latest.player.UserId == 2 and latest.payload.kind == "snapshot" and latest.payload.requestId == nil
		and latest.payload.state.life == 20 and f.selected == 0)
end)
test("burst/refill and forget isolate sessions; repeated destroy disconnects once", function()
	local f = fixture()
	for id = 1, 100 do f.send(1, { action = "sync", requestId = id, life = 10 }) end
	assert(#f.replies == 12 and f.snapshots == 12 and f.selected == 0)
	f.now = 101
	for id = 101, 200 do f.send(1, { action = "sync", requestId = id, life = 10 }) end
	assert(#f.replies == 20 and f.snapshots == 20)
	f.gateway.forget(1)
	assert(f.send(1, select(1)).ok)
	f.gateway.destroy(); f.gateway.destroy()
	assert(f.disconnected == 1 and f.send(1, select(2, 11, "warlock")) == nil)
end)
print("Class gateway/schema contracts:", total, "passed (actual network source and selection service)")
