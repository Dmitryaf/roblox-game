--!strict
local Vector3 = require("@lune/roblox").Vector3
local Arrow = require("../../build/test-source/server/application/combat/ArrowService")
local Hands = require("../../build/test-source/server/application/combat/HandsService")
local Combat = require("../../build/test-source/server/application/combat/WarlockCombat")
local ArrowConfig = require("../../build/test-source/server/config/Warlock")
local HandsConfig = require("../../build/test-source/server/config/Hands")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
    local f: any = { slow = 1, moves = 0 }
    local arrow = Arrow.new({ origin = function() return Vector3.zero end, alive = function() return true end,
        sweep = function() return nil, nil end, damage = function() end,
        landing = function(_, position) return position end, move = function() f.moves += 1 end, emit = function() end }, ArrowConfig)
    local hands = Hands.new({ alive = function() return true end, placement = function(_, position) return position end,
        targets = function() return { "enemy" } end, damage = function() end,
        slow = function(_, multiplier) f.slow = multiplier end, emit = function() end }, HandsConfig)
    f.combat = Combat.new(arrow, hands); f.combat.join(1, 10); f.combat.join(2, 20)
    return f
end
test("hands preparation blocks arrow without spending its cooldown", function()
    local f = fixture(); local c = f.combat
    assert(c.castHands(1, 10, Vector3.zero, 0))
    local ok, reason = c.cast(1, 10, Vector3.xAxis, 0.1)
    assert(not ok and reason == "busy" and c.snapshot(1).readyAt == 0)
    c.step(0.8)
    assert(c.cast(1, 10, Vector3.xAxis, 0.9), "Active hands must not lock normal arrow use")
end)
test("arrow preparation blocks hands, flying arrow retains one teleport", function()
    local f = fixture(); local c = f.combat
    assert(c.cast(1, 10, Vector3.xAxis, 0))
    local ok, reason = c.castHands(1, 10, Vector3.zero, 0.1)
    assert(not ok and reason == "busy" and c.handsSnapshot(1).readyAt == 0)
    c.step(0.7)
    assert(c.castHands(1, 10, Vector3.zero, 0.8))
    local id = c.snapshot(1).active[1].castId
    assert(c.teleport(1, 10, id, 0.9) and f.moves == 1)
    assert(not c.teleport(1, 10, id, 0.91))
    assert(#c.handsSnapshot(1).active == 1, "Ordinary teleport incorrectly consumed hands")
end)
test("shared pause, death and new life clear both ability contexts", function()
    local f = fixture(); local c = f.combat
    assert(c.castHands(1, 10, Vector3.zero, 0)); c.step(0.8)
    assert(f.slow == 0.65 and c.cast(1, 10, Vector3.xAxis, 0.9))
    c.pause(1, 1)
    assert(f.slow == 1 and #c.snapshot(1).active == 0 and #c.handsSnapshot(1).active == 0)
    assert(c.snapshot(1).suspended and c.handsSnapshot(1).suspended)
    c.resume(1, 2); c.die(1)
    assert(not c.snapshot(1).alive and not c.handsSnapshot(1).alive)
    c.join(1, 11)
    assert(c.snapshot(1).readyAt == 0 and c.handsSnapshot(1).readyAt == 0)
    assert(not c.castHands(1, 10, Vector3.zero, 2))
    assert(c.castHands(1, 11, Vector3.zero, 2))
    c.destroy(); c.destroy(); assert(f.slow == 1)
end)
test("production runtime resolves combat deaths before objective sampling", function()
    local fs = require("@lune/fs")
    local luau = require("@lune/luau")
    local function signal() return { Connect = function() return { Disconnect = function() end } end } end
    local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
    local run = { Heartbeat = signal() }
    local runtimeModule = luau.load(fs.readFile("src/server/adapters/runtime/MatchRuntime.luau"), { environment = {
        game = { GetService = function(_, name) return if name == "Players" then players else run end },
    } })()
    local alive = true
    local trace = {}
    local runtime = runtimeModule.new({ step = function() alive = false; table.insert(trace, "combat") end,
        destroy = function() end }, { step = function() table.insert(trace, "world") end,
        onZone = function() return if alive then { [1] = true } else {} end }, {}, function() return 1 end, 5)
    local gateway = { start = function() end, destroy = function() end }
    runtime.start({ step = function(_, occupants)
        assert(next(occupants) == nil, "Dead zone occupant contributed before damage resolved")
        table.insert(trace, "objective")
    end, destroy = function() end }, gateway, gateway)
    runtime.tick()
    assert(table.concat(trace, ",") == "world,combat,objective")
    runtime.destroy()
end)
print(tostring(total) .. " combined combat/runtime contracts passed")
