--!strict
-- Comparison fixture only: real input, real production damage, no synthetic hit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local control = ReplicatedStorage:WaitForChild("LivingReviewControl") :: RemoteEvent
local bridge = game:GetService("ServerStorage"):WaitForChild("MatchTestBridge", 30) :: BindableFunction
local token = (ReplicatedStorage:WaitForChild("StudioTestToken") :: StringValue).Value
assert(game:GetService("RunService"):IsStudio() and token:match("^living%-review%-"))
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local sequence, advance, scene = 0, false, "initializing"
local connections: { RBXScriptConnection } = {}
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
    if kind == "ready" then ready[player] = true
    elseif kind == "report" then reports[id] = { player = player, result = data }
    elseif kind == "next" and not advance then advance = true end
end))
local function waitFor(check: () -> boolean, limit: number, message: string)
    local untilAt = os.clock() + limit
    repeat if check() then return end; task.wait(0.03) until os.clock() >= untilAt
    error(message)
end
local function command(player: Player, action: string, data: any?): any
    sequence += 1; local id = sequence
    control:FireClient(player, id, action, data)
    waitFor(function() return reports[id] ~= nil end, 12, "Review input timeout: " .. action)
    local response = reports[id]; reports[id] = nil
    assert(response.player == player and response.result.ok, response.result.error)
    return response.result.data
end
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function human(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function place(player: Player, at: Vector3)
    bridge:Invoke("place", player.UserId, at)
    waitFor(function() return (command(player, "inspect").position - at).Magnitude < 1 end, 4, "Review placement not replicated")
end
local ok, problem = xpcall(function()
    waitFor(function() local n = 0; for _ in ready do n += 1 end; return n == 2 end, 60, "Two review clients required")
    local players = Players:GetPlayers(); table.sort(players, function(a, b) return a.UserId < b.UserId end)
    local warrior, warlock = players[1], players[2]
    command(warrior, "class", "warrior"); command(warlock, "class", "warlock")
    command(warrior, "ready"); command(warlock, "ready")
    waitFor(function()
        return bridge:Invoke("context", warrior.UserId).mode == "match"
            and not bridge:Invoke("context", warrior.UserId).frozen
    end, 12, "Review match did not start")
    for _, player in players do
        human(player).MaxHealth, human(player).Health = 1000, 1000
        local before = human(player).Health
        table.insert(connections, human(player).HealthChanged:Connect(function(health)
            if health < before then print(token, "REAL_DAMAGE", scene, player.UserId, "at", workspace:GetServerTimeNow(), "loss", before - health) end
            before = health
        end))
    end
    local cases = {
        { label = "walk-stop-turn", ability = "move" },
        { label = "sword-hit", ability = "melee" }, { label = "sword-miss", ability = "melee", miss = true },
        { label = "heavy-hit", ability = "heavy" }, { label = "heavy-miss", ability = "heavy", miss = true },
        { label = "arrow-hit", ability = "arrow" }, { label = "arrow-miss", ability = "arrow", miss = true },
    }
    for _, effects in { true, false } do
      for _, case in cases do
        scene, advance = case.label .. (if effects then "-on" else "-off"), false
        local arrow = case.ability == "arrow"
        local attacker, target = if arrow then warlock else warrior, if arrow then warrior else warlock
        place(attacker, Vector3.new(-20, 3, 30)); place(target, Vector3.new(-20, 3, if arrow then 6 else 24))
        for _, player in players do control:FireClient(player, 0, "scene", { label = scene, effects = effects, attacker = attacker.UserId, target = target.UserId }) end
        print(token, "SCENE_READY", scene, "attacker", attacker.UserId, "target", target.UserId)
        waitFor(function() return advance end, 1800, "Review awaiting N / next: " .. scene)
        if case.ability == "move" then
            command(attacker, "move", { direction = Vector3.xAxis, duration = 0.8 })
            task.wait(0.5); command(attacker, "move", { direction = -Vector3.zAxis, duration = 0.8 })
        else
            local state = bridge:Invoke("combat", attacker.UserId)[if arrow then "arrow" else case.ability]
            waitFor(function() return workspace:GetServerTimeNow() > state.readyAt + 0.1 end, 10, "Review cooldown")
            local point = if case.miss then root(attacker).Position + Vector3.xAxis * 30 else root(target).Position
            local result = command(attacker, "cast", { ability = case.ability, point = point, ok = true })
            print(token, "REAL_INPUT", scene, result.sentAt, result.repliedAt)
            task.wait(if arrow then 2.8 else 1.4)
        end
      end
    end
    for _, player in players do control:FireClient(player, 0, "scene", { label = "baseline complete; no art verdict", attacker = warrior.UserId, target = warlock.UserId }) end
    print(token, "BASELINE_SEQUENCE_COMPLETE")
end, debug.traceback)
if not ok then
    warn(token, "BASELINE_FAILURE", problem)
    for _, player in Players:GetPlayers() do
        control:FireClient(player, 0, "failure", { label = scene })
    end
end
script.Destroying:Connect(function() for _, c in connections do c:Disconnect() end end)
