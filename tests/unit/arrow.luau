--!strict
local Vector3 = require("@lune/roblox").Vector3
local Service = require("../../build/test-source/server/application/combat/ArrowService")
local Config = require("../../build/test-source/server/config/Warlock")
local Requests = require("../../build/test-source/shared/contracts/Requests")
local Gateway = require("../../build/test-source/server/adapters/networking/ArrowGateway")
local total = 0
local function test(name, run)
	run()
	total += 1
	print("PASS", name)
end
local function fixture()
	local f = { events = {}, moves = {}, damages = {}, living = { [1] = true, [2] = true },
		blocked = false, collision = false, now = 0, origins = 0 }
	f.service = Service.new({
		origin = function() f.origins += 1; return Vector3.new(0, 4, 0) end,
		alive = function(owner) return f.living[owner] == true end,
		sweep = function(_, p, delta)
			f.segment = delta
			if f.collision then return p + delta / 2, "target" end
			return nil, nil
		end,
		damage = function(owner, target, amount) table.insert(f.damages, {owner, target, amount}) end,
		landing = function(_, p) return if f.blocked then nil else p end,
		move = function(owner, p) table.insert(f.moves, { owner, p }) end,
		emit = function(e) table.insert(f.events, e) end,
	}, Config)
	f.service.join(1, 10)
	f.service.join(2, 20)
	function f.cast(owner)
		owner = owner or 1
		assert(f.service.cast(owner, if owner == 1 then 10 else 20, Vector3.new(1, 0, 0), f.now))
		return f.events[#f.events].castId
	end
	return f
end

test("prepare -> launch -> one teleport at authoritative position", function()
	local f = fixture(); local id = f.cast()
	assert(f.events[1].direction == Vector3.xAxis, "Preparation must expose the accepted aim to observers")
	assert(not f.service.teleport(1, 10, id, 0.1))
	assert(f.service.teleport(1, 10, id, Config.windup + 0.5))
	assert(#f.moves == 1 and math.abs(f.moves[1][2].X - 29) < 0.001)
	assert(not f.service.teleport(1, 10, id, Config.windup + 0.51))
	assert(#f.moves == 1 and #f.damages == 0)
end)
test("approved 0.7s windup and snapshots share authoritative start", function()
	local f = fixture(); f.now = 10; local id = f.cast()
	assert(Config.windup == 0.7)
	assert(f.events[1].startedAt == 10 and f.events[1].launchAt == 10.7)
	local snapshot = f.service.snapshot(1).active[1]
	assert(snapshot.startedAt == 10 and snapshot.launchAt == 10.7 and snapshot.kind == "preparing")
	for _, at in { 10.32, 10.699 } do
		local ok, reason = f.service.teleport(1, 10, id, at)
		assert(not ok and reason == "preparing" and #f.events == 1 and #f.moves == 0)
	end
	assert(f.service.teleport(1, 10, id, 10.7))
	assert(f.events[2].kind == "launched" and #f.moves == 1 and f.moves[1][2].X == 0)
end)
test("another owner and previous life cannot consume arrow", function()
	local f = fixture(); local id = f.cast()
	assert(not f.service.teleport(2, 20, id, 0.8))
	assert(not f.service.teleport(1, 9, id, 0.8))
	assert(f.service.teleport(1, 10, id, 0.8))
end)
test("expiry blocks movement including exact boundary", function()
	local f = fixture(); local id = f.cast()
	assert(not f.service.teleport(1, 10, id, Config.windup + Config.lifetime))
	assert(#f.moves == 0 and #f.service.snapshot(1).active == 0)
end)
test("hit is resolved before teleport request and damages once", function()
	local f = fixture(); local id = f.cast(); f.collision = true
	assert(not f.service.teleport(1, 10, id, 0.8))
	f.service.step(1); f.service.step(2)
	assert(#f.damages == 1 and f.damages[1][3] == 25 and #f.moves == 0)
end)
test("long frame sweeps full path only through expiry", function()
	local f = fixture(); f.cast(); f.service.step(100)
	assert(math.abs(f.segment.Magnitude - Config.speed * Config.lifetime) < 0.01)
	assert(#f.service.snapshot(1).active == 0)
end)
test("blocked landing preserves one use for a later safe request", function()
	local f = fixture(); local id = f.cast(); f.blocked = true
	local ok, reason = f.service.teleport(1, 10, id, 0.8)
	assert(not ok and reason == "blocked" and #f.moves == 0)
	f.blocked = false
	assert(f.service.teleport(1, 10, id, 0.9) and #f.moves == 1)
end)
test("death during windup prevents launch and damage", function()
	local f = fixture(); f.cast(); f.living[1] = false; f.service.step(1)
	assert(#f.service.snapshot(1).active == 0 and #f.damages == 0)
	for _, e in f.events do assert(e.kind ~= "launched") end
end)
test("death in flight cancels; respawn resets cooldown and rejects old life", function()
	local f = fixture(); local id = f.cast(); f.service.step(0.7); f.service.die(1)
	assert(not f.service.teleport(1, 10, id, 0.8))
	f.service.join(1, 11)
	assert(not f.service.cast(1, 10, Vector3.xAxis, 0.9))
	assert(f.service.cast(1, 11, Vector3.xAxis, 0.9))
end)
test("leave and repeated destroy remove active objects", function()
	local f = fixture(); f.cast(); f.cast(2); f.service.leave(1)
	assert(#f.service.snapshot(2).active == 1)
	f.service.destroy(); f.service.destroy()
	assert(#f.service.snapshot(2).active == 0)
end)
test("cooldown survives consumed arrow", function()
	local f = fixture(); local id = f.cast(); assert(f.service.teleport(1, 10, id, 0.8))
	local ok, reason = f.service.cast(1, 10, Vector3.xAxis, 1)
	assert(not ok and reason == "cooldown")
	assert(f.service.cast(1, 10, Vector3.xAxis, Config.cooldown))
end)
test("schema rejects NaN, infinity, oversized and forged payloads", function()
	assert(Requests.valid({ action = "cast", requestId = 1, life = 10, direction = Vector3.xAxis }))
	for _, request in {
		{ action = "cast", requestId = 1, life = 10, direction = Vector3.new(0/0, 0, 0) },
		{ action = "cast", requestId = 1, life = 10, direction = Vector3.new(math.huge, 0, 0) },
		{ action = "cast", requestId = 1, life = 10, direction = Vector3.zero },
		{ action = "teleport", requestId = 1, life = 10, castId = 1, owner = 2 },
		{ action = "sync", requestId = math.huge, life = 0 },
		{ action = "teleport", requestId = 1, life = 10, castId = -1 },
		{ action = string.rep("x", 1000), requestId = 1, life = 10 },
	} do assert(not Requests.valid(request)) end
end)
test("network entry -> service -> world effect, dedup and rate limit", function()
	local f = fixture()
	local receive
	local replies = {}
	local disconnected = false
	local remote = { OnServerEvent = { Connect = function(_, callback)
		receive = callback; return { Disconnect = function() disconnected = true end }
	end }, FireClient = function(_, player, value) table.insert(replies, { player, value }) end }
	local g = Gateway.new(remote, f.service, function() return f.now end); g.start()
	local player = { UserId = 1 }
	receive(player, { action = "cast", requestId = 1, life = 10, direction = Vector3.xAxis })
	local id = f.events[1].castId
	receive(player, { action = "cast", requestId = 1, life = 10, direction = Vector3.xAxis })
	assert(#f.events == 1 and #replies == 1)
	f.now = 0.8
	local request = { action = "teleport", requestId = 2, life = 10, castId = id }
	receive(player, request); receive(player, request)
	assert(#f.moves == 1 and replies[#replies][2].ok)
	for n = 3, 200 do receive(player, { action = "sync", requestId = n, life = 10 }) end
	assert(#replies <= 14)
	f.now = 3
	receive(player, { action = "sync", requestId = 201, life = 10 })
	assert(replies[#replies][2].kind == "snapshot")
	g.destroy(); assert(disconnected)
end)
print(string.format("%d executable contract tests passed (world/network ports simulated; no Studio physics).", total))
