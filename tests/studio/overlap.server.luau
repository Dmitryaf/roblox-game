--!strict
-- Four real owners, unchanged team rules, actual class/ready/Q/W/B inputs through MixedDriver.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local control = ReplicatedStorage:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local connections: { RBXScriptConnection } = {}
local watching: { [Player]: any } = {}
local failure: string? = nil
local sequence = 0
local center = Vector3.new(0, 0, -30)
local victimPoint = Vector3.new(0, 3, -30)
local warlockPoint = Vector3.new(3, 3, -30)
local warriorPoint = Vector3.new(0, 3, -35)
local farPoint = Vector3.new(-60, 3, -45)
local function now(): number return workspace:GetServerTimeNow() end
local function exact(value: any): string return if type(value) == "number" then string.format("%.17g", value) else tostring(value) end
local function humanoid(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function flat(a: Vector3, b: Vector3): number return ((a-b) * Vector3.new(1, 0, 1)).Magnitude end
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
    if kind == "ready" then ready[player] = true
    elseif kind == "failure" then failure = tostring(id)
    elseif kind == "report" then reports[id] = {player = player, report = data} end
end))
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat
        if failure then error(failure) end
        if predicate() then return end
        task.wait(0.02)
    until os.clock() >= deadline
    error(message)
end
local function command(player: Player, action: string, data: any?): any
    sequence += 1
    local id = sequence
    control:FireClient(player, id, action, data)
    waitFor(function() return reports[id] ~= nil end, 12, "Overlap command timed out: " .. player.Name .. "/" .. action)
    local delivery = reports[id]; reports[id] = nil
    assert(delivery.player == player and delivery.report.ok, delivery.report.error)
    return delivery.report.data
end
local function watch(player: Player)
    local body = humanoid(player)
    local previous = watching[player]
    if previous and previous.body == body then return end
    if previous then previous.connection:Disconnect(); previous.diedConnection:Disconnect() end
    -- More health prevents fixture fatalities; damage is still observed as signed negative deltas.
    body.MaxHealth, body.Health = 1000, 1000
    local data: any = {body = body, negative = if previous then previous.negative else 0,
        fixtureNegative = if previous then previous.fixtureNegative else 0, deadNegative = if previous then previous.deadNegative else 0,
        combatNegative = if previous then previous.combatNegative else 0, character = player.Character,
        changes = if previous then previous.changes else {}}
    local last = body.Health
    data.observedHealth = last
    data.diedConnection = body.Died:Connect(function()
        if data.fixtureLife ~= nil and player.Character == data.character
            and data.character:GetAttribute("CombatLife") == data.fixtureLife then
            data.fixtureDeadConfirmed, data.diedAt = true, now()
            print("OverlapFixtureDied", HttpService:JSONEncode({owner = player.UserId, life = data.fixtureLife,
                state = tostring(body:GetState()), health = exact(body.Health), pendingFixtureDeath = exact(data.fixtureDeath)}))
        end
    end)
    data.connection = body.HealthChanged:Connect(function(value)
        local previousHealth, pendingKill = last, data.fixtureDeath
        local delta = value - last; last = value; data.observedHealth = value
        local state = body:GetState()
        local fixtureDead = data.fixtureDeadConfirmed == true and state == Enum.HumanoidStateType.Dead
            and player.Character == data.character and data.character:GetAttribute("CombatLife") == data.fixtureLife
        if delta < 0 then
            data.negative += -delta
            local fixtureAmount = 0
            if value == 0 and data.fixtureDeath then
                fixtureAmount = math.min(-delta, data.fixtureDeath)
                data.fixtureNegative += fixtureAmount
                data.fixtureDeath = nil
            end
            -- Only a confirmed fixture-killed body in the same life and Dead state gets this separate debit.
            -- Any negative event from an alive state, a fresh life, or an unmarked death remains combat damage.
            local deadAmount = if fixtureDead then math.max(0, -delta-fixtureAmount) else 0
            data.deadNegative += deadAmount
            data.combatNegative += math.max(0, -delta-fixtureAmount-deadAmount)
            local change = {at = now(), amount = -delta, fixture = fixtureAmount > 0, state = tostring(state),
                deadConfirmed = data.fixtureDeadConfirmed == true, diedAt = data.diedAt, fixtureLife = data.fixtureLife,
                deadAmount = exact(deadAmount), deadNegative = exact(data.deadNegative),
                owner = player.UserId, previous = exact(previousHealth), value = exact(value), delta = exact(delta),
                propertyHealth = exact(body.Health), fixtureDeath = exact(pendingKill), fixtureAmount = exact(fixtureAmount),
                negative = exact(data.negative), fixtureNegative = exact(data.fixtureNegative), damage = exact(data.combatNegative)}
            table.insert(data.changes, change)
            print("OverlapHealthNegative", HttpService:JSONEncode(change))
        elseif fixtureDead and delta > 0 then
            print("OverlapDeadHealthRise", HttpService:JSONEncode({owner = player.UserId, life = data.fixtureLife,
                state = tostring(state), diedAt = data.diedAt, previous = exact(previousHealth), value = exact(value), delta = exact(delta)}))
        end
    end)
    watching[player] = data
end
local function damage(player: Player): number
    local data = watching[player]
    return data.combatNegative
end
local function kill(player: Player)
    local data = watching[player]
    assert(data and data.body == humanoid(player))
    -- Keep the explicit death debit until HealthChanged delivers it, including deferred signals.
    data.fixtureDeath = data.body.Health
    data.fixtureLife = (player.Character :: Model):GetAttribute("CombatLife")
    print("OverlapFixtureKill", HttpService:JSONEncode({owner = player.UserId, propertyHealth = exact(data.body.Health),
        observedHealth = exact(data.observedHealth), fixtureDeath = exact(data.fixtureDeath), negative = exact(data.negative),
        fixtureNegative = exact(data.fixtureNegative), deadNegative = exact(data.deadNegative), damage = exact(data.combatNegative)}))
    assert(bridge:Invoke("kill", player.UserId), "Fixture kill did not reach the live player")
end
local function settle(player: Player, point: Vector3)
    bridge:Invoke("place", player.UserId, point)
    waitFor(function()
        local inspect = command(player, "inspect")
        return inspect.position ~= nil and (inspect.position - point).Magnitude < 1
    end, 5, "Overlap owner did not receive fixture placement: " .. player.Name)
end
local function active(result: any, owner: Player): any
    assert(result.reply and result.reply.ok and result.state, "Actual Q was not accepted")
    for _, entry in result.state.active do if entry.owner == owner.UserId then return entry end end
    error("Accepted actual Q omitted the owner's active state")
end
local function cooldown(player: Player, ability: string)
    local inspect = command(player, "inspect")
    local state = inspect.states[ability]
    assert(state and type(state.readyAt) == "number", "Missing authoritative cooldown: " .. ability)
    waitFor(function() return now() >= state.readyAt + 0.05 end, 10, "Overlap cooldown did not elapse: " .. ability)
end
local function speed(player: Player, expected: number): boolean return math.abs(humanoid(player).WalkSpeed - expected) < 0.001 end
local function resumed(players: { Player }, matchId: number)
    for _, player in players do
        local c = context(player)
        assert(c.mode == "match" and c.matchId == matchId and not c.frozen, "A caster death unexpectedly paused/reset the battle")
    end
end
local function respawn(player: Player, old: Model)
    local life = old:GetAttribute("CombatLife") :: number
    waitFor(function()
        local character = player.Character
        local current = if character then character:GetAttribute("CombatLife") else nil
        return character ~= nil and character ~= old and type(current) == "number" and current > life
            and character:FindFirstChild("HumanoidRootPart") ~= nil
    end, 13, "Overlap caster did not respawn into a new life")
    waitFor(function() return command(player, "inspect").life == (player.Character :: Model):GetAttribute("CombatLife") end,
        6, "Overlap controller retained the caster's old life")
    watch(player)
end
local ok, problem = xpcall(function()
    waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 4 end,
        75, "Four overlap clients did not initialize; no clients/assertions are omitted")
    local players = Players:GetPlayers()
    table.sort(players, function(a, b) return a.UserId < b.UserId end)
    assert(#players == 4, "Overlap fixture requires all four actual clients")
    -- Actual queue order is alternating by Roster.fromPairOrder, including a late reserved pair.
    command(players[1], "class", "warlock"); command(players[2], "class", "warrior")
    command(players[3], "class", "warrior"); command(players[4], "class", "warlock")
    for _, player in players do command(player, "ready") end
    waitFor(function()
        for _, player in players do local c = context(player); if c.mode ~= "match" or c.frozen then return false end end
        return true
    end, 12, "Four owners did not enter the real active 2v2")
    local warlock, victim, warrior, far = players[1], players[2], players[3], players[4]
    local team, matchId = context(warlock).team, context(warlock).matchId
    assert(context(warrior).team == team and context(victim).team ~= team and context(far).team == context(victim).team,
        "Actual team assignment differs from the ordered queue; no fake team context is permitted")
    for _, player in players do
        assert(context(player).matchId == matchId)
        watch(player)
    end
    local function placeAll()
        cooldown(warlock, "hands"); cooldown(warrior, "heavy")
        for _, player in players do assert(speed(player, 16), "A previous overlap source survived its deadline") end
        settle(warlock, warlockPoint); settle(warrior, warriorPoint)
        settle(victim, victimPoint); settle(far, farPoint)
    end
    local function friendlyWindow(): any
        return {warlock = damage(warlock), warrior = damage(warrior), far = damage(far)}
    end
    local function immune(before: any)
        if damage(warlock) ~= before.warlock or damage(warrior) ~= before.warrior or damage(far) ~= before.far then
            for _, entry in ({{warlock, "warlock", before.warlock}, {warrior, "warrior", before.warrior}, {far, "far", before.far}} :: {{any}}) do
                local player, label, expected = entry[1], entry[2], entry[3]
                local data = watching[player]
                print("OverlapFriendlyMismatch", HttpService:JSONEncode({owner = player.UserId, label = label,
                    before = exact(expected), damage = exact(damage(player)), negative = exact(data.negative),
                    fixtureNegative = exact(data.fixtureNegative), deadNegative = exact(data.deadNegative), pendingFixtureDeath = exact(data.fixtureDeath),
                    state = tostring(data.body:GetState()), diedAt = data.diedAt,
                    propertyHealth = exact(data.body.Health), observedHealth = exact(data.observedHealth), changes = data.changes}))
            end
        end
        assert(damage(warlock) == before.warlock and damage(warrior) == before.warrior,
            "Allied/self hands or heavy strike applied real negative health deltas")
        assert(damage(far) == before.far, "Out-of-range hostile control received damage")
        for _, ally in {warlock, warrior} do
            if humanoid(ally).Health > 0 then assert(speed(ally, 16), "Hands/heavy slowed a caster or its teammate") end
        end
    end
    local function overlap(): (any, any, any)
        placeAll()
        local before = friendlyWindow()
        local area = active(command(warlock, "cast", {ability = "hands", point = center, ok = true}), warlock)
        assert(area.radius == 8 and flat(root(warlock).Position, area.position) < 7.5
            and flat(root(warrior).Position, area.position) < 7.5, "Friendly controls were not inside actual hands")
        waitFor(function() return speed(victim, 10.4) end, 3, "Actual hands did not establish the 0.65 source")
        local oldChanges = #watching[victim].changes
        local heavy = active(command(warrior, "cast", {ability = "heavy", point = victimPoint, ok = true}), warrior)
        assert(heavy.style == "heavy")
        local towardAlly = (root(warlock).Position - root(warrior).Position) * Vector3.new(1, 0, 1)
        assert(towardAlly.Magnitude < 7 and towardAlly.Unit:Dot(heavy.direction) > math.cos(math.rad(50)),
            "Warlock friendly control was not in the warrior's real heavy arc")
        waitFor(function() return speed(victim, 9.6) end, 3, "Combined sources did not choose strongest 0.6")
        local exactHit = false
        for index = oldChanges + 1, #watching[victim].changes do
            local change = watching[victim].changes[index]
            if not change.fixture and change.amount == 25 and change.at >= heavy.hitAt - 0.03 then exactHit = true end
        end
        assert(exactHit and damage(victim) >= 25, "Heavy source was not backed by an actual 25-damage hit")
        assert(now() < area.expiresAt and now() < heavy.hitAt + 2, "Overlap observation missed an active source window")
        immune(before)
        return area, heavy, before
    end
    -- Heavy expires first while both actual/trusted victim positions remain inside hands.
    local area, heavy, before = overlap()
    waitFor(function() return now() >= heavy.hitAt + 2 and speed(victim, 10.4) end,
        3, "Heavy expiry erased the still-active hands source")
    assert(now() < area.expiresAt and flat(root(victim).Position, area.position) < area.radius
        and flat(bridge:Invoke("position", victim.UserId), area.position) < area.radius, "Victim left hands before overlap expiry assertion")
    waitFor(function() return now() > area.expiresAt and speed(victim, 16) end, 3, "Final hands expiry did not restore normal movement")
    immune(before)
    print("OverlapSources", "heavy_expiry_inside_hands", 9.6, 10.4, 16)
    -- A real W exit revokes hands, while the independent heavy lease is still live.
    area, heavy, before = overlap()
    local moved = command(victim, "move", {direction = -Vector3.xAxis, duration = 1.05})
    local actual, trusted = root(victim).Position, bridge:Invoke("position", victim.UserId)
    local function coordinates(value: Vector3?): any return if value then {value.X, value.Y, value.Z} else nil end
    print("OverlapExitObservation", HttpService:JSONEncode({actual = coordinates(actual), trusted = coordinates(trusted),
        actualDistance = flat(actual, area.position), trustedDistance = if trusted then flat(trusted, area.position) else nil,
        start = coordinates(moved.start), finish = coordinates(moved.finish), distance = moved.distance, duration = moved.duration,
        samples = moved.samples, corrections = moved.corrections, lateral = moved.lateral, rewinds = moved.rewinds,
        nowMinusHitAt = now()-heavy.hitAt, heavyRemaining = heavy.hitAt+2-now(), handsRemaining = area.expiresAt-now(),
        actualSpeed = humanoid(victim).WalkSpeed, segments = moved.stableSpeedSegments}))
    assert(moved.samples >= 10 and moved.corrections == 0 and moved.distance > 8.5 and trusted ~= nil and flat(actual, area.position) > 8.25
        and flat(trusted, area.position) > 8.25, "Real W did not take both positions outside hands")
    assert(now() < heavy.hitAt + 2 and speed(victim, 9.6), "Leaving hands erased the still-active heavy source")
    local afterExit = damage(victim)
    waitFor(function() return now() >= heavy.hitAt + 2 and speed(victim, 16) end, 2, "Outside victim retained the expired heavy source")
    assert(now() < area.expiresAt and damage(victim) == afterExit, "Hands damaged the victim after both positions left")
    waitFor(function() return now() > area.expiresAt end, 3, "Exited hands did not finish")
    immune(before)
    print("OverlapSources", "real_W_exit_keeps_heavy", moved.distance, moved.samples)
    -- Death is an individual source cancellation; all other roster members remain active.
    area, heavy, before = overlap()
    local oldWarlock = warlock.Character :: Model
    kill(warlock)
    waitFor(function() return speed(victim, 9.6) end, 1, "Warlock death erased the allied warrior's heavy source")
    resumed({victim, warrior, far}, matchId)
    assert(now() < heavy.hitAt + 2 and humanoid(warlock).Health == 0)
    waitFor(function() return now() >= heavy.hitAt + 2 and speed(victim, 16) end, 3, "Warlock death retained hands or heavy failed to expire")
    assert(now() < area.expiresAt, "Warlock-death cleanup was observed only after the original hands deadline")
    immune(before)
    respawn(warlock, oldWarlock)
    resumed(players, matchId)
    print("OverlapSources", "warlock_death_revokes_only_hands")
    area, heavy, before = overlap()
    local oldWarrior = warrior.Character :: Model
    kill(warrior)
    waitFor(function() return speed(victim, 10.4) end, 1, "Warrior death erased the allied warlock's hands source")
    resumed({victim, warlock, far}, matchId)
    assert(now() < area.expiresAt and humanoid(warrior).Health == 0)
    waitFor(function() return now() > area.expiresAt and speed(victim, 16) end, 5, "Surviving hands source failed to expire")
    immune(before)
    respawn(warrior, oldWarrior)
    resumed(players, matchId)
    print("OverlapSources", "warrior_death_revokes_only_heavy")
    -- Real B is deliberately last: a roster exit pauses the entire 2v2, so all sources must clear.
    area, heavy, before = overlap()
    command(warlock, "exit")
    waitFor(function() return context(victim).frozen and speed(victim, 16) end, 2, "Real roster exit did not pause/cancel all sources")
    assert(context(warrior).frozen and context(far).frozen and context(warlock).mode == "training")
    immune(before)
    waitFor(function()
        for _, player in players do if context(player).mode ~= "training" then return false end end
        return true
    end, 6, "Interrupted 2v2 did not return all owners to training")
    local oldWarlockLife = (warlock.Character :: Model):GetAttribute("CombatLife") :: number
    local oldWarriorLife = (warrior.Character :: Model):GetAttribute("CombatLife") :: number
    command(warlock, "class", "warrior"); command(warrior, "class", "warlock")
    assert(((warlock.Character :: Model):GetAttribute("CombatLife") :: number) > oldWarlockLife
        and ((warrior.Character :: Model):GetAttribute("CombatLife") :: number) > oldWarriorLife,
        "Actual training class reset did not create fresh lives")
    task.wait(0.9)
    for _, player in players do
        local inspect = command(player, "inspect")
        assert(inspect.physicsViolations == 0, "Overlap presentation entered physics: " .. player.Name)
        assert(type(inspect.renderFrames) == "number" and inspect.renderFrames >= 30
            and type(inspect.heartbeatFrames) == "number" and inspect.heartbeatFrames >= 60,
            "Four-client background execution did not provide enough actual simulation/render frames: " .. player.Name)
        assert(inspect.contacts.heavy >= 1 and inspect.visuals.hands.seen > 0 and inspect.visuals.heavy.seen > 0,
            "One of four clients missed actual overlap contact/presentation: " .. player.Name)
        assert(inspect.visuals.hands.live == 0 and inspect.visuals.heavy.live == 0 and speed(player, 16),
            "Pause/class/new-life cleanup retained overlap resources")
        print("OverlapClient", player.UserId, "life", inspect.life, "team", inspect.team,
            "heavyContacts", inspect.contacts.heavy, "handsPeak", inspect.visuals.hands.peak,
            "heavyPeak", inspect.visuals.heavy.peak, "heartbeatFrames", inspect.heartbeatFrames,
            "renderFrames", inspect.renderFrames, "corrections", inspect.corrections,
            "negativeDamage", watching[player].negative, "fixtureKillDamage", watching[player].fixtureNegative,
            "confirmedDeadClamp", watching[player].deadNegative, "aliveCombatDamage", watching[player].combatNegative)
    end
    print("PASS overlap 4 actual clients/2v2: ordered real class+R teams, friendly negative-health controls inside both attacks, hands/heavy strongest composition, heavy expiry inside hands, real W hands exit preserving heavy, separate caster-death cancellation while battle continues, real B global pause, training class/new-life cleanup, all-four contact/art visibility and nonphysics resources")
end, debug.traceback)
for _, data in watching do data.connection:Disconnect(); data.diedConnection:Disconnect() end
for _, connection in connections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ok = ok, error = if ok then nil else tostring(problem)})
