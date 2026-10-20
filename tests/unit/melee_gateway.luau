--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
local SwordSwing = require("../../build/test-source/server/domain/combat/SwordSwing")
local Config = require("../../build/test-source/server/config/Warrior")
-- Production text stays unchanged; only Roblox lookup and the engine Vector3 global are injected.
local Requests = luau.load(fs.readFile("src/shared/contracts/Requests.luau"), {debugName = "Requests"})()
local requestsModule, meleeModule, swordModule = {}, {}, {}
local MeleeRequests = luau.load(fs.readFile("src/shared/contracts/MeleeRequests.luau"), {
	debugName = "MeleeRequests", environment = {
		script = {Parent = {Requests = requestsModule}},
		require = function(module) assert(module == requestsModule); return Requests end,
	},
})()
local Service = luau.load(fs.readFile("src/server/application/combat/MeleeService.luau"), {
	debugName = "MeleeService", environment = {
		Vector3 = Vector3,
		script = {Parent = {Parent = {Parent = {domain = {combat = {SwordSwing = swordModule}}}}}},
		require = function(module) assert(module == swordModule); return SwordSwing end,
	},
})()
local replicated = {Shared = {contracts = {MeleeRequests = meleeModule}}}
local Gateway = luau.load(fs.readFile("src/server/adapters/networking/MeleeGateway.luau"), {
	debugName = "MeleeGateway", environment = {
		game = {GetService = function(_, name) assert(name == "ReplicatedStorage"); return replicated end},
		require = function(module) assert(module == meleeModule); return MeleeRequests end,
	},
})()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function cast(id, life, direction)
	return {action = "cast", requestId = id, life = life or 10, direction = direction or Vector3.xAxis}
end
local function fixture()
	local f: any = {now = 100, replies = {}, events = {}, origins = {}, faces = {}, targets = {}, damages = {},
		castCalls = 0, snapshotCalls = 0, disconnected = 0, players = {[1] = {UserId = 1}, [2] = {UserId = 2}}}
	f.core = Service.new({
		alive = function(owner) return owner == 1 or owner == 2 end,
		origin = function(owner) table.insert(f.origins, owner); return Vector3.new(0, 4, 0) end,
		face = function(owner, direction) table.insert(f.faces, {owner = owner, direction = direction}); return true end,
		targets = function(owner, direction, range, arc)
			table.insert(f.targets, {owner = owner, direction = direction, range = range, arc = arc})
			return f.victims or {"victim", "victim"}
		end,
		damage = function(owner, target, amount) table.insert(f.damages, {owner = owner, target = target, amount = amount}) end,
		emit = function(event) table.insert(f.events, event) end,
	}, Config)
	f.core.join(1, 10); f.core.join(2, 20)
	local wrapped = {
		cast = function(...) f.castCalls += 1; return f.core.cast(...) end,
		snapshot = function(owner) f.snapshotCalls += 1; return f.core.snapshot(owner) end,
	}
	local receive, connection
	local remote = {
		OnServerEvent = {Connect = function(_, callback)
			receive, connection = callback, {Connected = true}
			function connection:Disconnect() self.Connected = false; f.disconnected += 1 end
			return connection
		end},
		FireClient = function(_, player, payload) table.insert(f.replies, {player = player, payload = payload}) end,
	}
	f.gateway = Gateway.new(remote, wrapped, function() return f.now end)
	f.gateway.start()
	function f.send(owner, request)
		local previous = #f.replies
		if connection.Connected then receive(f.players[owner], request) end
		return if #f.replies > previous then f.replies[#f.replies].payload else nil
	end
	function f.step(at) f.now = at; f.core.step(at) end
	return f
end

test("unchanged schema accepts bounded IDs and unit aim, never a melee teleport", function()
	assert(MeleeRequests.valid(cast(0, 0)))
	assert(MeleeRequests.valid(cast(2147483647, 2147483647, Vector3.new(0.6, 0.8, 0))))
	assert(MeleeRequests.valid({action = "sync", requestId = 1, life = 0}))
	local teleport = {action = "teleport", requestId = 1, life = 10, castId = 7}
	assert(Requests.valid(teleport) and not MeleeRequests.valid(teleport))
end)
test("malformed, non-finite, non-unit and forged requests never enter the service", function()
	local invalid = {
		false, 7, "cast", {}, Vector3.zero,
		{action = "cast", requestId = 1, life = 10},
		cast(1, 10, {X = 1, Y = 0, Z = 0}),
		cast(1, 10, Vector3.zero), cast(1, 10, Vector3.new(2, 0, 0)),
		cast(1, 10, Vector3.new(0.5, 0, 0)), cast(1, 10, Vector3.new(0/0, 0, 0)),
		cast(1, 10, Vector3.new(0, math.huge, 0)), cast(1, 10, Vector3.new(0, 0, -math.huge)),
		cast(0/0), cast(math.huge), cast(-1), cast(1.5), cast(2147483648),
		cast(1, 0/0), cast(1, math.huge), cast(1, -1), cast(1, "10"),
		{action = "cast", requestId = 1, life = 10, direction = Vector3.xAxis, owner = 2},
		{action = "cast", requestId = 1, life = 10, direction = Vector3.xAxis, damage = 999},
		{action = "cast", requestId = 1, life = 10, direction = Vector3.xAxis, castId = 1},
		{action = "sync", requestId = 1, life = 10, direction = Vector3.xAxis},
		{action = "teleport", requestId = 1, life = 10, castId = 7},
	}
	for _, request in invalid do
		assert(not MeleeRequests.valid(request), "Melee schema accepted malformed request")
		local f = fixture()
		assert(f.send(1, request) == nil)
		assert(f.castCalls == 0 and f.snapshotCalls == 0 and #f.origins == 0 and #f.faces == 0
			and #f.events == 0 and #f.damages == 0, "Invalid payload reached gameplay")
	end
	local f = fixture()
	assert(f.send(1, nil) == nil and f.castCalls == 0 and f.snapshotCalls == 0)
end)
test("network cast -> normalized server-facing aim -> one twenty-damage hit after windup", function()
	local f = fixture()
	local reply = f.send(1, cast(77, 10, Vector3.new(0.6, 0.8, 0) * 1.005))
	assert(reply.ok and reply.kind == "reply" and reply.requestId == 77 and reply.life == 10)
	assert(reply.state.life == 10 and f.replies[1].player == f.players[1])
	assert(#f.faces == 1 and f.faces[1].owner == 1 and f.faces[1].direction == Vector3.xAxis)
	local preparing = f.events[1]
	assert(preparing.kind == "preparing" and preparing.owner == 1 and preparing.life == 10)
	assert(preparing.direction == Vector3.xAxis and preparing.hitAt == 100 + Config.windup)
	assert(reply.state.active[1].swingId == preparing.swingId and #f.damages == 0)
	f.step(preparing.hitAt - 0.001); assert(#f.damages == 0)
	f.step(preparing.hitAt); f.step(preparing.hitAt + 0.1)
	assert(#f.damages == 1 and f.damages[1].owner == 1 and f.damages[1].target == "victim" and f.damages[1].amount == 20)
	assert(#f.targets == 1 and f.targets[1].range == 7 and f.targets[1].arc == 100)
	assert(f.events[2].kind == "struck" and f.events[2].swingId == preparing.swingId)
end)
test("one accepted swing damages each distinct target once", function()
	local f = fixture()
	f.victims = {"first", "first", "second", "second"}
	assert(f.send(1, cast(1)).ok)
	f.step(100 + Config.windup); f.step(100 + Config.windup + 0.1)
	assert(#f.damages == 2 and f.damages[1].target == "first" and f.damages[2].target == "second")
	assert(f.damages[1].amount == 20 and f.damages[2].amount == 20)
end)
test("stale life is correlated and rejected before origin, facing or damage", function()
	local f = fixture()
	local reply = f.send(1, cast(15, 20))
	assert(not reply.ok and reply.reason == "stale_life" and reply.requestId == 15 and reply.life == 20)
	assert(reply.state.life == 10 and #reply.state.active == 0 and #f.events == 0 and #f.origins == 0 and #f.faces == 0)
	assert(f.send(1, cast(16)).ok and #f.events == 1)
end)
test("deduplication is per owner and never repeats accepted swings", function()
	local f = fixture()
	assert(f.send(1, cast(7)).ok)
	assert(f.send(1, cast(7)) == nil and f.send(1, cast(6)) == nil)
	assert(f.castCalls == 1 and #f.events == 1 and #f.replies == 1)
	local reply = f.send(1, cast(8))
	assert(not reply.ok and reply.reason == "busy" and reply.requestId == 8)
	assert(f.send(2, cast(7, 20)).ok and f.events[2].owner == 2)
	assert(#f.core.snapshot(2).active == 2)
end)
test("forged high request ID cannot suppress a later valid lower ID", function()
	local f = fixture()
	assert(f.send(1, {action = "cast", requestId = 99999, life = 10, direction = Vector3.xAxis, owner = 2}) == nil)
	assert(f.send(1, cast(1)).ok and f.castCalls == 1)
end)
test("twelve-token burst, eight-per-second refill, forget and destroy preserve endpoint lifecycle", function()
	local f = fixture()
	for id = 1, 100 do f.send(1, {action = "sync", requestId = id, life = 10}) end
	assert(#f.replies == 12 and f.snapshotCalls == 12 and f.castCalls == 0)
	f.now = 101
	for id = 101, 200 do f.send(1, {action = "sync", requestId = id, life = 10}) end
	assert(#f.replies == 20 and f.snapshotCalls == 20 and f.castCalls == 0)
	assert(f.send(2, {action = "sync", requestId = 1, life = 20}).state.life == 20)
	f.gateway.forget(1)
	assert(f.send(1, cast(1)).ok and f.castCalls == 1)
	f.gateway.destroy(); f.gateway.destroy()
	assert(f.disconnected == 1 and f.send(1, cast(2)) == nil)
end)
test("requested and server sync return actual snapshot protocol without fabricated reply IDs", function()
	local f = fixture()
	assert(f.send(1, cast(1)).ok)
	local message = f.send(2, {action = "sync", requestId = 25, life = 0})
	assert(message.kind == "snapshot" and message.requestId == nil and message.state.life == 20)
	assert(#message.state.active == 1 and message.state.active[1].owner == 1 and message.state.active[1].kind == "preparing")
	f.gateway.sync(f.players[1])
	local last = f.replies[#f.replies]
	assert(last.player == f.players[1] and last.payload.kind == "snapshot" and last.payload.state.life == 10)
	assert(f.castCalls == 1 and #f.events == 1)
end)
print("Melee gateway/schema contracts:", total, "passed (unchanged production source and real service; simulated Roblox boundary)")
