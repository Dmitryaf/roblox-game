--!strict
local Gateway = require("../../build/test-source/server/adapters/networking/MatchGateway")
local Service = require("../../build/test-source/server/application/match/MatchService")
local Config = require("../../build/test-source/server/config/Match")
local total = 0
local function test(name, run)
	run()
	total += 1
	print("PASS", name)
end
local function fixture()
	local f = { now = 0, replies = {}, resets = {}, live = {[1]=true,[2]=true}, ticks = 0, disconnected = false }
	f.service = Service.new({
		reset = function(owner, team, frozen) table.insert(f.resets, {owner=owner,team=team,frozen=frozen}) end,
		freeze = function() end,
	}, Config)
	f.service.join(1,0); f.service.join(2,0)
	local receive
	local remote = { OnServerEvent = { Connect = function(_, callback)
		receive = callback
		return { Disconnect = function() f.disconnected = true end }
	end }, FireClient = function(_, player, payload) table.insert(f.replies, {player=player,payload=payload}) end }
	f.gateway = Gateway.new(remote, f.service, function() return f.now end, function()
		f.ticks += 1
		f.service.step(f.now, {})
	end, function(owner) return f.live[owner] == true end)
	f.gateway.start()
	function f.send(owner, request)
		receive({UserId=owner}, request)
		return if #f.replies > 0 then f.replies[#f.replies].payload else nil
	end
	return f
end

test("real network entry -> ready -> roster -> exit mutates only authenticated owner", function()
	local f = fixture()
	local reply = f.send(1, {action="ready",requestId=1,matchId=0})
	assert(reply.kind == "reply" and reply.requestId == 1 and reply.ok and reply.state.ready)
	assert(reply.state.queuePosition == 1 and not f.service.snapshot(2,0).ready)
	f.send(2, {action="ready",requestId=1,matchId=0})
	f.now = 13
	reply = f.send(1, {action="sync",requestId=2,matchId=0})
	assert(reply.state.matchId == 1 and reply.state.mode == "match" and #f.resets == 2)
	reply = f.send(1, {action="exit",requestId=3,matchId=1})
	assert(reply.ok and reply.state.mode == "training" and reply.state.phase == "paused")
	assert(f.service.context(2).team == 2)
	assert(f.replies[#f.replies].player.UserId == 1)
end)
test("forged owner, unknown action and NaN are rejected before service tick or state mutation", function()
	local f = fixture()
	for _, request in {
		{action="ready",requestId=1,matchId=0,owner=2},
		{action="reset",requestId=2,matchId=0},
		{action="ready",requestId=0/0,matchId=0},
		{action="ready",requestId=3,matchId=0/0},
		{action="ready",requestId=math.huge,matchId=0},
	} do f.send(1,request) end
	assert(#f.replies == 0 and f.ticks == 0 and not f.service.snapshot(1,0).ready)
	assert(not f.service.snapshot(2,0).ready)
end)
test("stale match produces correlated rejection and cannot exit current roster", function()
	local f = fixture()
	f.send(1,{action="ready",requestId=1,matchId=0})
	f.send(2,{action="ready",requestId=1,matchId=0})
	f.now = 13
	local reply = f.send(1,{action="exit",requestId=2,matchId=0})
	assert(not reply.ok and reply.reason == "stale_match" and reply.requestId == 2)
	assert(reply.state.matchId == 1 and reply.state.phase == "active" and f.service.context(1).team == 1)
	assert(#f.resets == 2)
end)
test("duplicate and lower request IDs cannot repeat accepted state change", function()
	local f = fixture()
	f.send(1,{action="ready",requestId=3,matchId=0})
	f.send(1,{action="cancel",requestId=3,matchId=0})
	f.send(1,{action="cancel",requestId=2,matchId=0})
	assert(#f.replies == 1 and f.ticks == 1 and f.service.snapshot(1,0).ready)
	local reply = f.send(1,{action="cancel",requestId=4,matchId=0})
	assert(reply.ok and not reply.state.ready)
end)
test("burst limit bounds callbacks, refills with time and forget clears previous session IDs", function()
	local f = fixture()
	for id = 1, 100 do f.send(1,{action="sync",requestId=id,matchId=0}) end
	assert(#f.replies == 10 and f.ticks == 10)
	f.now = 1
	for id = 101, 120 do f.send(1,{action="sync",requestId=id,matchId=0}) end
	assert(#f.replies == 15 and f.ticks == 15)
	f.gateway.forget(1)
	local reply = f.send(1,{action="ready",requestId=1,matchId=0})
	assert(reply.ok and reply.requestId == 1 and f.service.snapshot(1,1).ready)
	f.gateway.destroy(); f.gateway.destroy()
	assert(f.disconnected)
end)
test("dead or unregistered body cannot ready, while cancellation and exit remain available", function()
	local f = fixture()
	f.live[1] = false
	local reply = f.send(1,{action="ready",requestId=1,matchId=0})
	assert(not reply.ok and reply.reason == "not_ready" and not reply.state.ready)
	f.live[2] = nil
	reply = f.send(2,{action="ready",requestId=1,matchId=0})
	assert(not reply.ok and reply.reason == "not_ready")
	f.live[1] = true
	f.send(1,{action="ready",requestId=2,matchId=0})
	f.live[1] = false
	reply = f.send(1,{action="cancel",requestId=3,matchId=0})
	assert(reply.ok and not reply.state.ready)
	reply = f.send(1,{action="exit",requestId=4,matchId=0})
	assert(reply.ok and reply.state.mode == "training")
end)
test("sync reply retains request correlation; unsolicited sync remains a snapshot", function()
	local f = fixture()
	local reply = f.send(1,{action="sync",requestId=71,matchId=0})
	assert(reply.kind == "reply" and reply.requestId == 71 and reply.ok and reply.state.mode == "training")
	f.gateway.sync({UserId=2})
	local message = f.replies[#f.replies]
	assert(message.player.UserId == 2 and message.payload.kind == "snapshot" and message.payload.requestId == nil)
end)
print("Match gateway contracts:", total, "passed")
