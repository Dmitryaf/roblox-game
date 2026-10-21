--!strict
local roblox, fs, luau = require("@lune/roblox"), require("@lune/fs"), require("@lune/luau")
local V = roblox.Vector3
local Service = require("../../build/test-source/server/application/combat/ArrowService")
local Sector = luau.load(fs.readFile("build/test-source/server/domain/combat/ArrowInterception.luau"), { environment = {Vector3 = V} })()
local Intercept = luau.load(fs.readFile("build/test-source/server/application/combat/ArrowInterceptService.luau"), {
    environment = {Vector3 = V, require = function() return Sector end},
})()
local config = {windup = 0.7, lifetime = 2, cooldown = 3, speed = 10, damage = 25, radius = 0.5}
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function close(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture()
    local f = {events = {}, damage = {}, moves = {}, allowed = true, wall = nil, target = nil,
        living = {[1] = true, [2] = true}, swings = {{owner = 2, life = 20, swingId = 1,
            direction = -V.xAxis, hitAt = 0.9}}, covers = 0}
    local intercept = Intercept.new({
        swings = function() return f.swings end, alive = function(id) return f.living[id] end,
        origin = function() return V.new(10, 1, 0) end, allowed = function() return f.allowed end,
        visible = function() return not f.hidden end,
    }, {window = 0.18, range = 7, arcDegrees = 100})
    f.service = Service.new({
        origin = function() return V.zero end, alive = function(id) return f.living[id] end,
        sweep = function(owner, p, delta)
            if f.wall and delta.X > 0 and p.X <= f.wall and p.X + delta.X >= f.wall then return V.new(f.wall, 0, 0), nil, "cover", f.hitDistance end
            if f.target and owner == 2 and delta.X < 0 and p.X + delta.X <= f.target then return V.new(f.target, 0, 0), "caster", nil end
            return nil, nil, nil
        end,
        intercept = intercept, coverHit = function() f.covers += 1; return true end,
        damage = function(owner, target) table.insert(f.damage, {owner, target}); return true end,
        landing = function(_, p) return if f.blocked then nil else p end,
        move = function(owner, p) table.insert(f.moves, {owner, p}) end,
        emit = function(e) table.insert(f.events, e) end,
    }, config)
    f.service.join(1, 10); f.service.join(2, 20)
    assert(f.service.cast(1, 10, V.xAxis, 0))
    f.id = f.events[1].castId
    function f.active() return f.service.snapshot(1).active[1] end
    function f.redirectCount() local count = 0; for _, e in f.events do if e.kind == "redirected" then count += 1 end end; return count end
    return f
end
test("swept contact preserves speed deadline and creator, changes damage owner", function()
    local f = fixture(); f.service.step(1.05)
    local a = f.active(); assert(a.redirected and a.owner == 1 and a.damageOwner == 2 and a.damageLife == 20)
    close(a.position.X, 2.5); close(a.speed, 10); close(a.expiresAt, 2.7)
    assert(f.redirectCount() == 1 and a.direction == -V.xAxis)
end)
test("only creator can teleport after redirect and it consumes without damage", function()
    local f = fixture(); f.service.step(1.05)
    assert(not f.service.teleport(2, 20, f.id, 1.06))
    assert(f.service.teleport(1, 10, f.id, 1.07))
    assert(not f.service.teleport(1, 10, f.id, 1.08))
    f.service.step(3); assert(#f.moves == 1 and #f.damage == 0 and not f.active())
end)
test("redirected arrow damages creator once with warrior ownership", function()
    local f = fixture(); f.target = 0; f.service.step(1.5); f.service.step(2)
    assert(#f.damage == 1 and f.damage[1][1] == 2 and f.damage[1][2] == "caster")
    assert(not f.service.teleport(1, 10, f.id, 1.5) and #f.moves == 0)
end)
test("late blade cannot intercept a segment already resolved", function()
    local f = fixture(); f.swings[1].hitAt = 1.8; f.service.step(1.7)
    assert(not f.active().redirected)
    f.service.step(2); assert(not f.active().redirected)
end)
test("blade behind arrow or aimed away cannot intercept", function()
    local f = fixture(); f.swings[1].direction = V.xAxis; f.service.step(1.2)
    assert(not f.active().redirected)
end)
test("teammates and disallowed contexts cannot redirect", function()
    local f = fixture(); f.allowed = false; f.service.step(1.05); assert(not f.active().redirected)
end)
test("wall before blade consumes arrow first, no damage behind cover", function()
    local f = fixture(); f.wall = 2; f.service.step(1.2)
    assert(not f.active() and f.redirectCount() == 0 and f.covers == 1 and #f.damage == 0)
end)
test("blade cannot reach through a wall even when arrow has not reached that wall", function()
    local f = fixture(); f.hidden = true; f.wall = 7; f.service.step(1.5)
    assert(f.redirectCount() == 0 and not f.active() and f.covers == 1)
end)
test("sphere contact distance wins even when surface point is beyond blade", function()
    local f = fixture(); f.wall = 3.5; f.hitDistance = 2.85; f.service.step(1.2)
    assert(f.redirectCount() == 0 and f.covers == 1 and not f.active())
end)
test("teleport before blade resolves once and prevents later intercept", function()
    local f = fixture(); assert(f.service.teleport(1, 10, f.id, 0.8)); f.service.step(1.2)
    assert(f.redirectCount() == 0 and #f.moves == 1 and #f.damage == 0)
end)
test("failed landing retains redirected arrow and original deadline", function()
    local f = fixture(); f.blocked = true; f.service.step(1.05)
    assert(not f.service.teleport(1, 10, f.id, 1.1)); assert(f.active().redirected)
    f.service.step(2.7); assert(not f.active() and #f.moves == 0)
end)
test("one redirect only even across another active blade", function()
    local f = fixture(); f.service.step(1.05); f.swings[1].hitAt = 1.05; f.service.step(1.1)
    assert(f.redirectCount() == 1)
end)
test("stale defender life cannot take damage ownership", function()
    local f = fixture(); f.swings[1].life = 19; f.service.step(1.05); assert(not f.active().redirected)
end)
test("defender death pause leave and new life cancel redirected arrows", function()
    for _, action in {"die", "pause", "leave", "join"} do
        local f = fixture(); f.service.step(1.05); assert(f.active().redirected)
        if action == "pause" then f.service.pause(2, 1.06)
        elseif action == "join" then f.service.join(2, 21)
        else f.service[action](2) end
        assert(not f.active()); assert(not f.service.teleport(1, 10, f.id, 1.1))
    end
end)
test("caster death and expired arrows cannot survive interception", function()
    local f = fixture(); f.service.step(1.05); f.service.die(1); assert(not f.active())
    f = fixture(); f.service.step(5); assert(not f.active()); assert(#f.damage == 0)
end)
test("sector rejects height, expired window and out of range", function()
    for _, point in {V.new(0, 8, 0), V.new(0, 0, 8)} do
        assert(not Sector.fraction(point, V.xAxis * 5, 0.7, 1.2, V.new(10, 0, 0), -V.xAxis, 0.9, 0.18, 7, 100))
    end
    assert(not Sector.fraction(V.zero, V.xAxis * 20, 2, 3, V.new(10, 0, 0), -V.xAxis, 0.9, 0.18, 7, 100))
end)
print(total, "interception contracts passed (simulated ports; no Studio physics)")
