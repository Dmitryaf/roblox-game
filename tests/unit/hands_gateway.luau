--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
local Service = require("../../build/test-source/server/application/combat/HandsService")
local Config = require("../../build/test-source/server/config/Hands")
-- Compile both production network files unchanged. Only Roblox module lookup is mocked.
local Requests = luau.load(fs.readFile("src/shared/contracts/HandsRequests.luau"), { debugName = "HandsRequests" })()
local requestModule = {}
local replicated = { Shared = { contracts = { HandsRequests = requestModule } } }
local game = {}
function game:GetService(name)
	assert(name == "ReplicatedStorage", "Unexpected service dependency")
	return replicated
end
local Gateway = luau.load(fs.readFile("src/server/adapters/networking/HandsGateway.luau"), {
	debugName = "HandsGateway", environment = {
		game = game, require = function(module) assert(module == requestModule); return Requests end,
	},
})()
local total = 0
local function test(name, run)
	run(); total += 1; print("PASS", name)
end
local function cast(id, life, position)
	return { action = "cast", requestId = id, life = life or 10, position = position or Vector3.new(19, 3, -13) }
end
local function fixture()
	local f: any = { now = 100, replies = {}, events = {}, placements = {}, damages = {}, slows = {},
		castCalls = 0, snapshotCalls = 0, disconnected = 0, players = { [1] = { UserId = 1 }, [2] = { UserId = 2 } } }
	f.core = Service.new({
		alive = function(owner) return owner == 1 or owner == 2 end,
		placement = function(owner, position, range, radius)
			table.insert(f.placements, { owner = owner, position = position, range = range, radius = radius })
			return if f.blocked then nil else Vector3.new(position.X, 0.1, position.Z)
		end,
		targets = function() return { "victim" } end,
		damage = function(owner, target, amount) table.insert(f.damages, { owner = owner, target = target, amount = amount }) end,
		slow = function(target, multiplier) f.slows[target] = multiplier end,
		emit = function(event) table.insert(f.events, event) end,
	}, Config)
	f.core.join(1, 10); f.core.join(2, 20)
	local service = {
		cast = function(...)
			f.castCalls += 1
			return f.core.cast(...)
		end,
		snapshot = function(owner)
			f.snapshotCalls += 1
			return f.core.snapshot(owner)
		end,
	}
	local receive, connection
	local remote = {
		OnServerEvent = { Connect = function(_, callback)
			receive, connection = callback, { Connected = true }
			function connection:Disconnect() self.Connected = false; f.disconnected += 1 end
			return connection
		end },
		FireClient = function(_, player, payload) table.insert(f.replies, { player = player, payload = payload }) end,
	}
	f.gateway = Gateway.new(remote, service, function() return f.now end)
	f.gateway.start()
	function f.send(owner, request)
		local count = #f.replies
		if connection.Connected then receive(f.players[owner], request) end
		return if #f.replies > count then f.replies[#f.replies].payload else nil
	end
	function f.step(at) f.now = at; f.core.step(at) end
	return f
end

test("schema accepts a world position and bounded IDs; sync never accepts a target", function()
	assert(Requests.valid(cast(0, 0, Vector3.zero)))
	assert(Requests.valid(cast(2147483647, 2147483647, Vector3.new(10000, -10000, 10000))))
	assert(Requests.valid({ action = "sync", requestId = 1, life = 0 }))
	assert(not Requests.valid({ action = "sync", requestId = 1, life = 10, position = Vector3.zero }))
	assert(not Requests.valid(nil))
end)

test("malformed types, non-finite numbers, forged owner and extra fields never reach service", function()
	local invalid = {
		false, 7, "cast", {}, Vector3.zero,
		{ action = "cast", requestId = 1, life = 10 },
		{ action = "cast", requestId = 1, life = 10, position = { X = 1, Y = 2, Z = 3 } },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.new(0/0, 0, 0) },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.new(0, math.huge, 0) },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.new(0, 0, -math.huge) },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.new(10001, 0, 0) },
		{ action = "cast", requestId = 0/0, life = 10, position = Vector3.zero },
		{ action = "cast", requestId = math.huge, life = 10, position = Vector3.zero },
		{ action = "cast", requestId = 1.5, life = 10, position = Vector3.zero },
		{ action = "cast", requestId = -1, life = 10, position = Vector3.zero },
		{ action = "cast", requestId = 2147483648, life = 10, position = Vector3.zero },
		{ action = "cast", requestId = 1, life = 0/0, position = Vector3.zero },
		{ action = "cast", requestId = 1, life = math.huge, position = Vector3.zero },
		{ action = "cast", requestId = 1, life = -1, position = Vector3.zero },
		{ action = "cast", requestId = 1, life = "10", position = Vector3.zero },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.zero, owner = 2 },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.zero, damage = 999 },
		{ action = "cast", requestId = 1, life = 10, position = Vector3.zero, direction = Vector3.xAxis },
		{ action = "teleport", requestId = 1, life = 10, position = Vector3.zero },
		{ action = string.rep("x", 1000), requestId = 1, life = 10, position = Vector3.zero },
	}
	for _, request in invalid do
		assert(not Requests.valid(request), "Production schema accepted malformed payload")
		local f = fixture()
		assert(f.send(1, request) == nil)
		assert(f.castCalls == 0 and f.snapshotCalls == 0 and #f.placements == 0 and #f.events == 0,
			"Malformed request reached gameplay or state projection")
	end
	local f = fixture()
	assert(f.send(1, nil) == nil and f.castCalls == 0 and f.snapshotCalls == 0)
end)

test("authenticated endpoint preserves position, life and request correlation through damage", function()
	local f = fixture()
	local point = Vector3.new(19, 3, -13)
	local reply = f.send(1, cast(77, 10, point))
	assert(reply.ok and reply.kind == "reply" and reply.requestId == 77 and reply.life == 10)
	assert(reply.state.life == 10 and f.replies[1].player == f.players[1])
	assert(f.castCalls == 1 and #f.placements == 1 and f.placements[1].owner == 1)
	assert(f.placements[1].position == point and f.placements[1].position.Magnitude > 1,
		"Gateway normalized a world-space target as though it were a direction")
	assert(f.events[1].owner == 1 and f.events[1].position == Vector3.new(19, 0.1, -13))
	assert(reply.state.active[1].areaId == f.events[1].areaId and reply.state.active[1].kind == "preparing")
	f.step(100 + Config.windup)
	assert(#f.damages == 0 and f.slows.victim == 0.65)
	f.step(100 + Config.windup + Config.tickInterval)
	assert(#f.damages == 1 and f.damages[1].owner == 1 and f.damages[1].target == "victim" and f.damages[1].amount == 3)
end)

test("stale life is correlated to its rejected request and cannot create an area", function()
	local f = fixture()
	local reply = f.send(1, cast(15, 20))
	assert(not reply.ok and reply.reason == "stale_life" and reply.requestId == 15 and reply.life == 20)
	assert(reply.state.life == 10 and #reply.state.active == 0 and #f.events == 0 and #f.placements == 0)
	reply = f.send(1, cast(16, 10))
	assert(reply.ok and reply.requestId == 16 and #f.events == 1)
end)

test("duplicate and lower IDs cannot repeat casts; another player's IDs remain independent", function()
	local f = fixture()
	assert(f.send(1, cast(7)).ok)
	assert(f.send(1, cast(7, 10, Vector3.zero)) == nil)
	assert(f.send(1, cast(6)) == nil)
	assert(f.castCalls == 1 and #f.events == 1 and #f.replies == 1)
	local reply = f.send(1, cast(8))
	assert(not reply.ok and reply.reason == "busy" and reply.requestId == 8)
	assert(f.castCalls == 2 and #f.events == 1)
	assert(f.send(2, cast(7, 20)).ok)
	assert(f.events[2].owner == 2 and #f.core.snapshot(2).active == 2)
end)

test("invalid high ID does not suppress the next valid lower request", function()
	local f = fixture()
	assert(f.send(1, { action = "cast", requestId = 99999, life = 10, position = Vector3.zero, owner = 2 }) == nil)
	assert(f.send(1, cast(1)).ok and f.castCalls == 1)
end)

test("burst and refill bound replies; forget clears a previous connection's request history", function()
	local f = fixture()
	for id = 1, 100 do f.send(1, { action = "sync", requestId = id, life = 10 }) end
	assert(#f.replies == 12 and f.snapshotCalls == 12 and f.castCalls == 0)
	f.now = 101
	for id = 101, 200 do f.send(1, { action = "sync", requestId = id, life = 10 }) end
	assert(#f.replies == 20 and f.snapshotCalls == 20 and f.castCalls == 0)
	assert(f.send(2, { action = "sync", requestId = 1, life = 20 }).state.life == 20)
	f.gateway.forget(1)
	assert(f.send(1, cast(1)).ok and f.castCalls == 1)
	f.gateway.destroy(); f.gateway.destroy()
	assert(f.disconnected == 1 and f.send(1, cast(2)) == nil)
end)

test("server sync and requested sync expose current life without fabricating cast replies", function()
	local f = fixture()
	local reply = f.send(2, { action = "sync", requestId = 25, life = 0 })
	assert(reply.kind == "snapshot" and reply.requestId == nil and reply.state.life == 20)
	f.gateway.sync(f.players[1])
	local message = f.replies[#f.replies]
	assert(message.player == f.players[1] and message.payload.kind == "snapshot" and message.payload.state.life == 10)
	assert(f.castCalls == 0 and #f.events == 0)
end)

print("Hands gateway/schema contracts:", total, "passed (actual source and service; simulated Roblox boundary)")
