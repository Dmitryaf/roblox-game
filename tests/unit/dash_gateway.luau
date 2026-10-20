--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3
local Config = luau.load(fs.readFile("src/server/config/Dash.luau"))()
local Requests = luau.load(fs.readFile("src/shared/contracts/Requests.luau"))()
local requestsModule, dashModule = {}, {}
local DashRequests = luau.load(fs.readFile("src/shared/contracts/DashRequests.luau"), { environment = {
    script = {Parent = {Requests = requestsModule}},
    require = function(module) assert(module == requestsModule); return Requests end,
} })()
local Service = luau.load(fs.readFile("src/server/application/combat/DashService.luau"), {
    environment = {Vector3 = Vector3},
})()
local Gateway = luau.load(fs.readFile("src/server/adapters/networking/DashGateway.luau"), { environment = {
    game = {GetService = function(_, name)
        assert(name == "ReplicatedStorage"); return {Shared = {contracts = {DashRequests = dashModule}}}
    end},
    require = function(module) assert(module == dashModule); return DashRequests end,
} })()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function cast(id, life, direction)
    return {action = "cast", requestId = id, life = life or 10, direction = direction or Vector3.xAxis}
end
local function fixture()
    local f = {now = 100, replies = {}, events = {}, starts = {}, stops = {}, castCalls = 0, snapshotCalls = 0,
        disconnected = 0, players = {[1] = {UserId = 1}, [2] = {UserId = 2}}}
    f.core = Service.new({
        alive = function(owner) return owner == 1 or owner == 2 end,
        start = function(owner, direction, distance, duration)
            table.insert(f.starts, {owner = owner, direction = direction, distance = distance, duration = duration})
            if f.blocked then return nil, nil, "blocked" end
            return Vector3.new(owner * 20, 3, 0), distance, nil
        end,
        stop = function(owner, reason) table.insert(f.stops, {owner = owner, reason = reason}) end,
        emit = function(event) table.insert(f.events, event) end,
    }, Config)
    f.core.join(1, 10); f.core.join(2, 20)
    local receive, connection
    local remote = {
        OnServerEvent = {Connect = function(_, callback)
            receive, connection = callback, {Connected = true}
            function connection:Disconnect() self.Connected = false; f.disconnected += 1 end
            return connection
        end},
        FireClient = function(_, player, payload) table.insert(f.replies, {player = player, payload = payload}) end,
    }
    f.gateway = Gateway.new(remote, {
        cast = function(...) f.castCalls += 1; return f.core.cast(...) end,
        snapshot = function(owner) f.snapshotCalls += 1; return f.core.snapshot(owner) end,
    }, function() return f.now end)
    f.gateway.start()
    function f.send(owner, request)
        local before = #f.replies
        if connection.Connected then receive(f.players[owner], request) end
        return if #f.replies > before then f.replies[#f.replies].payload else nil
    end
    return f
end

test("unchanged schema accepts bounded IDs and unit aim, never a dash teleport", function()
	assert(DashRequests.valid(cast(0, 0)))
	assert(DashRequests.valid(cast(2147483647, 2147483647, Vector3.new(0.6, 0.8, 0))))
	assert(DashRequests.valid({action = "sync", requestId = 1, life = 0}))
	local teleport = {action = "teleport", requestId = 1, life = 10, castId = 7}
	assert(Requests.valid(teleport) and not DashRequests.valid(teleport))
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
		assert(not DashRequests.valid(request), "Dash schema accepted malformed request")
		local f = fixture()
		assert(f.send(1, request) == nil)
		assert(f.castCalls == 0 and f.snapshotCalls == 0 and #f.starts == 0 and #f.events == 0, "Invalid payload reached gameplay")
	end
	local f = fixture()
	assert(f.send(1, nil) == nil and f.castCalls == 0 and f.snapshotCalls == 0)
end)
test("real network cast derives owner from Player and normalizes the accepted flat direction", function()
    local f = fixture()
    local reply = f.send(1, cast(77, 10, Vector3.new(0.6, 0.8, 0) * 1.005))
    assert(reply.ok and reply.kind == "reply" and reply.requestId == 77 and reply.life == 10)
    assert(reply.state.life == 10 and f.replies[1].player == f.players[1])
    local started = f.events[1]
    assert(started.kind == "started" and started.owner == 1 and started.life == 10)
    assert(started.direction == Vector3.xAxis and f.starts[1].direction == Vector3.xAxis and f.starts[1].owner == 1)
    assert(started.distance == 16 and started.expiresAt == 100.28 and reply.state.readyAt == 105)
    assert(reply.state.active[1].dashId == started.dashId)
    f.core.step(started.expiresAt); f.core.step(101)
    assert(#f.stops == 1 and f.stops[1].owner == 1 and #f.events == 2 and f.events[2].kind == "ended")
end)
test("stale life and geometry rejection return correlated replies without spending cooldown", function()
    local f = fixture(); local reply = f.send(1, cast(15, 20))
    assert(not reply.ok and reply.reason == "stale_life" and reply.requestId == 15 and reply.life == 20)
    assert(reply.state.life == 10 and reply.state.readyAt == 0 and #f.starts == 0 and #f.events == 0)
    f.blocked = true; reply = f.send(1, cast(16))
    assert(not reply.ok and reply.reason == "blocked" and reply.requestId == 16 and reply.state.readyAt == 0)
    f.blocked = false; assert(f.send(1, cast(17)).ok)
end)
test("deduplication is per owner and never repeats accepted physical movement", function()
    local f = fixture(); assert(f.send(1, cast(7)).ok)
    assert(f.send(1, cast(7)) == nil and f.send(1, cast(6)) == nil)
    assert(f.castCalls == 1 and #f.starts == 1 and #f.replies == 1)
    local reply = f.send(1, cast(8))
    assert(not reply.ok and reply.reason == "busy" and reply.requestId == 8 and #f.starts == 1)
    assert(f.send(2, cast(7, 20)).ok and f.events[2].owner == 2 and #f.core.snapshot(2).active == 2)
end)
test("forged owner or parameters cannot reserve a high request ID or movement", function()
    local f = fixture()
    assert(f.send(1, {action = "cast", requestId = 99999, life = 10, direction = Vector3.xAxis, owner = 2}) == nil)
    assert(f.send(1, {action = "cast", requestId = 99999, life = 10, direction = Vector3.xAxis, distance = 999}) == nil)
    assert(f.send(1, cast(1)).ok and f.castCalls == 1 and #f.starts == 1)
end)
test("twelve-token burst, eight-per-second refill, forget and destroy preserve endpoint lifecycle", function()
    local f = fixture()
    for id = 1, 100 do f.send(1, {action = "sync", requestId = id, life = 10}) end
    assert(#f.replies == 12 and f.snapshotCalls == 12 and f.castCalls == 0)
    f.now = 101
    for id = 101, 200 do f.send(1, {action = "sync", requestId = id, life = 10}) end
    assert(#f.replies == 20 and f.snapshotCalls == 20 and f.castCalls == 0)
    assert(f.send(2, {action = "sync", requestId = 1, life = 20}).state.life == 20)
    f.gateway.forget(1); assert(f.send(1, cast(1)).ok and f.castCalls == 1)
    f.gateway.destroy(); f.gateway.destroy()
    assert(f.disconnected == 1 and f.send(1, cast(2)) == nil)
end)
test("requested and server sync expose active remote dashes and actual personal state", function()
    local f = fixture(); assert(f.send(1, cast(1)).ok)
    local message = f.send(2, {action = "sync", requestId = 25, life = 0})
    assert(message.kind == "snapshot" and message.requestId == nil and message.state.life == 20)
    assert(#message.state.active == 1 and message.state.active[1].owner == 1 and message.state.active[1].kind == "started")
    f.gateway.sync(f.players[1]); local last = f.replies[#f.replies]
    assert(last.player == f.players[1] and last.payload.kind == "snapshot" and last.payload.state.life == 10)
    assert(f.castCalls == 1 and #f.events == 1)
end)
print(string.format("%d DashGateway/schema real-service contracts passed", total))
