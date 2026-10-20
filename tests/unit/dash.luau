--!strict
local Vector3 = require("@lune/roblox").Vector3
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Config = luau.load(fs.readFile("src/server/config/Dash.luau"))()
-- Execute unchanged production text with only the Roblox value type injected.
local Service = luau.load(fs.readFile("src/server/application/combat/DashService.luau"), {
    debugName = "DashService", environment = { Vector3 = Vector3 },
})()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a-b) < 0.000001, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture()
    local f = { events = {}, starts = {}, stops = {}, living = { [1] = true, [2] = true },
        positions = { [1] = Vector3.new(0, 3, 0), [2] = Vector3.new(20, 3, 0) }, distance = Config.distance }
    f.service = Service.new({
        alive = function(owner) return f.living[owner] == true end,
        start = function(owner, direction, distance, duration)
            table.insert(f.starts, { owner = owner, direction = direction, distance = distance, duration = duration })
            if f.rejected then return nil, nil, f.rejected end
            return f.positions[owner], f.distance, nil
        end,
        stop = function(owner, reason)
            table.insert(f.stops, { owner = owner, reason = reason })
            if f.onStop then f.onStop(owner, reason) end
        end,
        emit = function(event) table.insert(f.events, event) end,
    }, Config)
    f.service.join(1, 10); f.service.join(2, 20)
    function f.cast(at, direction) return f.service.cast(1, 10, direction or Vector3.xAxis, at or 0) end
    function f.ended() local ends = {}; for _, event in f.events do if event.kind == "ended" then table.insert(ends, event) end end; return ends end
    return f
end

test("dash config and accepted event carry the authoritative distance, timing and life", function()
    assert(Config.distance == 16 and Config.duration == 0.28 and Config.cooldown == 5)
    local f = fixture(); assert(f.cast(100))
    local event = f.events[1]
    assert(event.kind == "started" and event.owner == 1 and event.life == 10 and event.dashId > 0)
    assert(event.position == Vector3.new(0, 3, 0) and event.direction == Vector3.xAxis)
    assert(f.starts[1].owner == 1 and f.starts[1].distance == 16 and f.starts[1].duration == 0.28)
    near(event.startedAt, 100); near(event.expiresAt, 100.28); near(event.readyAt, 105)
    near(event.distance, 16); near(event.duration, 0.28); near(event.speed, 16/0.28)
    local state = f.service.snapshot(1)
    assert(state.life == 10 and state.alive and not state.suspended and state.active[1].dashId == event.dashId)
    near(state.readyAt, 105); assert(#f.stops == 0)
end)
test("sloped movement direction is flattened before the authoritative world starts", function()
    local f = fixture(); assert(f.cast(0, Vector3.new(0.6, 0.8, 0)))
    assert(f.starts[1].direction == Vector3.xAxis and f.events[1].direction == Vector3.xAxis)
end)
test("zero, vertical and non-finite aim never start movement or spend cooldown", function()
    for _, direction in { Vector3.zero, Vector3.yAxis, -Vector3.yAxis,
        Vector3.new(0/0, 0, 0), Vector3.new(math.huge, 0, 0), Vector3.new(0, 0, -math.huge) } do
        local f = fixture(); local ok, reason = f.cast(0, direction)
        assert(not ok and reason == "invalid_aim" and #f.starts == 0 and #f.events == 0)
        assert(f.service.snapshot(1).readyAt == 0 and f.cast(0))
    end
end)
test("blocked, airborne and invalid world positions spend neither cooldown nor dash ID", function()
    for _, failure in { "blocked", "airborne", "invalid_position" } do
        local f = fixture(); f.rejected = failure
        local ok, reason = f.cast(1)
        assert(not ok and reason == failure and #f.events == 0 and #f.stops == 0)
        assert(f.service.snapshot(1).readyAt == 0 and #f.service.snapshot(1).active == 0)
        f.rejected = nil; assert(f.cast(1)); assert(f.events[1].dashId == 1)
    end
end)
test("geometry-clamped travel keeps speed and shortens the active duration", function()
    local f = fixture(); f.distance = 6; assert(f.cast(10))
    local event = f.events[1]
    near(event.distance, 6); near(event.duration, 0.28 * 6/16); near(event.speed, 16/0.28)
    f.service.step(event.expiresAt - 0.001); assert(#f.stops == 0)
    f.service.step(event.expiresAt); f.service.step(11)
    assert(#f.stops == 1 and f.stops[1].owner == 1 and f.stops[1].reason == "expired")
    assert(#f.ended() == 1 and f.ended()[1].dashId == event.dashId and #f.service.snapshot(1).active == 0)
    near(f.service.snapshot(1).readyAt, 15)
end)
test("active dash rejects repetition, expires once and does not bypass cooldown", function()
    local f = fixture(); assert(f.cast(0))
    local ok, reason = f.cast(0.1); assert(not ok and reason == "busy" and #f.starts == 1)
    f.service.step(0.28); f.service.step(0.28)
    assert(#f.stops == 1 and #f.ended() == 1)
    ok, reason = f.cast(4.999); assert(not ok and reason == "cooldown")
    assert(f.cast(5) and #f.starts == 2 and f.events[#f.events].dashId ~= f.events[1].dashId)
end)
test("snapshot is public active state with each requester's own life and cooldown", function()
    local f = fixture(); assert(f.cast(1)); assert(f.service.cast(2, 20, -Vector3.xAxis, 1))
    local one, two, stranger = f.service.snapshot(1), f.service.snapshot(2), f.service.snapshot(99)
    assert(one.life == 10 and two.life == 20 and stranger.life == 0 and not stranger.alive)
    assert(#one.active == 2 and #two.active == 2 and #stranger.active == 2)
    one.active[1].distance = 999
    for _, event in f.service.snapshot(1).active do assert(event.distance == Config.distance) end
end)
test("stale life, absent membership and dead characters cannot reach world start", function()
    local f = fixture()
    local ok, reason = f.service.cast(99, 10, Vector3.xAxis, 0); assert(not ok and reason == "not_ready")
    ok, reason = f.service.cast(1, 9, Vector3.xAxis, 0); assert(not ok and reason == "stale_life")
    f.living[1] = false; ok, reason = f.cast(0); assert(not ok and reason == "dead")
    assert(not f.service.snapshot(1).alive and #f.starts == 0 and #f.events == 0)
end)
test("death discovered by step cancels physical movement exactly once", function()
    local f = fixture(); assert(f.cast(0)); f.living[1] = false
    f.service.step(0.1); f.service.die(1); f.service.step(1)
    assert(#f.stops == 1 and #f.ended() == 1 and f.ended()[1].reason == "dead")
    assert(not f.service.snapshot(1).alive and #f.service.snapshot(1).active == 0)
end)
test("pause stops movement once and freezes only the remaining cooldown", function()
    local f = fixture(); assert(f.cast(0)); f.service.pause(1, 0.1); f.service.pause(1, 2)
    f.service.step(8); local ok, reason = f.cast(8)
    assert(not ok and reason == "paused" and #f.stops == 1 and f.ended()[1].reason == "paused")
    assert(f.service.snapshot(1).suspended and #f.service.snapshot(1).active == 0)
    f.service.resume(1, 10); f.service.resume(1, 12)
    near(f.service.snapshot(1).readyAt, 14.9)
    ok, reason = f.cast(14.899); assert(not ok and reason == "cooldown")
    assert(f.cast(14.9))
end)
test("new life, leave and destroy stop old movement and clear membership", function()
    local f = fixture(); assert(f.cast(0)); f.service.join(1, 11)
    assert(#f.stops == 1 and f.ended()[1].reason == "reset" and f.service.snapshot(1).readyAt == 0)
    local ok, reason = f.cast(0); assert(not ok and reason == "stale_life")
    assert(f.service.cast(1, 11, Vector3.xAxis, 0)); f.service.leave(1); f.service.leave(1)
    assert(#f.stops == 2 and f.ended()[2].reason == "left" and f.service.snapshot(1).life == 0)
    assert(f.service.cast(2, 20, Vector3.xAxis, 1)); f.service.destroy(); f.service.destroy(); f.service.step(5)
    assert(#f.stops == 3 and f.service.snapshot(2).life == 0 and #f.service.snapshot(2).active == 0)
end)
test("world stop reentrancy cannot end or release one dash twice", function()
    local f = fixture(); assert(f.cast(0)); f.onStop = function(owner) f.service.die(owner) end
    f.service.die(1); f.service.die(1)
    assert(#f.stops == 1 and #f.ended() == 1 and f.ended()[1].reason == "dead")
end)
print(string.format("%d DashService lifecycle/world-port tests passed", total))
