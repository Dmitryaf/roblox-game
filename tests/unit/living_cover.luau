--!strict
local Vector3 = require("@lune/roblox").Vector3
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Service = require("../../build/test-source/server/application/combat/CoverService")
local Config = luau.load(fs.readFile("src/server/config/LivingCover.luau"), { environment = { Vector3 = Vector3 } })()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
    local f = { alive = { [1] = true, [2] = true }, clear = true, slot = 1, events = {}, models = {}, removed = {},
        resets = {}, targets = { 1 }, placement = nil, onClear = nil }
    f.service = Service.new({
        alive = function(owner) return f.alive[owner] == true end,
        choose = function() return if f.placement then nil else f.slot, f.placement end,
        position = function(slot) return Config.slots[slot] end,
        clearForRaise = function() if f.onClear then f.onClear() end; return f.clear end,
        show = function(area, phase) f.models[area.slotId] = { id = area.areaId, phase = phase } end,
        remove = function(area, reason) f.removed[area.areaId] = (f.removed[area.areaId] or 0) + 1; f.models[area.slotId] = nil end,
        reset = function(owner) table.insert(f.resets, owner) end,
        targetSlot = function(target)
            for slot, model in f.models do if model == target and model.phase == "active" then return slot end end
            return nil
        end,
        strikeTargets = function() return f.targets end,
        emit = function(event) table.insert(f.events, event) end,
    }, Config)
    f.service.join(1, 10); f.service.join(2, 20)
    function f.cast(owner, at)
        owner = owner or 1
        return f.service.cast(owner, if owner == 1 then 10 else 20, Vector3.zero, at or 0)
    end
    return f
end
test("warning reserves one of two sites and raises only after windup", function()
    assert(#Config.slots == 2 and Config.size.X < 20 and Config.range == 30)
    local f = fixture(); assert(f.cast())
    assert(f.models[1].phase == "preparing")
    local ok, reason = f.cast(2)
    assert(not ok and reason == "occupied")
    f.slot = 2; assert(f.cast(2))
    f.service.step(Config.windup - 0.001); assert(f.models[1].phase == "preparing")
    f.service.step(Config.windup)
    assert(f.models[1].phase == "active" and f.models[2].phase == "active")
    assert(#f.service.snapshot(1).active == 2)
end)
test("person entering warning cancels raise and keeps cooldown", function()
    local f = fixture(); assert(f.cast()); f.clear = false
    f.service.step(Config.windup)
    assert(f.models[1] == nil and #f.service.snapshot(1).active == 0)
    assert(f.events[#f.events].reason == "occupied")
    f.clear = true
    local ok, reason = f.cast(1, 1)
    assert(not ok and reason == "cooldown")
    assert(f.cast(1, Config.cooldown))
end)
test("occupied or remote initial aim does not spend cooldown", function()
    local f = fixture(); f.clear = false
    assert(not f.cast()); assert(f.service.snapshot(1).readyAt == 0)
    f.clear = true; f.placement = "out_of_range"
    local ok, reason = f.cast(); assert(not ok and reason == "out_of_range")
    assert(f.service.snapshot(1).readyAt == 0)
    f.placement = nil; assert(f.cast())
end)
test("arrow consumes raised state once; stale geometry cannot destroy its replacement", function()
    local f = fixture(); assert(f.cast()); f.service.step(Config.windup)
    local old = f.models[1]
    assert(f.service.hit(old, 1)); assert(not f.service.hit(old, 1))
    assert(f.removed[1] == 1 and f.events[#f.events].reason == "shattered")
    assert(f.cast(1, Config.cooldown)); f.service.step(Config.cooldown + Config.windup)
    assert(not f.service.hit(old, Config.cooldown + 1))
    assert(f.models[1] ~= nil)
end)
test("heavy strike destroys active cover only and deduplicates slots", function()
    local f = fixture(); assert(f.cast()); f.targets = { 1, 1 }
    assert(f.service.strike(2, Vector3.xAxis, 0.2) == 0)
    assert(f.service.strike(2, Vector3.xAxis, 1) == 1)
    assert(f.removed[1] == 1)
    assert(f.service.strike(2, Vector3.xAxis, 1) == 0)
end)
test("expiry does not flash a cover after a long stalled preparation", function()
    local f = fixture(); assert(f.cast())
    f.service.step(100)
    assert(f.models[1] == nil and f.events[#f.events].reason == "expired")
    for _, event in f.events do assert(event.kind ~= "active") end
end)
test("death reset leave and pause release sites and prevent old-life actions", function()
    for _, action in { "die", "leave", "pause", "join" } do
        local f = fixture(); assert(f.cast())
        if action == "join" then f.service.join(1, 11)
        elseif action == "pause" then f.service.pause(1, 0.1)
        else f.service[action](1) end
        f.service.step(1)
        assert(f.models[1] == nil)
        assert(not f.service.cast(1, 10, Vector3.zero, 1))
        assert(f.cast(2, 1))
        assert(f.removed[1] == 1)
    end
end)
test("resume preserves remaining cooldown and does not restore the slab", function()
    local f = fixture(); assert(f.cast()); f.service.pause(1, 2); f.service.resume(1, 12)
    assert(f.service.snapshot(1).readyAt == Config.cooldown + 10)
    assert(#f.service.snapshot(1).active == 0)
    assert(not f.cast(1, 18.9)); assert(f.cast(1, 19))
end)
test("reentrant life change during occupancy validation cannot install old reservation", function()
    local f = fixture(); local fired = false
    f.onClear = function() if not fired then fired = true; f.service.join(1, 11) end end
    assert(not f.cast()); assert(#f.service.snapshot(1).active == 0)
    f.onClear = nil; assert(f.cast(2))
end)
test("reentrant reset at raise and repeated teardown never resurrect cover", function()
    local f = fixture(); assert(f.cast())
    f.onClear = function() f.service.join(1, 11) end
    f.service.step(1)
    assert(f.models[1] == nil and #f.service.snapshot(1).active == 0)
    f.service.destroy(); f.service.destroy()
    assert(f.service.snapshot(1).life == 0)
end)
print("Living cover tests:", total)
