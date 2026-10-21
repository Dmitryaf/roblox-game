--!strict
local Players, RS, SS = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local control = RS:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local bridge = SS:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: {[Player]: boolean}, reports: {[number]: any} = {}, {}
local sequence, transferRequests = 0, 0
local failure: string? = nil
local loss: {[Player]: number} = {}
local healthConnections: {RBXScriptConnection} = {}
local function now(): number return workspace:GetServerTimeNow() end
local function human(p: Player): Humanoid return (p.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function combat(p: Player): any return bridge:Invoke("combat", p.UserId) end
local function context(p: Player): any return bridge:Invoke("context", p.UserId) end
local function own(state: any, p: Player): any
    for _, a in state.active do if a.owner == p.UserId then return a end end
    return nil
end
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat
        assert(not failure, failure)
        if predicate() then return end
        task.wait(0.01)
    until os.clock() >= deadline
    error(message)
end
local connection = control.OnServerEvent:Connect(function(p, kind, id, data)
    if kind == "ready" then ready[p] = true
    elseif kind == "failure" then failure = tostring(id)
    elseif kind == "report" then reports[id] = {player = p, report = data} end
end)
local requests = (RS:WaitForChild("ArrowRemote", 20) :: RemoteEvent).OnServerEvent:Connect(function(_, message: any)
    if type(message) == "table" and message.action == "transfer" then transferRequests += 1 end
end)
local function begin(p: Player, action: string, data: any?): number
    sequence += 1; control:FireClient(p, sequence, action, data); return sequence
end
local function finish(p: Player, id: number): any
    waitFor(function() return reports[id] ~= nil end, 12, "Living command timeout " .. id)
    local report = reports[id]; reports[id] = nil
    assert(report.player == p and report.report.ok, tostring(report.report.error))
    return report.report.data
end
local function command(p: Player, action: string, data: any?): any return finish(p, begin(p, action, data)) end
local function cast(p: Player, ability: string, point: Vector3?, allowed: boolean?): any
    return command(p, "cast", {ability = ability, point = point, ok = allowed ~= false})
end
local function place(p: Player, point: Vector3)
    bridge:Invoke("place", p.UserId, point)
    waitFor(function() return (command(p, "inspect").position - point).Magnitude < 1 end, 5, "Placement replication failed")
    task.wait(0.12)
end
local ok, problem = xpcall(function()
    waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end, 70, "Two living clients not ready")
    assert(RS:GetAttribute("LivingMagicExperiment") == true)
    local loadModule = require :: any
    loadModule(SS:WaitForChild("LivingCoverWorldTests", 5)).run()
    local players = Players:GetPlayers(); table.sort(players, function(a, b) return a.UserId < b.UserId end)
    local caster, warrior = players[1], players[2]
    command(caster, "class", "warrior"); command(caster, "class", "warlock"); command(warrior, "class", "warrior")
    local a, b = begin(caster, "ready"), begin(warrior, "ready"); finish(caster, a); finish(warrior, b)
    waitFor(function() return context(caster).mode == "match" and not context(caster).frozen end, 8, "Living duel did not start")
    for _, p in players do
        human(p).MaxHealth = 1000; human(p).Health = 1000
        loss[p] = 0
        local previous = human(p).Health
        table.insert(healthConnections, human(p).HealthChanged:Connect(function(value)
            loss[p] += math.max(0, previous - value); previous = value
        end))
    end
    local function duel(teleport: boolean)
        waitFor(function() return now() > combat(caster).arrow.readyAt and now() > combat(warrior).melee.readyAt end, 5, "Arrow cooldown")
        -- The teleport case needs enough return-flight time for a genuine E to
        -- cross the simulated network after the confirmed redirect. The damage
        -- case keeps the original shorter lane and all damage expectations.
        local casterZ = if teleport then 45 else 30
        place(caster, Vector3.new(-40, 3, casterZ)); place(warrior, Vector3.new(-40, 3, 0))
        local before, enemyBefore = loss[caster], loss[warrior]
        -- Deliver both real-input commands before their shared schedule. Waiting for
        -- the arrow's round trip before telling the warrior to swing makes a lag
        -- fixture miss its own interception window rather than test the mechanic.
        local startAt = now() + 1
        local shotCommand = begin(caster, "cast", {ability = "arrow", point = Vector3.new(-40, 4, 0), at = startAt, ok = true})
        local swing = begin(warrior, "cast", {ability = "melee", point = Vector3.new(-40, 4, casterZ),
            at = startAt + 0.78 + (casterZ - 30) / 58, ok = true})
        local shot = own(finish(caster, shotCommand).state, caster)
        assert(shot, "LMB did not prepare an arrow")
        local redirected: any = nil
        local lastTrace = 0
        waitFor(function()
            local arrow = own(combat(caster).arrow, caster)
            local blade = own(combat(warrior).melee, warrior)
            if reports[swing] and not reports[swing].report.ok then error(tostring(reports[swing].report.error)) end
            if now() - lastTrace > 0.1 then
                lastTrace = now()
                print("LIVING_TRACE", now() - shot.launchAt, arrow and arrow.position, arrow and arrow.direction,
                    blade and blade.hitAt - shot.launchAt, blade and blade.direction)
            end
            if arrow and arrow.redirected then redirected = arrow; return true end
            return false
        end, 2, "Actual sword did not intercept arrow")
        assert(redirected.owner == caster.UserId and redirected.damageOwner == warrior.UserId)
        assert(redirected.expiresAt == shot.expiresAt and redirected.speed == 58, "Redirect renewed or accelerated arrow")
        if teleport then
            -- A late intercept can occur beside the warrior; wait for an empty landing
            -- envelope instead of asking the production teleport to overlap the opponent.
            waitFor(function()
                local arrow = own(combat(caster).arrow, caster)
                return arrow ~= nil and arrow.position.Z >= 12
            end, 0.4, "Returned arrow did not clear the warrior for teleport")
            local moved = cast(caster, "teleport", nil)
            assert(moved.reply.ok and own(moved.state, caster) == nil)
            task.wait(0.7)
            assert(loss[caster] == before and loss[warrior] == enemyBefore,
                "Teleport damage delta caster/warrior " .. tostring(loss[caster] - before) .. "/" .. tostring(loss[warrior] - enemyBefore))
        else
            waitFor(function() return loss[caster] == before + 25 end, 2, "Returned arrow did not damage caster")
            assert(loss[warrior] == enemyBefore, "Intercepted arrow still damaged warrior")
        end
        finish(warrior, swing)
        for _, p in players do
            local observed = command(p, "livingInspect")
            assert(observed.redirect and observed.redirect.castId == shot.castId and observed.redirect.damageOwner == warrior.UserId,
                "Client did not receive redirected identity")
        end
        print("LIVING_REDIRECT_PASS", if teleport then "creator teleport without damage" else "warrior damage ownership")
    end
    duel(false); duel(true)
    for _, p in {warrior, caster} do
        local ability = if p == warrior then "melee" else "arrow"
        waitFor(function() return now() > combat(p)[ability].readyAt end, 5, "Moving attack cooldown")
        place(p, Vector3.new(-48, 3, 35))
        place(if p == warrior then caster else warrior, Vector3.new(40, 3, -30))
        local movement = command(p, "move", {direction = Vector3.new(0, 0, -1), duration = 2.1, attackAt = 0.5, ability = ability})
        local speed = movement.stableSpeedSegments["16"]
        assert(movement.attackReply.ok and speed.samples >= 20 and speed.speed >= 14, "Native attack suppressed running speed")
        assert(movement.rewinds == 0 and movement.backward < 0.25 and movement.maxExcessStep < 0.75 and movement.corrections == 0,
            "Native attack introduced a movement correction")
        print("LIVING_NATIVE_RUNNING_PASS", ability, "speed", speed.speed, "distance", movement.distance, "excess", movement.maxExcessStep)
    end
    local slot = Vector3.new(22, 0, 28)
    local function coverReady()
        waitFor(function() return now() > combat(caster).hands.readyAt and now() > combat(caster).arrow.readyAt end, 10, "Cover cooldown")
        place(caster, slot + Vector3.new(0, 3, 12)); place(warrior, slot + Vector3.new(0, 3, -6))
    end
    local function raise()
        coverReady()
        local area = own(cast(caster, "hands", slot).state, caster)
        assert(area and area.kind == "preparing")
        waitFor(function() local v = own(combat(caster).hands, caster); return v ~= nil and v.kind == "active" end, 2, "Q did not raise cover")
        return area
    end
    -- A real participant enters an already accepted warning. The slab must never
    -- appear around the body, and an accepted preparation still spends cooldown.
    coverReady()
    local warning = own(cast(caster, "hands", slot).state, caster)
    assert(warning and warning.kind == "preparing")
    bridge:Invoke("place", warrior.UserId, slot + Vector3.new(0, 3, 0))
    waitFor(function() return own(combat(caster).hands, caster) == nil end, 2, "Occupied warning raised a slab around a player")
    assert(combat(caster).hands.readyAt > now(), "Occupied warning refunded accepted preparation")
    local liveCover = workspace:FindFirstChild("LivingCovers", true)
    assert(liveCover and not liveCover:FindFirstChild("RaisedSlab", true), "Occupied warning retained solid cover")
    assert(human(warrior).Health > 0 and human(warrior).WalkSpeed == 16, "Warning harmed or slowed occupant")
    print("LIVING_WARNING_OCCUPIED_PASS: real player blocks accepted raise; cooldown retained")
    raise()
    local before, enemyBefore = loss[caster], loss[warrior]
    cast(warrior, "melee", slot + Vector3.yAxis * 4)
    waitFor(function() return own(combat(warrior).melee, warrior) == nil end, 2, "Sword recovery did not finish")
    assert(own(combat(caster).hands, caster), "Ordinary sword broke cover")
    cast(warrior, "heavy", slot + Vector3.yAxis * 4)
    waitFor(function() return own(combat(caster).hands, caster) == nil end, 2, "Heavy failed to break cover")
    assert(loss[caster] == before and loss[warrior] == enemyBefore)
    raise()
    cast(caster, "arrow", slot + Vector3.new(0, 4, -6))
    waitFor(function() return own(combat(caster).hands, caster) == nil end, 2, "Arrow failed to break cover")
    assert(own(combat(caster).arrow, caster) == nil and loss[warrior] == enemyBefore,
        "Arrow continued through cover or inflicted damage behind it")
    assert(human(caster).WalkSpeed == 16 and human(warrior).WalkSpeed == 16, "Cover retained old area slow")
    command(caster, "tap", {ability = "transfer"}); task.wait(0.15); assert(transferRequests == 0)
    raise()
    -- Pause while one existing cover is active and another action is preparing.
    -- Observe server acceptance first, without spending the preparation on a
    -- client report round trip, then make the opponent leave through the real B.
    local preparing = begin(caster, "cast", {ability = "arrow", point = slot + Vector3.new(0, 4, 40), ok = true})
    waitFor(function()
        local arrow = own(combat(caster).arrow, caster)
        return arrow ~= nil and arrow.kind == "preparing"
    end, 2, "Arrow did not enter preparation before pause")
    local exit = begin(warrior, "exit")
    finish(caster, preparing); finish(warrior, exit)
    waitFor(function() return context(caster).frozen end, 2, "Exit did not pause duel")
    assert(own(combat(caster).hands, caster) == nil and own(combat(caster).arrow, caster) == nil)
    print("LIVING_PAUSE_PREPARATION_PASS: active cover and preparing arrow cancelled")
    task.wait(0.8)
    for _, p in players do
        local inspection = command(p, "inspect")
        assert(inspection.physicsViolations == 0)
        local cues = inspection.interactions
        assert(cues.total > 0 and cues.visibleFrames > 0, "Confirmed interaction effects never appeared")
        for _, kind in {"redirect", "gather", "raise", "shatter"} do
            assert((cues.byKind[kind] or 0) > 0, "Missing confirmed interaction cue: " .. kind)
            assert((cues.soundsLoaded[kind] or 0) > 0, "Studio did not load local interaction sound: " .. kind)
        end
        assert(cues.live == 0 and cues.parts == 0 and cues.physicsViolations == 0 and cues.attributeViolations == 0,
            "Interaction effects leaked or entered physics")
        assert(cues.peak <= 12 and cues.peakParts <= 264, "Interaction VFX exceeded presentation budget")
        print("LIVING_INTERACTION_PRODUCTION_PASS", p.UserId, game:GetService("HttpService"):JSONEncode(cues))
        local native = command(p, "nativeInspect")
        assert(not native.failure, native.failure)
        assert(native.nativeFrames > 20 and native.live == 0, "Production native clips absent or leaked")
        assert(native.geometryViolations == 0 and native.replicationViolations == 0 and native.actorMatchFailures == 0,
            "Native sampler escaped local presentation")
        for _, actor in players do
            local observed = native.actors[tostring(actor.UserId)]
            assert(observed and observed.frames > 10 and observed.maxHandDisplacement > 0.5,
                "Native attack did not move an actor's actual hand on both clients")
        end
        print("LIVING_NATIVE_PRODUCTION_PASS", p.UserId, game:GetService("HttpService"):JSONEncode(native))
    end
    print("LIVING_MAGIC_PASS: real two-client class/R/LMB/Q/E; redirect damage/teleport; cover sword/heavy/arrow; no DoT/slow; pause cleanup")
end, debug.traceback)
connection:Disconnect(); requests:Disconnect()
for _, c in healthConnections do c:Disconnect() end
game:GetService("StudioTestService"):EndTest({ok = ok, error = if ok then nil else tostring(problem)})
