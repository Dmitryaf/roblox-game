--!strict
-- Six live input clients. Fixture placements start only after the measured approach.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local control = ReplicatedStorage:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local losses: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local seenBodies: { [Model]: number } = {}
local totalCorrections, sequence = 0, 0
local failure: string? = nil
local activeAt: number? = nil
local firstActionAt: number? = nil
local firstContestedAt: number? = nil
local firstDamageAt: number? = nil
local players: { Player } = {}
local function now(): number return workspace:GetServerTimeNow() end
local function human(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function snapshot(player: Player): any return bridge:Invoke("snapshot", player.UserId) end
local function combat(player: Player): any return bridge:Invoke("combat", player.UserId) end
local function life(player: Player): number return ((player.Character :: Model):GetAttribute("CombatLife") or 0) :: number end
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat
        if failure then error(failure) end
        if predicate() then return end
        task.wait(0.02)
    until os.clock() >= deadline
    error(message)
end
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
    if kind == "ready" then ready[player] = true
    elseif kind == "failure" then failure = tostring(id)
    elseif kind == "report" then reports[id] = { player = player, report = data } end
end))
local function begin(player: Player, action: string, data: any?): number
    sequence += 1; control:FireClient(player, sequence, action, data); return sequence
end
local function finish(player: Player, id: number): any
    waitFor(function() return reports[id] ~= nil end, 15, "Arena client command timed out: " .. id)
    local delivery = reports[id]; reports[id] = nil
    assert(delivery.player == player and delivery.report.ok, delivery.report.error)
    return delivery.report.data
end
local function command(player: Player, action: string, data: any?): any return finish(player, begin(player, action, data)) end
local function together(actions: { any }): { any }
    local ids, results = {}, {}
    for index, action in actions do ids[index] = begin(action.player, action.action, action.data) end
    for index, action in actions do results[index] = finish(action.player, ids[index]) end
    return results
end
local function place(player: Player, point: Vector3)
    bridge:Invoke("place", player.UserId, point)
    waitFor(function() return (command(player, "inspect").position - point).Magnitude < 1 end, 4, "Arena fixture placement did not reach owner")
end
local function outside()
    local actions = {}
    for index, player in players do
        local point = Vector3.new(65, 3, -48 + index * 14)
        bridge:Invoke("place", player.UserId, point)
        table.insert(actions, { player = player, action = "inspect" })
    end
    together(actions); task.wait(0.15)
end
local function watch(player: Player)
    local humanoid = human(player); humanoid.MaxHealth, humanoid.Health = 1000, 1000
    losses[player] = 0; local previous = humanoid.Health
    table.insert(connections, humanoid.HealthChanged:Connect(function(current)
        if current < previous then
            losses[player] += previous - current
            if activeAt and not firstDamageAt then firstDamageAt = now() end
        end
        previous = current
    end))
end
local function owned(state: any, player: Player): any?
    for _, item in state.active do if item.owner == player.UserId then return item end end
    return nil
end
local function phaseMove(actions: { any }, label: string)
    local data = together(actions)
    for index, result in data do
        print("ArenaApproach", label, actions[index].player.UserId, "distance", result.distance, "rewinds", result.rewinds,
            "corrections", result.corrections, "speed16", result.stableSpeedSegments["16"].speed, "nearestBody", result.minOtherRootGap)
        for _, trace in result.rewindTrace do
            print("ArenaRewind", label, actions[index].player.UserId, "at", trace.at, "dt", trace.dt,
                "progress", trace.progress, "previous", trace.previous, "current", trace.current, "velocity", trace.velocity,
                "corrections", trace.correctionsBefore, trace.correctionsAfter,
                "other", if trace.other then trace.other.owner else nil, "gap", if trace.other then trace.other.gap else nil,
                "otherPosition", if trace.other then trace.other.position else nil)
        end
    end
    for index, result in data do
        assert(result.corrections == 0 and result.rewinds == 0, "Real approach introduced a movement correction or velocity rewind")
        assert(result.samples > 10 and result.distance > 10, "Approach did not exercise real W movement")
        local segment = result.stableSpeedSegments["16"]
        assert(segment.time > 0.4 and segment.speed > 13.5 and segment.speed < 18.5, "Native walking speed failed during six-client approach")
        if actions[index].data.dashAt then assert(result.dashReply and result.dashReply.ok, "Warrior approach omitted its real E") end
    end
end
local function waitActive(count: number)
    waitFor(function()
        local active = 0
        for _, player in players do local state = snapshot(player); if state.mode == "match" and not state.frozen then active += 1 end end
        return active == count
    end, 9, "Arena did not establish the expected live equal roster")
end
local function readySix(order: { number })
    -- This order keeps the initially alternating classes mixed on both teams.
    -- Gathering=5 allows six real R replies before the first round is committed.
    for _, index in order do command(players[index], "ready") end
    waitActive(6)
end
table.insert(connections, RunService.Heartbeat:Connect(function()
    for _, player in players do
        local character = player.Character
        if character then
            local current = (character:GetAttribute("CombatMovementCorrections") or 0) :: number
            totalCorrections += math.max(0, current - (seenBodies[character] or 0)); seenBodies[character] = current
        end
    end
    if #players < 1 then return end
    local state = snapshot(players[1])
    if state.mode == "match" and state.phase == "active" then
        if not activeAt then activeAt = now() end
        if state.countA + state.countB > 0 and not firstActionAt then firstActionAt = now() end
        if state.zone == "contested" and not firstContestedAt then firstContestedAt = now() end
    end
end))
local ok, problem = xpcall(function()
    waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 6 end, if ServerStorage:GetAttribute("StagedArenaTest") then 150 else 110, "Six arena clients did not initialize")
    players = Players:GetPlayers(); table.sort(players, function(a, b) return a.UserId < b.UserId end)
    assert(#players == 6, "Arena requires six real connected clients")
    for index, player in players do
        command(player, "class", if index % 2 == 1 then "warrior" else "warlock")
    end
    local order = { 1, 2, 4, 3, 5, 6 }; readySix(order)
    local first = snapshot(players[1]); local matchId = first.matchId
    local teams: { { Player } } = { {}, {} }
    local warriors: { Player } = {}
    local warlocks: { Player } = {}
    for _, player in players do
        local state = snapshot(player); assert(state.matchId == matchId and state.target == 150 and state.duration == 240)
        table.insert(teams[state.team], player)
        if (player.Character :: Model):GetAttribute("CombatClass") == "warrior" then table.insert(warriors, player) else table.insert(warlocks, player) end
        assert(math.abs(math.abs(root(player).Position.Z) - 118) < 5, "First approach did not begin on the actual team pad")
        watch(player)
    end
    for _, team in teams do
        local classes: { [string]: number } = {}
        assert(#team == 3)
        for _, player in team do local key = (player.Character :: Model):GetAttribute("CombatClass") :: string; classes[key] = (classes[key] or 0) + 1 end
        assert(classes.warrior and classes.warlock and (classes.warrior == 2 or classes.warlock == 2), "Both teams must include both classes and a repeated class")
        table.sort(team, function(a, b) return root(a).Position.X < root(b).Position.X end)
    end
    -- Walking-speed assertions require a clear route. The old 30/33/36 endpoints
    -- compressed teammates into real body contacts (observed root gap < 2).
    -- Clear the leading pair first so delayed replicas at the pad cannot obstruct
    -- the followers. Every displacement still comes from actual W input.
    local flank = { 28, 56, 76 }
    for index = 3, 1, -1 do
        local wave = {}
        for _, team in teams do
            local player = team[index]
            table.insert(wave, { player = player, action = "move", data = {
                direction = Vector3.xAxis, duration = (flank[index] - root(player).Position.X) / 16 } })
        end
        phaseMove(wave, "leave-pad-" .. index)
    end
    local moves = {}
    for _, player in players do
        -- The input report and final physics packet use different replication
        -- paths. Observe the same endpoint on the server before turning the lane.
        local received = root(player).Position
        waitFor(function()
            for _, x in flank do if math.abs(root(player).Position.X - x) < 2 then return true end end
            return false
        end, 2, "Real movement failed to replicate its clear screen flank from " .. tostring(received))
        local p = root(player).Position
        print("ArenaFlankReplicated", player.UserId, "atReport", received, "settled", p)
        local warrior = (player.Character :: Model):GetAttribute("CombatClass") == "warrior"
        local sign = if snapshot(player).team == 1 then 1 else -1
        local distance = math.abs(p.Z) - 8
        table.insert(moves, { player = player, action = "move", data = { direction = Vector3.new(0, 0, -sign),
            duration = (distance - (if warrior then 11.52 else 0)) / 16, dashAt = if warrior then 0.35 else nil } })
    end
    phaseMove(moves, "around-screen")
    moves = {}
    for _, team in teams do for index, player in team do
        local targetX = -12 + (index - 1) * 12
        table.insert(moves, { player = player, action = "move", data = { direction = -Vector3.xAxis, duration = (root(player).Position.X - targetX) / 16 } })
    end end
    phaseMove(moves, "enter-objective")
    waitFor(function() return firstActionAt ~= nil and firstContestedAt ~= nil end, 2, "Natural approach did not produce a first contested objective action")
    print("ArenaFirstAction", "startToZone", (firstActionAt :: number) - (activeAt :: number),
        "startToContested", (firstContestedAt :: number) - (activeAt :: number), "fixturePlacesBeforeFirstAction", 0)

    -- The first combat sample uses the positions reached by real movement, before
    -- any fixture placement. It measures scripted input, not human engagement.
    local naturalCaster: Player? = nil
    local naturalTarget: Player? = nil
    local closest = math.huge
    for _, warlock in warlocks do
        for _, enemy in players do
            if snapshot(warlock).team == snapshot(enemy).team then continue end
            local distance = (root(warlock).Position - root(enemy).Position).Magnitude
            if distance < closest then closest, naturalCaster, naturalTarget = distance, warlock, enemy end
        end
    end
    assert(naturalCaster and naturalTarget and closest < 30, "Natural approach did not leave a legal live combat target")
    local approachCaster, approachTarget = naturalCaster :: Player, naturalTarget :: Player
    local beforeNatural = losses[approachTarget]
    command(approachCaster, "cast", { ability = "hands", point = root(approachTarget).Position - Vector3.yAxis * 3, ok = true })
    waitFor(function() return losses[approachTarget] >= beforeNatural + 3 and firstDamageAt ~= nil end,
        4, "Real Q from the natural approach did not damage its live opponent before fixture placement")
    print("ArenaNaturalFirstDamage", "startToDamage", (firstDamageAt :: number) - (activeAt :: number),
        "source", approachCaster.UserId, "target", approachTarget.UserId, "gap", closest, "fixturePlacesBeforeDamage", 0)
    local retreatLife = life(approachTarget)
    local retreatArea = owned(combat(approachCaster).hands, approachCaster)
    assert(retreatArea and retreatArea.kind == "active", "Retreat requires an actually active source")
    local retreatSign = if root(approachTarget).Position.Z >= 0 then 1 else -1
    -- Leave enough real walking after the replicated slow clears to measure the
    -- unchanged >0.4-second free-speed segment before the source's original TTL.
    local retreat = command(approachTarget, "move", { direction = Vector3.zAxis * retreatSign, duration = 2.2 })
    assert(life(approachTarget) == retreatLife and retreat.corrections == 0 and retreat.rewinds == 0,
        "Actual retreat from the opening hands area changed life or rewound movement")
    print("ArenaRetreatTrace", approachTarget.UserId, "start", retreat.start, "finish", retreat.finish,
        "slowTime", retreat.stableSpeedSegments["10.4"].time, "slowSpeed", retreat.stableSpeedSegments["10.4"].speed,
        "freeTime", retreat.stableSpeedSegments["16"].time, "freeSpeed", retreat.stableSpeedSegments["16"].speed,
        "serverSpeed", human(approachTarget).WalkSpeed)
    assert(retreat.stableSpeedSegments["10.4"].time > 0.2 and retreat.stableSpeedSegments["16"].time > 0.4
        and retreat.stableSpeedSegments["10.4"].speed > 9 and retreat.stableSpeedSegments["10.4"].speed < 12
        and retreat.stableSpeedSegments["16"].speed > 13.5 and retreat.stableSpeedSegments["16"].speed < 18.5,
        "Real retreat did not transition from hands slow to native free movement")
    waitFor(function() return human(approachTarget).WalkSpeed == 16 end, 2, "Leaving hands retained its slow")
    assert(now() < retreatArea.expiresAt and owned(combat(approachCaster).hands, approachCaster) ~= nil,
        "Retreat recovery was only observed after the hands area expired")
    assert(((root(approachTarget).Position - retreatArea.position) * Vector3.new(1, 0, 1)).Magnitude > 8,
        "Retreat did not leave the actual active area")
    print("ArenaNaturalRetreat", approachTarget.UserId, "distance", retreat.distance,
        "slowSeconds", retreat.stableSpeedSegments["10.4"].time, "freeSpeed", retreat.stableSpeedSegments["16"].speed,
        "corrections", retreat.corrections, "rewinds", retreat.rewinds)

    -- Reproducible close combat starts after the real, measured route above.
    outside()
    local pairs: { any } = {}
    local available = table.clone(warlocks)
    for index, warrior in warriors do
        local enemyIndex: number? = nil
        for candidate, warlock in available do if snapshot(warlock).team ~= snapshot(warrior).team then enemyIndex = candidate; break end end
        assert(enemyIndex, "Six-player mixed roster could not form three opposing class pairs")
        local warlock = table.remove(available, enemyIndex :: number) :: Player
        local z = (index - 2) * 30
        place(warrior, Vector3.new(2.5, 3, z)); place(warlock, Vector3.new(-2.5, 3, z))
        table.insert(pairs, { warrior = warrior, warlock = warlock, warriorBefore = losses[warrior], warlockBefore = losses[warlock] })
    end
    local handsReady = 0
    for _, warlock in warlocks do handsReady = math.max(handsReady, combat(warlock).hands.readyAt) end
    waitFor(function() return now() >= handsReady + 0.1 end, 10, "Natural opening hands cooldown did not elapse before concurrent sources")
    -- The natural opening area can still tick while pairs are being placed. Take
    -- damage baselines only after its original duration and cooldown have elapsed.
    for _, pair in pairs do pair.warriorBefore, pair.warlockBefore = losses[pair.warrior], losses[pair.warlock] end
    local actions: { any } = {}
    for _, player in players do table.insert(actions, { player = player, action = "inspect" }) end
    local loadBefore = together(actions)
    actions = {}
    for _, pair in pairs do
        table.insert(actions, { player = pair.warlock, action = "cast", data = { ability = "hands", point = root(pair.warrior).Position - Vector3.yAxis * 3, ok = true } })
        table.insert(actions, { player = pair.warrior, action = "cast", data = { ability = "heavy", point = root(pair.warlock).Position, ok = true } })
    end
    together(actions)
    waitFor(function()
        for _, pair in pairs do
            if losses[pair.warlock] < pair.warlockBefore + 25 or losses[pair.warrior] < pair.warriorBefore + 3 then return false end
        end
        return true
    end, 4, "Three concurrent hands/heavy pairs did not apply confirmed damage to all six live players")
    local liveAreas = 0
    for _, area in combat(players[1]).hands.active do if area.kind == "active" then liveAreas += 1 end end
    assert(liveAreas == 3, "Six-player overlap did not retain three independent hands sources")
    for _, pair in pairs do
        assert(losses[pair.warlock] == pair.warlockBefore + 25 and math.abs(human(pair.warrior).WalkSpeed - 10.4) < 0.001)
    end
    actions = {}
    for _, pair in pairs do
        pair.arrowBefore, pair.swordBefore = losses[pair.warrior], losses[pair.warlock]
        table.insert(actions, { player = pair.warlock, action = "cast", data = { ability = "arrow", point = root(pair.warrior).Position, ok = true } })
        table.insert(actions, { player = pair.warrior, action = "cast", data = { ability = "melee", point = root(pair.warlock).Position, ok = true } })
    end
    together(actions)
    waitFor(function()
        for _, pair in pairs do if losses[pair.warrior] < pair.arrowBefore + 25 or losses[pair.warlock] < pair.swordBefore + 20 then return false end end
        return true
    end, 3, "Concurrent actual LMB actions did not deliver all arrows and sword follow-ups")
    assert(firstDamageAt ~= nil); print("ArenaCombat", "startToFirstDamage", (firstDamageAt :: number) - (activeAt :: number), "sources", liveAreas, "realClients", #players)
    actions = {}; for _, player in players do table.insert(actions, { player = player, action = "inspect" }) end
    for index, data in together(actions) do
        assert(data.physicsViolations == 0 and data.contacts.heavy >= 3 and data.contacts.melee >= 3, "Observer omitted confirmed contacts or ability VFX entered physics")
        for _, key in { "hands", "heavy", "arrow", "melee", "dash" } do assert(data.visuals[key].seen > 0, "Six-player observer never saw " .. key) end
        print("ArenaObserver", players[index].UserId, "heavy", data.contacts.heavy, "melee", data.contacts.melee, "physics", data.physicsViolations)
        local elapsed = data.sampledAt - loadBefore[index].sampledAt
        print("ArenaObservedLoad", players[index].UserId, "seconds", elapsed,
            "renderHz", (data.renderFrames - loadBefore[index].renderFrames) / elapsed,
            "heartbeatHz", (data.heartbeatFrames - loadBefore[index].heartbeatFrames) / elapsed,
            "handsPeak", data.visuals.hands.peak, "heavyPeak", data.visuals.heavy.peak,
            "arrowPeak", data.visuals.arrow.peak, "meleePeak", data.visuals.melee.peak)
    end
    waitFor(function() return #combat(players[1]).hands.active == 0 end, 5, "Concurrent hands sources failed to expire")
    outside()
    local coverCaster, coverTarget = warlocks[1], pairs[1].warrior
    for _, warrior in warriors do if snapshot(warrior).team ~= snapshot(coverCaster).team then coverTarget = warrior; break end end
    waitFor(function() return now() > combat(coverCaster).arrow.readyAt + 0.1 end, 4, "Cover arrow cooldown did not elapse")
    place(coverCaster, Vector3.new(35, 3, 50)); place(coverTarget, Vector3.new(53, 3, 50))
    local coverHealth = human(coverTarget).Health
    local coverLosses = losses[coverTarget]
    local coverOrigin, coverEnd = root(coverCaster).Position + Vector3.yAxis, root(coverTarget).Position
    local query = RaycastParams.new()
    query.FilterType, query.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { coverCaster.Character :: Model }
    local obstruction = workspace:Raycast(coverOrigin, coverEnd - coverOrigin, query)
    assert(obstruction and obstruction.Instance:GetAttribute("MainCover") == true, "Cover probe did not cross real arena cover")
    command(coverCaster, "cast", { ability = "arrow", point = coverEnd, ok = true })
    waitFor(function() return owned(combat(coverCaster).arrow, coverCaster) == nil end, 3, "Arrow did not resolve against cover")
    -- Default Roblox regeneration may increase Health during this observation.
    -- Cumulative negative HealthChanged deltas also detect damage masked by healing.
    local coveredDamage = losses[coverTarget] - coverLosses
    print("ArenaCover", "caster", coverCaster.UserId, "target", coverTarget.UserId, "obstruction", obstruction.Instance:GetFullName(),
        "damage", coveredDamage, "healthBefore", coverHealth, "healthAfter", human(coverTarget).Health)
    assert(coveredDamage == 0, "A real arrow damaged its opponent through arena cover")
    outside()
    local a, b = teams[1][1], teams[2][1]
    place(a, Vector3.new(-4, 3, 0)); place(b, Vector3.new(4, 3, 0))
    waitFor(function() return snapshot(a).zone == "contested" end, 2, "Six-player match lost contested-zone behavior")
    local disputed = snapshot(a); task.wait(1.2)
    assert(snapshot(a).scoreA == disputed.scoreA and snapshot(a).scoreB == disputed.scoreB, "Contested six-player zone awarded score")
    local deadBody, deadLife, killedAt = b.Character, life(b), os.clock(); bridge:Invoke("kill", b.UserId)
    waitFor(function() return snapshot(a).countB == 0 end, 1, "Dead player continued contesting the objective")
    place(a, Vector3.new(65, 3, 60)); local empty = snapshot(a)
    waitFor(function()
        local character = b.Character; local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        return character ~= nil and character ~= deadBody and humanoid ~= nil and humanoid.Health > 0 and life(b) > deadLife
    end, 9, "Six-player participant did not respawn with a fresh life")
    assert(os.clock() - killedAt >= 4.5 and math.abs(math.abs(root(b).Position.Z) - 118) < 5 and human(b).Health == 100)
    assert(snapshot(a).scoreA == empty.scoreA and snapshot(a).scoreB == empty.scoreB, "Empty objective accumulated score through respawn")
    watch(b); place(a, Vector3.new(0, 3, 0)); local held = snapshot(a)
    waitFor(function() return snapshot(a).scoreA >= held.scoreA + 1 end, 3, "Exclusive six-player control did not score")
    outside()

    -- Active source and preparing projectile are both canceled by a real B pause.
    local source, shotOwner = warlocks[1], warlocks[2]
    local gate = combat(source).hands.readyAt
    waitFor(function() return now() > gate + 0.1 end, 10, "Arena hands cooldown did not elapse")
    place(source, Vector3.new(-8, 3, 40)); place(shotOwner, Vector3.new(20, 3, 0))
    command(source, "cast", { ability = "hands", point = Vector3.new(0, 0, 40), ok = true })
    waitFor(function() local area = owned(combat(source).hands, source); return area ~= nil and area.kind == "active" end, 3, "Pause probe had no active hands")
    command(shotOwner, "cast", { ability = "arrow", point = Vector3.new(-25, 1, 0), ok = true })
    local quitter = warriors[1]; local lives = {}; for _, player in players do lives[player] = life(player) end
    command(quitter, "exit")
    local remaining = if quitter == a then b else a
    waitFor(function() return snapshot(remaining).phase == "paused" end, 2, "Real B did not pause unequal 3v3")
    local paused = snapshot(remaining)
    assert(#combat(remaining).hands.active == 0 and #combat(remaining).arrow.active == 0 and #combat(remaining).heavy.active == 0)
    task.wait(0.35); local frozen = snapshot(remaining)
    assert(frozen.frozen and frozen.scoreA == paused.scoreA and frozen.scoreB == paused.scoreB and math.abs(frozen.remaining - paused.remaining) < 0.05)
    command(quitter, "ready"); waitActive(6)
    for _, player in players do
        -- watch() raises this fixture's MaxHealth to 1000 to survive the damage
        -- sequence. Production resetContext refills MaxHealth, not a hardcoded 100.
        assert(life(player) > lives[player] and snapshot(player).matchId == matchId
            and human(player).Health == human(player).MaxHealth, "Replacement did not reset a participant's life and full health")
        print("ArenaFreshLife", player.UserId, "before", lives[player], "after", life(player),
            "health", human(player).Health, "maxHealth", human(player).MaxHealth)
    end
    command(quitter, "exit")
    waitFor(function() return snapshot(remaining).phase == "finished" end, 6, "Missing replacement did not end the interrupted round")
    assert(snapshot(remaining).result.reason == "interrupted" and snapshot(remaining).result.winner == nil)
    readySix(order)
    local replay = snapshot(players[1]); assert(replay.matchId > matchId and replay.scoreA == 0 and replay.scoreB == 0 and replay.result == nil)
    for _, player in players do assert(snapshot(player).matchId == replay.matchId and not snapshot(player).frozen) end
    local replayCaster = warlocks[1]; local replayTarget: Player? = nil
    for _, warrior in warriors do if snapshot(warrior).team ~= snapshot(replayCaster).team then replayTarget = warrior; break end end
    assert(replayTarget); local target = replayTarget :: Player; watch(target)
    place(replayCaster, Vector3.new(-8, 3, 40)); place(target, Vector3.new(0, 3, 40))
    command(replayCaster, "cast", { ability = "arrow", point = root(target).Position, ok = true })
    waitFor(function() return losses[target] >= 25 end, 3, "Fresh six-player replay could not apply real arrow damage")
    assert(totalCorrections == 0, "Six-client combat or lifecycle introduced authoritative movement corrections")
    actions = {}; for _, player in players do table.insert(actions, { player = player, action = "inspect" }) end
    for _, data in together(actions) do assert(data.physicsViolations == 0) end
    print("PASS arena6: real mixed/repeated class GUI and R 3v3, measured native W/E flank and first contest, three simultaneous hands/heavy and arrow/sword pairs, all-six observers, zone/score/death/respawn, real pause/replacement/fresh lives/interruption/replay, zero corrections and VFX physics")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
