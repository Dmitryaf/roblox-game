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
        place(caster, Vector3.new(-40, 3, 30)); place(warrior, Vector3.new(-40, 3, 0))
        local before, enemyBefore = loss[caster], loss[warrior]
        local shot = own(cast(caster, "arrow", Vector3.new(-40, 4, 0)).state, caster)
        assert(shot, "LMB did not prepare an arrow")
        local swing = begin(warrior, "cast", {ability = "melee", point = Vector3.new(-40, 4, 30), at = shot.launchAt + 0.08, ok = true})
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
    local slot = Vector3.new(22, 0, 28)
    local function raise()
        waitFor(function() return now() > combat(caster).hands.readyAt and now() > combat(caster).arrow.readyAt end, 10, "Cover cooldown")
        place(caster, slot + Vector3.new(0, 3, 12)); place(warrior, slot + Vector3.new(0, 3, -6))
        local area = own(cast(caster, "hands", slot).state, caster)
        assert(area and area.kind == "preparing")
        waitFor(function() local v = own(combat(caster).hands, caster); return v ~= nil and v.kind == "active" end, 2, "Q did not raise cover")
        return area
    end
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
    command(warrior, "exit")
    waitFor(function() return context(caster).frozen end, 2, "Exit did not pause duel")
    assert(own(combat(caster).hands, caster) == nil and own(combat(caster).arrow, caster) == nil)
    for _, p in players do assert(command(p, "inspect").physicsViolations == 0) end
    print("LIVING_MAGIC_PASS: real two-client class/R/LMB/Q/E; redirect damage/teleport; cover sword/heavy/arrow; no DoT/slow; pause cleanup")
end, debug.traceback)
connection:Disconnect(); requests:Disconnect()
for _, c in healthConnections do c:Disconnect() end
game:GetService("StudioTestService"):EndTest({ok = ok, error = if ok then nil else tostring(problem)})
