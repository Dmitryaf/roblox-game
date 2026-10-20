--!strict
-- Two real clients: approved Q/LMB/F combination, authority and its existing cleanup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local control = ReplicatedStorage:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local arrow = ReplicatedStorage:WaitForChild("ArrowRemote", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local loss: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local sequence, transferRequests, teleportRequests = 0, 0, 0
local failure: string? = nil
local probe: any = nil
local caster: Player
local victim: Player
local wall: Part? = nil
local function now(): number return workspace:GetServerTimeNow() end
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function human(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function combat(player: Player): any return bridge:Invoke("combat", player.UserId) end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function owned(state: any, player: Player): any?
    for _, item in state.active do if item.owner == player.UserId then return item end end
    return nil
end
local function corrections(player: Player): number return ((player.Character :: Model):GetAttribute("CombatMovementCorrections") or 0) :: number end
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat
        if failure then error(failure) end
        if predicate() then return end
        task.wait(0.015)
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
    waitFor(function() return reports[id] ~= nil end, 10, "Transfer client command timed out: " .. id)
    local delivery = reports[id]; reports[id] = nil
    assert(delivery.player == player and delivery.report.ok, delivery.report.error)
    return delivery.report.data
end
local function command(player: Player, action: string, data: any?): any return finish(player, begin(player, action, data)) end
local function cast(player: Player, ability: string, point: Vector3?, accepted: boolean?): any
    return command(player, "cast", { ability = ability, point = point, ok = accepted ~= false })
end
local function place(player: Player, position: Vector3)
    bridge:Invoke("place", player.UserId, position)
    waitFor(function() return (command(player, "inspect").position - position).Magnitude < 1 end, 4, "Transfer placement did not reach owner")
    task.wait(0.1)
end
local function watch(player: Player)
    local humanoid = human(player); humanoid.MaxHealth, humanoid.Health = 1000, 1000
    loss[player] = 0; local previous = humanoid.Health
    table.insert(connections, humanoid.HealthChanged:Connect(function(current)
        if current < previous then loss[player] += previous - current end
        previous = current
    end))
end
local function resetPair()
    local state = combat(caster)
    waitFor(function() return now() >= math.max(state.hands.readyAt, state.arrow.readyAt) + 0.1 end, 10, "Transfer cooldown did not expire")
    place(caster, Vector3.new(0, 3, 40)); place(victim, Vector3.new(4, 3, 40))
end
local function startCombo(): (any, any)
    local hands = owned(cast(caster, "hands", Vector3.new(0, 0, 40)).state, caster)
    assert(hands, "Actual Q omitted its own area")
    waitFor(function() local area = owned(combat(caster).hands, caster); return area ~= nil and area.kind == "active" end,
        3, "Actual Q area did not become active")
    local shot = owned(cast(caster, "arrow", Vector3.new(0, 1, -30)).state, caster)
    assert(shot, "Actual LMB omitted its own arrow")
    waitFor(function() return now() >= shot.launchAt + 0.04 end, 2, "Transfer arrow did not launch")
    return hands, shot
end
table.insert(connections, arrow.OnServerEvent:Connect(function(player: Player, request: any)
    if player ~= caster or type(request) ~= "table" then return end
    if request.action == "teleport" then teleportRequests += 1 end
    if request.action ~= "transfer" then return end
    transferRequests += 1
    local current = probe
    if not current then return end
    task.defer(function()
        local ok, problem = xpcall(function()
            local area = owned(combat(caster).hands, caster)
            assert(area and area.kind == "transferring", "Actual F did not establish the warning phase")
            current.area, current.loss, current.samples = area, loss[victim], 0
            current.firstAt = now()
            assert(math.abs(area.transferReadyAt - area.transferStartedAt - 0.35) < 0.001)
            while now() < area.transferReadyAt - 0.025 do
                local live = owned(combat(caster).hands, caster)
                assert(live and live.kind == "transferring" and live.areaId == current.before.areaId)
                assert(loss[victim] == current.loss and human(victim).WalkSpeed == 16,
                    "Hands applied damage or slow during the inactive transfer warning")
                current.samples += 1
                if not current.moved and now() >= area.transferStartedAt + 0.1 then
                    current.oldChecked = true
                    bridge:Invoke("place", victim.UserId, area.position + Vector3.yAxis * 3)
                    current.moved = true
                end
                if current.moved then
                    assert((root(victim).Position - (area.position + Vector3.yAxis * 3)).Magnitude < 1,
                        "Warning target did not occupy the authoritative new area")
                    current.newChecked = true
                end
                RunService.Heartbeat:Wait()
            end
            current.lastAt, current.done = now(), true
        end, debug.traceback)
        if not ok then failure = tostring(problem) end
    end)
end))
local ok, problem = xpcall(function()
    waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end, 70, "Two transfer clients did not initialize")
    local players = Players:GetPlayers(); table.sort(players, function(a, b) return a.UserId < b.UserId end)
    caster, victim = players[1], players[2]
    command(caster, "class", "warrior"); command(caster, "class", "warlock"); command(victim, "class", "warrior")
    local r1, r2 = begin(caster, "ready"), begin(victim, "ready"); finish(caster, r1); finish(victim, r2)
    waitFor(function() return context(caster).mode == "match" and not context(caster).frozen end, 8, "Transfer 1v1 did not activate")
    assert(context(caster).team ~= context(victim).team)
    for _, player in players do watch(player) end
    resetPair()
    local baselineCaster, baselineVictim = corrections(caster), corrections(victim)
    local area, shot = startCombo()
    probe = { before = area }
    local transferred = cast(caster, "transfer", nil)
    waitFor(function() return probe.done == true end, 2, "Server warning observation did not complete")
    local moved = owned(combat(caster).hands, caster)
    assert(moved and moved.areaId == area.areaId and moved.position ~= area.position and moved.expiresAt == area.expiresAt
        and moved.startedAt == area.startedAt and moved.readyAt == area.readyAt, "Transfer replaced or renewed the original area")
    assert(probe.oldChecked and probe.newChecked and probe.samples >= 5 and probe.lastAt - probe.firstAt >= 0.2,
        "Transfer did not observe both old/new positions through its warning")
    assert(owned(transferred.state, caster) == nil, "F did not consume the flying arrow")
    waitFor(function() return math.abs(human(victim).WalkSpeed - 10.4) < 0.001 and loss[victim] >= probe.loss + 3 end,
        2, "Transferred active hands did not resume their ordinary slow/DoT")
    local beforePosition, beforeRequests = root(caster).Position, teleportRequests
    command(caster, "tap", { ability = "teleport" }); command(caster, "tap", { ability = "transfer" }); task.wait(0.2)
    assert(teleportRequests == beforeRequests and transferRequests == 1 and (root(caster).Position - beforePosition).Magnitude < 0.5,
        "Consumed arrow was still usable by E or repeated F")
    assert(shot.expiresAt > shot.launchAt and moved.expiresAt == area.expiresAt)
    print("TransferWarning", "samples", probe.samples, "observed", probe.lastAt - probe.firstAt,
        "oldTTL", area.expiresAt, "newTTL", moved.expiresAt, "negativeLoss", loss[victim])
    waitFor(function() return now() >= area.expiresAt + 0.1 end, 5, "Original transferred area TTL did not finish")
    assert(owned(combat(caster).hands, caster) == nil and human(victim).WalkSpeed == 16)
    local endedLoss = loss[victim]; task.wait(0.6); assert(loss[victim] == endedLoss, "Expired transferred hands still damaged target")
    probe = nil

    -- A real side wall intersects the area footprint while leaving the projectile's
    -- center lane clear. The wall rejection therefore must preserve the live arrow.
    resetPair(); local wallArea, wallShot = startCombo()
    local obstacle = Instance.new("Part"); wall = obstacle
    obstacle.Name, obstacle.Size, obstacle.Position = "TransferFootprintWall", Vector3.new(2, 9, 90), Vector3.new(8, 4.5, 10)
    obstacle.Anchored, obstacle.CanCollide, obstacle.CanQuery, obstacle.CanTouch = true, true, true, false; obstacle.Parent = workspace
    local refused = cast(caster, "transfer", nil, false)
    local untouched = owned(combat(caster).hands, caster)
    assert(refused.reply.reason == "invalid_target" and owned(refused.state, caster) ~= nil and untouched
        and untouched.areaId == wallArea.areaId and untouched.position == wallArea.position and untouched.expiresAt == wallArea.expiresAt,
        "World footprint wall refusal consumed resources or moved hands")
    assert(combat(caster).hands.readyAt == wallArea.readyAt and math.abs(combat(caster).arrow.readyAt - wallShot.startedAt - 3.5) < 0.001)
    obstacle:Destroy(); wall = nil
    print("TransferGroundWall", "reason", refused.reply.reason, "liveArrow", true, "area", untouched.areaId)

    resetPair(); local rangeArea, rangeShot = startCombo()
    waitFor(function()
        local active = owned(combat(caster).arrow, caster)
        return active ~= nil and active.position ~= nil and (active.position - root(caster).Position).Magnitude > 32
    end, 2, "Real arrow did not travel past the owner placement range")
    local far = cast(caster, "transfer", nil, false)
    local kept = owned(combat(caster).hands, caster)
    assert(far.reply.reason == "out_of_range" and owned(far.state, caster) ~= nil and kept
        and kept.areaId == rangeArea.areaId and kept.position == rangeArea.position and kept.expiresAt == rangeArea.expiresAt,
        "Owner range refusal consumed resources or renewed hands")
    assert(combat(caster).hands.readyAt == rangeArea.readyAt and math.abs(combat(caster).arrow.readyAt - rangeShot.startedAt - 3.5) < 0.001)
    print("TransferRange", "reason", far.reply.reason, "arrowStillFlying", owned(far.state, caster) ~= nil)

    resetPair(); startCombo(); assert(cast(caster, "transfer", nil).reply.ok)
    assert(corrections(caster) == baselineCaster and corrections(victim) == baselineVictim,
        "Transfer sequences introduced authoritative movement corrections")
    local deadBody = caster.Character
    bridge:Invoke("kill", caster.UserId)
    waitFor(function() return owned(combat(caster).hands, caster) == nil and owned(combat(caster).arrow, caster) == nil end,
        1, "Caster death retained transferred area or arrow")
    assert(human(victim).WalkSpeed == 16, "Caster death retained a transferred slow contribution")
    waitFor(function()
        local character = caster.Character
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        return character ~= nil and character ~= deadBody and humanoid ~= nil and humanoid.Health > 0
    end, 9, "Transfer caster did not respawn")
    watch(caster); resetPair(); startCombo(); assert(cast(caster, "transfer", nil).reply.ok)
    command(victim, "exit")
    waitFor(function() return context(caster).frozen end, 2, "Opponent exit did not pause the transfer match")
    assert(owned(combat(caster).hands, caster) == nil and owned(combat(caster).arrow, caster) == nil
        and human(caster).WalkSpeed == 16, "Real match pause retained transferred state or slow")
    for _, player in players do
        local data = command(player, "inspect")
        assert(data.physicsViolations == 0, "Transfer VFX entered movement/ray physics")
        if player == victim then assert(corrections(player) == baselineVictim) end
    end
    print("PASS transfer: two live clients actual class/R/Q/LMB/F, same area/TTL/cooldowns, .35 inactive old/new warning, no catch-up DoT, consumed E/F, real footprint wall/range refusal, death/respawn/pause cleanup, no VFX physics")
end, debug.traceback)
if wall then wall:Destroy() end
for _, connection in connections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
