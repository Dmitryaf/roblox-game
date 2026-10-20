--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local control = ReplicatedStorage:WaitForChild("HandsTestControl") :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local failed: string? = nil
local sequence = 0
local connection = control.OnServerEvent:Connect(function(player, kind, id, report)
    if kind == "ready" then ready[player] = true
    elseif kind == "failure" then failed = tostring(id)
    elseif kind == "report" then reports[id] = { player = player, report = report } end
end)
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat
        if failed then error(failed) end
        if predicate() then return end
        task.wait(0.025)
    until os.clock() >= deadline
    error(message)
end
local function command(player: Player, action: string, data: any?): any
    sequence += 1
    local id = sequence
    control:FireClient(player, id, action, data)
    waitFor(function() return reports[id] ~= nil end, 8, "Client command failed: " .. action)
    local delivery = reports[id]; reports[id] = nil
    assert(delivery.player == player and delivery.report.ok, delivery.report.error)
    return delivery.report.data
end
local function health(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function place(player: Player, at: Vector3) bridge:Invoke("place", player.UserId, at) end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function settled(player: Player, point: Vector3)
    waitFor(function()
        local data = command(player, "inspect")
        return data.position ~= nil and (data.position - point).Magnitude < 1
    end, 4, "Client did not receive test placement")
end
local ok, problem = xpcall(function()
    waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end, 60, "Hands clients did not initialize")
    local players = Players:GetPlayers()
    table.sort(players, function(a, b) return a.UserId < b.UserId end)
    local caster, target = players[1], players[2]
    command(caster, "ready"); command(target, "ready")
    waitFor(function() return context(caster).mode == "match" and not context(caster).frozen end, 8, "Match did not become active")
    place(caster, Vector3.new(0, 3, -35)); place(target, Vector3.new(3, 3, -30))
    settled(caster, Vector3.new(0, 3, -35)); settled(target, Vector3.new(3, 3, -30))
    local center = Vector3.new(2, 0, -30)
    command(caster, "cast", { point = Vector3.new(70, 0, -30), ok = false, reason = "out_of_range" })
    assert(health(target).Health == 100 and health(target).WalkSpeed == 16, "Rejected placement affected opponent")
    local accepted = command(caster, "cast", { point = center, ok = true })
    assert(health(target).Health == 100, "Hands damaged before preparation completed")
    waitFor(function() return health(target).WalkSpeed < 16 end, 4, "Active hands did not slow real opponent")
    assert(math.abs(health(target).WalkSpeed - 10.4) < 0.001, "Incorrect real movement multiplier")
    waitFor(function() return health(target).Health < 100 end, 3, "Hands did not deal periodic damage")
    assert(health(target).Health >= 94, "Hands dealt an unbounded first damage burst")
    assert(health(caster).Health == 100 and health(caster).WalkSpeed == 16, "Hands affected their caster")
    local visible = command(target, "inspect")
    assert(visible.observed and visible.count > 60 and visible.hud, "Observer missed full hands presentation/HUD")
    place(target, Vector3.new(23, 3, -30))
    waitFor(function() return health(target).WalkSpeed == 16 end, 2, "Leaving hands did not restore speed")
    local afterExit = health(target).Health
    task.wait(0.65)
    assert(health(target).Health == afterExit, "Area damaged a target that left")
    waitFor(function() return workspace:GetServerTimeNow() >= accepted.state.active[1].expiresAt + 0.25 end, 6, "Hands did not expire")
    local cleared = command(target, "inspect")
    assert(cleared.children == 0 and health(target).WalkSpeed == 16, "Expired hands leaked visuals or slow")
    waitFor(function() return workspace:GetServerTimeNow() >= accepted.state.readyAt + 0.05 end, 8, "Cooldown did not elapse")
    local oldCharacter = caster.Character
    local oldLife = (oldCharacter :: Model):GetAttribute("CombatLife")
    command(caster, "cast", { point = center, ok = true })
    health(caster).Health = 0
    waitFor(function()
        local current = caster.Character
        return current ~= nil and current ~= oldCharacter and current:GetAttribute("CombatLife") ~= oldLife
    end, 12, "Caster did not respawn with new life")
    task.wait(0.5)
    assert(health(target).WalkSpeed == 16, "Death retained a slow contribution")
    command(caster, "cast", { point = Vector3.new(0, 0, -90), ok = false, reason = "spawn_protected" })
    place(caster, Vector3.new(0, 3, -35)); place(target, Vector3.new(3, 3, -30))
    settled(caster, Vector3.new(0, 3, -35)); settled(target, Vector3.new(3, 3, -30))
    local renewed = command(caster, "cast", { point = center, ok = true })
    local renewedInfo = game:GetService("HttpService"):JSONEncode(renewed.state.active)
    print("HandsRenewedArea", renewedInfo)
    print("HandsRenewedBodies", bridge:Invoke("position", caster.UserId), bridge:Invoke("position", target.UserId),
        game:GetService("HttpService"):JSONEncode(context(caster)), game:GetService("HttpService"):JSONEncode(context(target)))
    waitFor(function() return health(target).WalkSpeed < 16 end, 4, "Second life could not create an area; areas=" .. renewedInfo
        .. " caster=" .. tostring(bridge:Invoke("position", caster.UserId)) .. " target=" .. tostring(bridge:Invoke("position", target.UserId))
        .. " health=" .. tostring(health(target).Health))
    command(caster, "exit")
    waitFor(function() return context(target).frozen and health(target).WalkSpeed == 16 end, 3, "Match pause did not cancel hands and restore speed")
    task.wait(0.4)
    assert(command(target, "inspect").children == 0, "Pause retained hands visuals")
    print("PASS hands: real Q/world aim, range rejection without cooldown, warning, opponent slow/DoT, self immunity, exit/expiry restore, observer/query isolation, death/new life, pad protection and pause cleanup")
end, debug.traceback)
connection:Disconnect()
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
