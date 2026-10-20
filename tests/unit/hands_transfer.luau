--!strict
local Vector3 = require("@lune/roblox").Vector3
local Arrow = require("../../build/test-source/server/application/combat/ArrowService")
local Hands = require("../../build/test-source/server/application/combat/HandsService")
local Combat = require("../../build/test-source/server/application/combat/WarlockCombat")
local ArrowConfig = require("../../build/test-source/server/config/Warlock")
local HandsConfig = require("../../build/test-source/server/config/Hands")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture()
    local f: any = { now = 0, living = { [1] = true, [2] = true }, events = {}, hits = {}, slows = {}, moves = {},
        damageResult = true, impactCalls = 0, blocked = nil, collision = false, memberships = {}, placements = {} }
    f.arrow = Arrow.new({
        alive = function(owner) return f.living[owner] == true end,
        origin = function() return Vector3.new(0, 3, 0) end,
        sweep = function(_, p, delta) return if f.collision then p + delta / 2 else nil, if f.collision then "victim" else nil end,
        damage = function(owner, target, amount)
            table.insert(f.hits, { ability = "arrow", owner = owner, target = target, amount = amount })
            if f.onArrowDamage then f.onArrowDamage() end
            return f.damageResult
        end,
        impact = function(target)
            f.impactCalls += 1; assert(target == "victim")
            return { targetModel = "victimModel", targetLife = 28 }
        end,
        landing = function(_, position) return position end,
        move = function(owner, position) table.insert(f.moves, { owner, position }) end,
        emit = function(e) table.insert(f.events, { ability = "arrow", event = e }); if f.onEmit then f.onEmit("arrow", e) end end,
    }, ArrowConfig)
    f.hands = Hands.new({
        alive = function(owner) return f.living[owner] == true end,
        placement = function(owner, position, range, radius)
            table.insert(f.placements, { owner, position, range, radius })
            if f.blocked then return nil, f.blocked end
            if position.Magnitude > range then return nil, "out_of_range" end
            return Vector3.new(position.X, 0.1, position.Z), nil
        end,
        targets = function(_, position) return f.memberships[if position.X < 1 then "old" else "new"] or {} end,
        damage = function(owner, target, amount) table.insert(f.hits, { ability = "hands", owner = owner, target = target, amount = amount, at = f.now }) end,
        slow = function(target, multiplier) f.slows[target] = multiplier end,
        emit = function(e) table.insert(f.events, { ability = "hands", event = e }); if f.onEmit then f.onEmit("hands", e) end end,
    }, HandsConfig)
    f.combat = Combat.new(f.arrow, f.hands); f.combat.join(1, 10); f.combat.join(2, 20)
    function f.step(now) f.now = now; f.combat.step(now) end
    function f.start(arrowAt)
        assert(f.combat.castHands(1, 10, Vector3.zero, 0)); f.step(0.8)
        assert(f.combat.cast(1, 10, Vector3.xAxis, arrowAt or 0.9, 57))
        return f.arrow.snapshot(1).active[1].castId
    end
    function f.transfer(id, at) f.now = at or 1.8; return f.combat.transferHands(1, 10, id, f.now) end
    function f.area() return f.hands.snapshot(1).active[1] end
    function f.damage(ability, target)
        local sum = 0
        for _, hit in f.hits do if hit.ability == ability and (not target or hit.target == target) then sum += hit.amount end end
        return sum
    end
    return f
end
test("F combination consumes one own flying arrow and moves the same area with unchanged TTL and cooldown", function()
    local f = fixture(); local id = f.start(); local before = f.area()
    assert(f.transfer(id)); local after = f.area()
    assert(after.areaId == before.areaId and after.owner == 1 and after.life == 10 and after.kind == "transferring")
    assert(after.startedAt == before.startedAt and after.expiresAt == before.expiresAt and after.readyAt == before.readyAt)
    assert(after.fromPosition == before.position and after.position.X > 11 and after.position.X < 12)
    near(after.transferStartedAt, 1.8); near(after.transferReadyAt, 2.15); near(after.launchAt, 2.15)
    assert(#f.hands.snapshot(1).active == 1 and #f.arrow.snapshot(1).active == 0 and #f.moves == 0)
    assert(f.arrow.snapshot(1).readyAt == 4.4)
    local arrowEnd = f.events[#f.events].event
    assert(arrowEnd.reason == "hands_transferred" and arrowEnd.castId == id and arrowEnd.requestId == 57)
end)
test("warning removes old slow immediately and has no new slow or DoT until activation with no tick burst", function()
    local f = fixture(); f.memberships = { old = { "oldVictim" }, new = { "newVictim" } }
    local id = f.start(); assert(f.slows.oldVictim == 0.65)
    f.step(1.3); assert(f.damage("hands", "oldVictim") == 3)
    assert(f.transfer(id)); local transferredDamage = f.damage("hands")
    assert(f.slows.oldVictim == 1 and f.slows.newVictim == nil)
    f.step(2.149); assert(f.area().kind == "transferring" and f.damage("hands") == transferredDamage)
    f.step(2.15); assert(f.area().kind == "active" and f.slows.newVictim == 0.65)
    f.step(2.649); assert(f.damage("hands") == transferredDamage)
    f.step(2.65); assert(f.damage("hands", "newVictim") == 3)
    f.step(2.65); f.step(2.651); assert(f.damage("hands", "newVictim") == 3)
    f.step(4.2); assert(f.damage("hands", "newVictim") == 6, "Stalled frame invented transfer history")
    f.step(4.8); assert(f.area() == nil and f.slows.newVictim == 1 and f.damage("hands") <= 24)
end)
test("transferred area expires at its original deadline even if the warning leaves no full damage interval", function()
    local f = fixture(); local id = f.start(3.6); local original = f.area().expiresAt
    assert(f.transfer(id, 4.4)); near(f.area().expiresAt, original)
    f.memberships.new = { "victim" }; f.step(4.75); assert(f.slows.victim == 0.65 and f.damage("hands") == 0)
    f.step(4.8); assert(f.area() == nil and f.slows.victim == 1 and f.damage("hands") == 0)
end)
test("foreign and stale life or cast id requests cannot consume either owner's resources", function()
    local f = fixture(); local id = f.start(); assert(f.arrow.cast(2, 20, Vector3.xAxis, 0.9))
    local own = f.area()
    local foreignId
    for _, e in f.arrow.snapshot(2).active do if e.owner == 2 then foreignId = e.castId end end
    for _, request in { { 1, 9, id }, { 1, 10, foreignId }, { 2, 20, id }, { 1, 10, id + 100 } } do
        assert(not f.combat.transferHands(request[1], request[2], request[3], 1.8))
    end
    assert(#f.arrow.snapshot(1).active == 2 and f.area().areaId == own.areaId and f.area().position == own.position)
    assert(f.transfer(id))
end)
test("preparing arrow or preparing hands cannot transfer and retains a later legal opportunity", function()
    local f = fixture(); local id = f.start()
    local ok, reason = f.transfer(id, 1); assert(not ok and reason == "preparing")
    assert(#f.arrow.snapshot(1).active == 1 and f.area().kind == "active")
    assert(f.transfer(id, 1.8))
    local g = fixture(); assert(g.arrow.cast(1, 10, Vector3.xAxis, 0)); g.arrow.step(0.7)
    assert(g.hands.cast(1, 10, Vector3.zero, 0.7))
    local castId = g.arrow.snapshot(1).active[1].castId
    ok, reason = g.transfer(castId, 0.8); assert(not ok and reason == "busy")
    assert(#g.arrow.snapshot(1).active == 1 and g.area().kind == "preparing")
end)
test("ground wall bounds pad and owner range refusal preserve area arrow and both cooldowns", function()
    for _, reason in { "blocked", "no_ground", "protected", "out_of_bounds" } do
        local f = fixture(); local id = f.start(); local before = f.area(); f.blocked = reason
        local ok, actual = f.transfer(id); assert(not ok and actual == reason)
        assert(f.area().position == before.position and f.area().kind == "active" and f.area().expiresAt == before.expiresAt)
        assert(#f.arrow.snapshot(1).active == 1 and f.arrow.snapshot(1).readyAt == 4.4 and f.hands.snapshot(1).readyAt == 9)
        local placement = f.placements[#f.placements]; assert(placement[3] == 30 and placement[4] == 8)
        f.blocked = nil; assert(f.transfer(id, 1.81))
    end
    local f = fixture(); local id = f.start()
    local ok, reason = f.transfer(id, 2.2); assert(not ok and reason == "out_of_range")
    assert(#f.arrow.snapshot(1).active == 1 and f.area().position.X == 0)
end)
test("missing expired and nearly expired areas reject without spending the flying arrow", function()
    local f = fixture(); assert(f.arrow.cast(1, 10, Vector3.xAxis, 0))
    local id = f.arrow.snapshot(1).active[1].castId
    local ok, reason = f.transfer(id, 0.8); assert(not ok and reason == "no_area" and #f.arrow.snapshot(1).active == 1)
    for _, at in { 4.5, 4.8 } do
        local g = fixture(); local nextId = g.start(3.7)
        ok, reason = g.transfer(nextId, at)
        assert(not ok and reason == (if at == 4.5 then "expiring_area" else "expired"))
        assert(#g.arrow.snapshot(1).active == 1 and g.area().kind == "active")
    end
end)
test("repeat use and teleport after transfer are refused while ordinary E remains independent", function()
    local f = fixture(); local id = f.start(); assert(f.transfer(id)); local area = f.area()
    assert(not f.transfer(id, 1.81) and not f.combat.teleport(1, 10, id, 1.82))
    assert(f.area().areaId == area.areaId and #f.moves == 0)
    local g = fixture(); local nextId = g.start(); local before = g.area()
    assert(g.combat.teleport(1, 10, nextId, 1.8))
    assert(#g.moves == 1 and g.area().position == before.position and g.area().kind == "active")
    assert(not g.transfer(nextId, 1.81))
end)
test("flight sweep resolves actual collision and expiry before granting transfer", function()
    for _, reason in { "collision", "expired" } do
        local f = fixture(); local id = f.start(); f.collision = reason == "collision"
        assert(not f.transfer(id, if f.collision then 1.8 else f.arrow.snapshot(1).active[1].expiresAt))
        assert(#f.arrow.snapshot(1).active == 0 and f.area().position.X == 0)
        assert(f.damage("arrow") == (if f.collision then 25 else 0))
    end
end)
test("death pause leave and new life during warning clean both source state and all slow without reactivation", function()
    for _, reason in { "death", "pause", "leave", "life", "destroy" } do
        local f = fixture(); f.memberships.old = { "victim" }; local id = f.start(); assert(f.transfer(id))
        if reason == "death" then f.combat.die(1)
        elseif reason == "pause" then f.combat.pause(1, 1.9)
        elseif reason == "leave" then f.combat.leave(1)
        elseif reason == "life" then f.combat.join(1, 11)
        else f.combat.destroy() end
        f.memberships.new = { "victim" }; f.step(2.7)
        assert(f.area() == nil and f.slows.victim == 1 and f.damage("hands") == 0 and #f.arrow.snapshot(1).active == 0)
        assert(not f.combat.transferHands(1, 10, id, 2.7))
    end
end)
test("actual death and paused cast requests cannot start a transfer", function()
    for _, reason in { "dead", "paused" } do
        local f = fixture(); local id = f.start()
        if reason == "dead" then f.living[1] = false else f.combat.pause(1, 1.7) end
        assert(not f.transfer(id))
        if reason == "dead" then f.combat.step(1.8) end
        assert(f.area() == nil and #f.arrow.snapshot(1).active == 0)
    end
end)
test("overlap retains the other owner's slow while the transferred source is inactive and clears only its source", function()
    local f = fixture(); f.memberships.old = { "shared" }; local id = f.start()
    assert(f.hands.cast(2, 20, Vector3.zero, 0)); f.hands.step(0.8)
    assert(f.transfer(id)); assert(f.slows.shared == 0.65)
    f.combat.die(2); assert(f.slows.shared == 1)
    f.memberships.new = { "shared" }; f.step(2.15); assert(f.slows.shared == 0.65)
    f.combat.die(1); assert(f.slows.shared == 1)
end)
test("arrow is already unavailable during transfer notifications and cannot be re-used by re-entry", function()
    local f = fixture(); local id = f.start(); local checked = false
    f.onEmit = function(ability, e)
        if ability == "hands" and e.kind == "transferring" then
            checked = true; assert(#f.arrow.snapshot(1).active == 0)
            assert(not f.combat.teleport(1, 10, id, 1.8))
            assert(not f.combat.transferHands(1, 10, id, 1.8))
        end
    end
    assert(f.transfer(id) and checked and #f.moves == 0)
end)
test("confirmed arrow damage alone adds a reaction target with swept source time and preserves void ports", function()
    for _, result in { "true", "false", "void" } do
        local f = fixture(); assert(f.arrow.cast(1, 10, Vector3.xAxis, 0, 83)); f.collision = true
        f.damageResult = if result == "true" then true else if result == "false" then false else nil
        f.onArrowDamage = function() assert(#f.arrow.snapshot(1).active == 0); f.arrow.die(1) end
        f.arrow.step(0.9)
        local ended = f.events[#f.events].event
        assert(ended.kind == "ended" and ended.reason == "hit" and ended.requestId == 83)
        assert(ended.sourcePosition == Vector3.new(0, 3, 0)); near(ended.contactAt, 0.8)
        assert(f.damage("arrow") == 25 and #f.arrow.snapshot(1).active == 0)
        if result == "true" then
            assert(ended.damageApplied and ended.targetModel == "victimModel" and ended.targetLife == 28 and f.impactCalls == 1)
        else assert(not ended.damageApplied and ended.targetModel == nil and ended.targetLife == nil and f.impactCalls == 0) end
        f.arrow.step(1); assert(f.damage("arrow") == 25)
    end
end)
print(string.format("%d hands transfer/arrow impact contract tests passed (world ports simulated; not Studio)", total))
