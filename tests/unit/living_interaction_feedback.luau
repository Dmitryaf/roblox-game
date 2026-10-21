--!strict
-- Real interaction controller with mocked rendering ports, not Studio/audio acceptance.
-- Deliberate presentation-contract change: confirmed one-shot sounds/accents finish their
-- own short lifetime after normal action end or sync; only sustained gather follows the
-- action's presence. Cancellation, invalid lives and destroy still remove every resource.
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Feedback = luau.load(fs.readFile("src/client/presentation/LivingInteractionFeedback.luau"))()
local V = rb.Vector3
local count = 0
local function test(name, action) action(); count += 1; print("PASS", name) end
local function fixture()
    local f = { time = 100, lives = { [1] = 7, [2] = 9 }, created = {} }
    f.feedback = Feedback.new({ now = function() return f.time end,
        valid = function(owner, life) return f.lives[owner] == life end,
        create = function(kind, event, expires)
            local entry = { kind = kind, event = event, expires = expires, destroyed = false, steps = 0 }
            local handle = { step = function() entry.steps += 1 end, destroy = function() assert(not entry.destroyed); entry.destroyed = true end }
            table.insert(f.created, entry); return handle
        end,
    })
    function f.cover(kind, id, reason)
        return { kind = kind, areaId = id or 3, owner = 1, life = 7, reason = reason,
            position = V.zero, startedAt = 100, launchAt = 100.8, expiresAt = 108.8 }
    end
    function f.arrow(kind)
        return { kind = kind or "redirected", castId = 4, owner = 1, life = 7, damageOwner = 2, damageLife = 9,
            position = V.zero, direction = V.zAxis, sampledAt = 100, expiresAt = 103 }
    end
    return f
end
test("only confirmed redirect emits success and duplicated delivery cannot replay it", function()
    local f = fixture()
    f.feedback.arrow(f.arrow("preparing")); f.feedback.arrow(f.arrow("launched")); f.feedback.arrow(f.arrow("flying"))
    assert(#f.created == 0)
    f.feedback.arrow(f.arrow()); f.feedback.arrow(f.arrow())
    assert(#f.created == 1 and f.created[1].kind == "redirect")
    f.feedback.destroy()
end)
test("snapshot and reply never recreate a historical redirect burst", function()
    local f = fixture()
    f.feedback.arrow({ kind = "snapshot", state = { active = { f.arrow() } } })
    f.feedback.arrow({ kind = "reply", state = { active = { f.arrow() } } })
    assert(#f.created == 0)
    f.feedback.arrow(f.arrow())
    f.feedback.arrow({ kind = "snapshot", state = { active = {} } })
    assert(not f.created[1].destroyed and f.feedback.inspect().live == 1)
    f.feedback.step(100.43); assert(f.created[1].destroyed and f.feedback.inspect().live == 0)
    f.feedback.destroy()
end)
test("old future or dead participant lives cannot create a redirect", function()
    local f = fixture()
    f.lives[1] = 8; f.feedback.arrow(f.arrow()); assert(#f.created == 0)
    f.lives[1] = 6; f.feedback.arrow(f.arrow()); assert(#f.created == 0)
    f.lives[1], f.lives[2] = 7, nil; f.feedback.arrow(f.arrow()); assert(#f.created == 0)
    f.feedback.destroy()
end)
test("stale network event and expired projectile cannot flash a fresh contact", function()
    local f = fixture()
    f.time = 100.66; f.feedback.arrow(f.arrow()); assert(#f.created == 0)
    f.time = 104; f.feedback.arrow(f.arrow()); assert(#f.created == 0)
    f.feedback.destroy()
end)
test("normal ended arrow preserves contact tail and late redirected event stays silent", function()
    local f = fixture()
    f.feedback.arrow(f.arrow()); f.feedback.arrow(f.arrow("ended"))
    assert(not f.created[1].destroyed)
    f.feedback.arrow(f.arrow()); assert(#f.created == 1)
    f.feedback.step(100.43); assert(f.created[1].destroyed)
    f.feedback.destroy()
end)
test("gather resolves into one raise and one shatter with no duplicate cleanup flicker", function()
    local f = fixture()
    f.feedback.cover(f.cover("preparing")); assert(f.created[1].kind == "gather")
    f.time = 100.8; f.feedback.cover(f.cover("active")); assert(f.created[1].destroyed and f.created[2].kind == "raise")
    f.feedback.cover(f.cover("active")); assert(#f.created == 2 and not f.created[2].destroyed)
    f.feedback.cover(f.cover("ended", 3, "shattered")); assert(not f.created[2].destroyed and f.created[3].kind == "shatter")
    f.feedback.cover(f.cover("ended", 3, "shattered")); assert(#f.created == 3 and not f.created[3].destroyed)
    f.feedback.cover(f.cover("preparing")); f.feedback.cover(f.cover("active")); assert(#f.created == 3)
    f.feedback.destroy()
end)
test("occupied cancelled paused dead reset and expired cover never shatter", function()
    for _, reason in { "occupied", "paused", "dead", "reset", "left", "expired" } do
        local f = fixture(); f.feedback.cover(f.cover("preparing"))
        f.feedback.cover(f.cover("ended", 3, reason))
        assert(#f.created == 1 and f.created[1].destroyed, reason)
        f.feedback.destroy()
    end
end)
test("quiet cover sync cannot play onset or replay a shatter", function()
    local f = fixture()
    f.feedback.cover(f.cover("preparing"), true)
    f.feedback.cover(f.cover("active"), true)
    f.feedback.cover(f.cover("ended", 3, "shattered"), true)
    assert(#f.created == 0)
    f.feedback.cover(f.cover("ended", 3, "shattered")); assert(#f.created == 0)
    f.feedback.destroy()
end)
test("cover snapshot removes missing action resources without touching arrow resources", function()
    local f = fixture()
    f.feedback.arrow(f.arrow()); f.feedback.cover(f.cover("preparing"))
    f.feedback.syncCover({})
    assert(not f.created[1].destroyed and f.created[2].destroyed)
    f.feedback.destroy()
end)
test("normal hit teleport expiry and cover consumption preserve the bounded redirect sound", function()
    for _, reason in { "hit", "teleported", "expired", "cover_broken", "hands_transferred" } do
        local f = fixture(); f.feedback.arrow(f.arrow())
        local ended = f.arrow("ended"); ended.reason = reason
        f.feedback.arrow(ended)
        f.feedback.arrow({ kind = "reply", state = { active = {} } })
        assert(not f.created[1].destroyed and f.feedback.inspect().live == 1, reason)
        f.feedback.step(100.43); assert(f.created[1].destroyed)
        f.feedback.destroy()
    end
end)
test("explicit arrow cancellation still cuts every one-shot immediately", function()
    for _, reason in { "dead", "left", "reset", "paused", "invalid_position", "interceptor_reset" } do
        local f = fixture(); f.feedback.arrow(f.arrow())
        local ended = f.arrow("ended"); ended.reason = reason
        f.feedback.arrow(ended)
        assert(f.created[1].destroyed and f.feedback.inspect().live == 0, reason)
        f.feedback.arrow(f.arrow()); assert(#f.created == 1)
        f.feedback.destroy()
    end
end)
test("raise and shatter complete their own lifetimes through empty cover snapshots", function()
    local f = fixture(); f.time = 100.8
    f.feedback.cover(f.cover("active"))
    f.feedback.cover(f.cover("ended", 3, "shattered"))
    f.feedback.syncCover({})
    assert(#f.created == 2 and not f.created[1].destroyed and not f.created[2].destroyed)
    f.feedback.step(101.36); assert(f.created[1].destroyed and not f.created[2].destroyed)
    f.feedback.step(101.51); assert(f.created[2].destroyed and f.feedback.inspect().live == 0)
    f.feedback.destroy()
end)
test("explicit cover pause reset and death clear even a previously completed event tail", function()
    for _, reason in { "paused", "reset", "dead", "left" } do
        local f = fixture(); f.time = 100.8
        f.feedback.cover(f.cover("active")); f.feedback.cover(f.cover("ended", 3, "shattered"))
        f.feedback.cover(f.cover("ended", 3, reason))
        assert(f.created[1].destroyed and f.created[2].destroyed and f.feedback.inspect().live == 0, reason)
        f.feedback.destroy()
    end
end)
test("real life changes and deadline progress clean effects without rendered frames", function()
    local f = fixture()
    f.feedback.arrow(f.arrow()); f.feedback.cover(f.cover("preparing"))
    f.feedback.step(100.2); assert(f.created[1].steps == 1)
    f.lives[2] = 10; f.feedback.step(100.21); assert(f.created[1].destroyed and not f.created[2].destroyed)
    f.feedback.step(101); assert(f.created[2].destroyed and f.feedback.inspect().live == 0)
    f.feedback.destroy()
end)
test("concurrent cues are bounded and destroy is idempotent", function()
    local f = fixture()
    for id = 1, 30 do f.feedback.cover(f.cover("preparing", id)) end
    assert(f.feedback.inspect().live == 12)
    for i = 1, 18 do assert(f.created[i].destroyed) end
    f.feedback.destroy(); f.feedback.destroy()
    for _, entry in f.created do assert(entry.destroyed) end
    f.feedback.cover(f.cover("preparing", 31)); f.feedback.arrow(f.arrow())
    assert(#f.created == 30)
end)
test("CoverEffects keeps original pose contract and marks sync cues quiet", function()
    local received, started, stopped, syncs = {}, 0, 0, 0
    local CoverEffects = luau.load(fs.readFile("src/client/presentation/CoverEffects.luau"))()
    local effects = CoverEffects.new({ begin = function() started += 1 end, stop = function() stopped += 1 end }, {
        cover = function(e, quiet) table.insert(received, { event = e, quiet = quiet }) end,
        syncCover = function() syncs += 1 end,
    })
    local f = fixture()
    effects.event(f.cover("preparing")); effects.sync({ f.cover("preparing") })
    assert(started == 1 and #received == 2 and received[2].quiet and syncs == 1)
    effects.sync({}); assert(stopped == 1)
    effects.destroy(); f.feedback.destroy()
end)
print("Living interaction feedback tests:", count)
