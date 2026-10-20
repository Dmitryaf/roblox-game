--!strict
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Service = luau.load(fs.readFile("src/server/application/combat/TimedSlowService.luau"), {
    debugName = "TimedSlowService",
})()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
    local f = { living = {[1] = true, [2] = true, [3] = true}, targets = {}, events = {}, tokensRead = 0,
        heavy = {}, hands = {}, actual = {} }
    function f.target(name, owner)
        local target = {name = name, owner = owner, token = {life = 1}}
        f.targets[name] = target; return target
    end
    f.service = Service.new({
        alive = function(owner) return f.living[owner] == true end,
        token = function(target) f.tokensRead += 1; return target.token end,
        owner = function(target) return target.owner end,
        apply = function(target, amount)
            f.heavy[target] = amount
            f.actual[target] = math.min(amount, f.hands[target] or 1)
            table.insert(f.events, {target = target, amount = amount})
        end,
    })
    f.a, f.b = f.target("a", 3), f.target("b", nil)
    return f
end

test("one confirmed hit applies immediately and expires at the exact absolute deadline once", function()
    local f = fixture(); assert(f.service.hit(1, f.a, 0.6, 2, 10))
    assert(f.heavy[f.a] == 0.6 and #f.events == 1)
    f.service.step(11.999); assert(f.heavy[f.a] == 0.6 and #f.events == 1)
    f.service.step(12); f.service.step(12); f.service.step(100)
    assert(f.heavy[f.a] == 1 and #f.events == 2)
end)
test("overlapping casters use the strongest contribution without multiplication", function()
    local f = fixture()
    assert(f.service.hit(1, f.a, 0.7, 5, 0)); assert(f.service.hit(2, f.a, 0.5, 2, 0))
    assert(f.heavy[f.a] == 0.5 and #f.events == 2)
    f.service.step(2); assert(f.heavy[f.a] == 0.7 and #f.events == 3)
    f.service.step(5); assert(f.heavy[f.a] == 1 and #f.events == 4)
end)
test("clearing one caster preserves another contribution and unrelated targets", function()
    local f = fixture()
    f.service.hit(1, f.a, 0.5, 3, 0); f.service.hit(2, f.a, 0.7, 4, 0); f.service.hit(2, f.b, 0.6, 4, 0)
    assert(#f.events == 2)
    f.service.reset(1)
    assert(f.heavy[f.a] == 0.7 and f.heavy[f.b] == 0.6 and #f.events == 3)
    f.service.reset(1); assert(#f.events == 3)
    f.service.reset(2)
    assert(f.heavy[f.a] == 1 and f.heavy[f.b] == 1 and #f.events == 5)
end)
test("same-caster refresh keeps the stronger slow and uses exactly the new hit deadline", function()
    local f = fixture(); f.service.hit(1, f.a, 0.6, 2, 0)
    f.service.hit(1, f.a, 0.8, 3, 1)
    assert(f.heavy[f.a] == 0.6 and #f.events == 1)
    f.service.step(2); assert(f.heavy[f.a] == 0.6)
    f.service.step(4); assert(f.heavy[f.a] == 1)
    f.service.hit(1, f.a, 0.8, 10, 5); f.service.hit(1, f.a, 0.5, 1, 6)
    assert(f.heavy[f.a] == 0.5)
    f.service.step(6.999); assert(f.heavy[f.a] == 0.5)
    f.service.step(7); assert(f.heavy[f.a] == 1, "Refresh incorrectly retained the old fifteen-second deadline")
end)
test("a late frame removes all expired contributions without replaying intermediate history", function()
    local f = fixture()
    f.service.hit(1, f.a, 0.7, 1, 0); f.service.hit(2, f.a, 0.5, 2, 0)
    local before = #f.events; f.service.step(50)
    assert(f.heavy[f.a] == 1 and #f.events == before + 1)
end)
test("changed life on the same target object drops old leases without writing into the new life", function()
    local f = fixture(); f.service.hit(1, f.a, 0.5, 5, 0)
    -- CombatWorld's fresh-body/life reset clears the heavy source before publishing the new token.
    f.a.token = {life = 2}; f.heavy[f.a] = 1
    local before = #f.events; f.service.step(0.1); f.service.step(10)
    assert(#f.events == before and f.heavy[f.a] == 1)
    assert(f.service.hit(2, f.a, 0.7, 2, 10) and f.heavy[f.a] == 0.7)
    f.service.step(12); assert(f.heavy[f.a] == 1 and #f.events == before + 2)
end)
test("owner reset clears outgoing and incoming effects, including several incoming casters", function()
    local f = fixture()
    f.service.hit(1, f.a, 0.6, 5, 0); f.service.hit(2, f.a, 0.5, 5, 0)
    f.service.hit(3, f.b, 0.7, 5, 0)
    f.service.reset(3)
    assert(f.heavy[f.a] == 1 and f.heavy[f.b] == 1)
    local count = #f.events; f.service.reset(3); f.service.step(10); assert(#f.events == count)
end)
test("pause keeps the target life token but immediately resets both incoming and outgoing contributions", function()
    local f = fixture(); local life = f.a.token
    f.service.hit(1, f.a, 0.5, 5, 0); f.service.hit(3, f.b, 0.6, 5, 0)
    -- Anchoring during a match pause does not invalidate CombatWorld.token(target).
    f.a.anchored = true; assert(f.a.token == life)
    f.service.reset(3)
    assert(f.a.token == life and f.heavy[f.a] == 1 and f.heavy[f.b] == 1)
    local before = #f.events; f.service.step(10); assert(#f.events == before)
end)
test("dead casters are removed while another living caster continues to slow", function()
    local f = fixture(); f.service.hit(1, f.a, 0.5, 5, 0); f.service.hit(2, f.a, 0.7, 5, 0)
    f.living[1] = false; f.service.step(0.1); assert(f.heavy[f.a] == 0.7)
    f.living[2] = false; f.service.step(0.2); assert(f.heavy[f.a] == 1)
    local before = #f.events; assert(not f.service.hit(1, f.b, 0.5, 3, 1) and #f.events == before)
end)
test("dead or missing targets are forgotten without applying to an invalid token", function()
    local f = fixture(); f.service.hit(1, f.a, 0.6, 5, 0)
    f.a.token = nil; local before = #f.events
    f.service.step(0.1); f.service.reset(3); f.service.destroy()
    assert(#f.events == before)
    local reads = f.tokensRead; f.service.step(20); assert(f.tokensRead == reads)
    local fresh = fixture(); fresh.a.token = nil
    assert(not fresh.service.hit(1, fresh.a, 0.5, 3, 0) and #fresh.events == 0)
end)
test("invalid multipliers, times and durations never reach the world apply boundary", function()
    local f = fixture()
    local invalid = { {0, 2, 0}, {-0.5, 2, 0}, {1, 2, 0}, {2, 2, 0}, {0/0, 2, 0},
        {math.huge, 2, 0}, {0.5, 0, 0}, {0.5, -2, 0}, {0.5, math.huge, 0},
        {0.5, 0/0, 0}, {0.5, 2, 0/0}, {0.5, 2, math.huge}, {0.5, 1e308, 1e308} }
    for _, values in invalid do assert(not f.service.hit(1, f.a, values[1], values[2], values[3])) end
    assert(not f.service.hit(1, nil, 0.5, 2, 0))
    f.service.step(0/0); assert(#f.events == 0)
end)
test("the dedicated heavy contribution composes with hands without clearing another source", function()
    local f = fixture(); f.hands[f.a] = 0.65
    f.service.hit(1, f.a, 0.5, 1, 0); assert(f.actual[f.a] == 0.5)
    f.service.step(1)
    assert(f.heavy[f.a] == 1 and f.hands[f.a] == 0.65 and f.actual[f.a] == 0.65)
end)
test("expired and destroyed state releases target references and cannot allocate after destruction", function()
    local f = fixture()
    for index = 1, 100 do
        local target = f.target("temporary_" .. index, nil)
        assert(f.service.hit(1, target, 0.6, 1, 0))
    end
    f.service.step(1)
    local reads = f.tokensRead; f.service.step(2); f.service.reset(1)
    assert(f.tokensRead == reads, "Expired targets are still retained by the service")
    f.service.hit(1, f.a, 0.5, 5, 2); f.service.hit(2, f.b, 0.7, 5, 2)
    f.service.destroy(); local count = #f.events; assert(f.heavy[f.a] == 1 and f.heavy[f.b] == 1)
    f.service.destroy(); f.service.step(100); f.service.reset(1)
    assert(not f.service.hit(1, f.a, 0.5, 2, 100) and #f.events == count)
end)
print(string.format("%d TimedSlowService real-source lifecycle contracts passed", total))
