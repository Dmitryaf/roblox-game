--!strict
-- Isolated, repeatable examples using unchanged rules, real clients and genuine input.
local Players, RS, SS = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local Studio = game:GetService("StudioTestService")
local control = RS:WaitForChild("LivingEpisodeControl") :: RemoteEvent
local bridge = SS:WaitForChild("MatchTestBridge", 30) :: BindableFunction
local token = (RS:WaitForChild("StudioTestToken") :: StringValue).Value
assert(game:GetService("RunService"):IsStudio() and token:match("^living%-episode%-"))
local automatic = SS:GetAttribute("LivingEpisodeAuto") == true
local ready: { [Player]: boolean }, reports: { [number]: any } = {}, {}
local sequence, requested, busy = 0, false, false
local connections: { RBXScriptConnection } = {}
local healthConnections: { RBXScriptConnection } = {}
local lost: { [Player]: number } = {}
local decor: Folder? = nil
local function now(): number return workspace:GetServerTimeNow() end
local function human(p: Player): Humanoid return (p.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function root(p: Player): BasePart return (p.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function combat(p: Player): any return bridge:Invoke("combat", p.UserId) end
local function own(state: any, p: Player): any
    for _, item in state.active do if item.owner == p.UserId then return item end end
    return nil
end
local function waitFor(check: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat if check() then return end; task.wait(0.02) until os.clock() >= deadline
    error(message)
end
table.insert(connections, control.OnServerEvent:Connect(function(p, kind, id, data)
    if kind == "ready" then ready[p] = true
    elseif kind == "report" then reports[id] = { player = p, result = data }
    elseif kind == "next" and not busy then requested = true end
end))
local function begin(p: Player, action: string, data: any?): number
    sequence += 1; control:FireClient(p, sequence, action, data); return sequence
end
local function finish(p: Player, id: number): any
    waitFor(function() return reports[id] ~= nil end, 12, "Episode command timeout " .. id)
    local report = reports[id]; reports[id] = nil
    assert(report.player == p and report.result.ok, tostring(report.result.error))
    return report.result.data
end
local function command(p: Player, action: string, data: any?): any return finish(p, begin(p, action, data)) end
local function caption(text: string, active: boolean?, free: boolean?, sample: boolean?)
    control:FireAllClients(0, "caption", { text = text, active = active, free = free, sample = sample })
    print(token, "EPISODE_SCENE", text)
end
local function place(p: Player, point: Vector3)
    bridge:Invoke("place", p.UserId, point)
    waitFor(function() return (command(p, "inspect").position - point).Magnitude < 1 end, 5, "Episode placement not replicated")
    task.wait(0.12)
end
local function view(p: Player, point: Vector3): CFrame
    local body = root(p).Position
    local direction = (point - body) * Vector3.new(1, 0, 1)
    if direction.Magnitude < 0.1 then direction = -Vector3.zAxis end
    return CFrame.lookAt(body - direction.Unit * 15 + Vector3.new(5, 7, 0), point)
end
local function cast(p: Player, ability: string, point: Vector3?, at: number?): any
    return command(p, "cast", { ability = ability, point = point, at = at, ok = true,
        viewFrame = if point then view(p, point) else nil })
end
local function cool(p: Player, ability: string)
    waitFor(function() return now() > combat(p)[ability].readyAt + 0.1 end, 12, "Episode cooldown " .. ability)
end
local function scenery()
    -- Dressing only; all routes and combat queries remain exactly the production arena.
    local loadModule = require :: any
    local Stone = loadModule((script.Parent:WaitForChild("Game") :: Instance):WaitForChild("adapters"):WaitForChild("world"):WaitForChild("ShrineStonework") :: ModuleScript)
    local folder = Instance.new("Folder"); folder.Name, folder.Parent = "LivingEpisodeArch", workspace
    decor = folder
    for _, side in { -1, 1 } do
        Stone.pillar(folder, Vector3.new(22 + side * 12, 0, 35), if side == -1 then 13 else 10, 3.5, true)
    end
    for index = 0, 9 do
        if index == 4 or index == 5 or index == 6 then continue end
        local angle = math.pi * index / 9
        local position = Vector3.new(22 + math.cos(angle) * 12, 13 + math.sin(angle) * 9, 35)
        Stone.block(folder, "BrokenArchStone", Vector3.new(3.3, 3.5, 3.5),
            CFrame.new(position) * CFrame.Angles(0.02 * index, 0, angle), Stone.colors.stone)
    end
    for _, item in folder:GetDescendants() do
        if item:IsA("BasePart") then assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch) end
    end
end
local ok, problem = xpcall(function()
    waitFor(function() local n = 0; for _ in ready do n += 1 end; return n == 2 end, 90, "Episode requires two clients")
    local players = Players:GetPlayers(); table.sort(players, function(a, b) return a.UserId < b.UserId end)
    local caster, warrior = players[1], players[2]
    command(caster, "class", "warlock"); command(warrior, "class", "warrior")
    local a, b = begin(caster, "ready"), begin(warrior, "ready"); finish(caster, a); finish(warrior, b)
    waitFor(function() local context = bridge:Invoke("context", caster.UserId); return context.mode == "match" and not context.frozen end, 12, "Episode match did not start")
    scenery()
    local function watchDamage()
        for _, connection in healthConnections do connection:Disconnect() end
        table.clear(healthConnections)
        for _, p in players do
            lost[p] = 0
            local previous = human(p).Health
            table.insert(healthConnections, human(p).HealthChanged:Connect(function(health)
                lost[p] += math.max(0, previous - health); previous = health
            end))
        end
    end
    local site = Vector3.new(22, 0, 28)
    local function startPositions()
        place(caster, site + Vector3.new(0, 3, 30)); place(warrior, site + Vector3.new(0, 3, 0))
    end
    local function redirect(teleport: boolean)
        cool(caster, "arrow"); cool(warrior, "melee"); startPositions()
        local damage, warriorDamage = lost[caster], lost[warrior]
        local start = now() + 1
        -- Keep the outgoing direction inside the sword's readable front sector.
        -- The diagonal left route also stays clear of the solid north-east pillar.
        local target = if teleport then site + Vector3.new(-28, 4, 28) else root(caster).Position
        local shotId = begin(caster, "cast", {ability = "arrow", point = site + Vector3.yAxis * 4,
            at = start, ok = true, viewFrame = view(caster, site + Vector3.yAxis * 4)})
        local swingId = begin(warrior, "cast", {ability = "melee", point = target,
            at = start + 0.78, ok = true, viewFrame = view(warrior, target)})
        local shot = own(finish(caster, shotId).state, caster)
        assert(shot, "Episode arrow absent")
        waitFor(function() local arrow = own(combat(caster).arrow, caster); return arrow ~= nil and arrow.redirected end, 3, "Episode interception failed")
        finish(warrior, swingId)
        if teleport then
            waitFor(function() local arrow = own(combat(caster).arrow, caster); return arrow ~= nil and arrow.position.X <= site.X - 10 end, 1, "Side path not clear for E")
            cast(caster, "teleport")
            assert(own(combat(caster).arrow, caster) == nil and lost[caster] == damage and lost[warrior] == warriorDamage,
                "Flank teleport retained arrow or caused damage")
            assert(root(caster).Position.X < site.X - 6, "E did not create a side position")
        else
            waitFor(function() return lost[caster] == damage + 25 end, 3, "Returned arrow did not damage creator")
            assert(lost[warrior] == warriorDamage)
        end
        print(token, "EPISODE_REDIRECT_PASS", if teleport then "side-path teleport; zero damage" else "return hit; 25 damage")
    end
    local function raise()
        cool(caster, "hands")
        local area = own(cast(caster, "hands", site).state, caster)
        assert(area and area.kind == "preparing")
        waitFor(function() local cover = own(combat(caster).hands, caster); return cover ~= nil and cover.kind == "active" end, 3, "Episode cover absent")
    end
    local function free()
        caption("ТВОЙ ХОД · ЛКМ: атака · E: перемещение / рывок · Q: плита / тяжёлый удар · N: показать варианты", true, true, false)
    end
    startPositions()
    if not automatic then
        free(); waitFor(function() return requested end, 1800, "Episode session finished")
    end
    repeat
        requested, busy = false, true
        -- A requested replay resets the comparison situation after ordinary
        -- actions have settled; it never reuses an old projectile or cast.
        caption("Повтор эпизода · возвращаем участников к арке")
        waitFor(function()
            for _, p in players do
                local h = if p.Character then p.Character:FindFirstChildOfClass("Humanoid") else nil
                local context = bridge:Invoke("context", p.UserId)
                if not h or h.Health <= 0 or context.mode ~= "match" or context.frozen then return false end
            end
            return true
        end, 12, "Wait for both players to respawn and return to the match before replay")
        waitFor(function()
            for _, p in players do
                for _, state in combat(p) do if #state.active > 0 then return false end end
            end
            return true
        end, 12, "Existing actions did not finish before episode replay")
        for _, p in players do human(p).Health = human(p).MaxHealth end
        watchDamage()
        caption("1 / 4 · Перехват меняет направление и источник урона. Маг по-прежнему может использовать E.", false, false, true)
        task.wait(2)
        for _, p in players do
            local ui = command(p, "reviewUi")
            assert(ui.showcasing and ui.hidden >= 3 and not ui.matchHudEnabled, "Ordinary HUD obscured the episode")
        end
        redirect(false); task.wait(1)
        caption("2 / 4 · Перехват вбок → E мага → плита → тяжёлый удар воина. Смотри на новый путь стрелы.")
        task.wait(2); redirect(true)
        command(warrior, "move", {direction = -Vector3.zAxis, duration = 0.42})
        -- E samples a live projectile, so render/network scheduling changes the
        -- exact flank endpoint. Approach through genuine movement before Q;
        -- preserve the production range check instead of widening the ability.
        local approach = (site - root(caster).Position) * Vector3.new(1, 0, 1)
        if approach.Magnitude > 22 then
            local movement = command(caster, "move", {direction = approach.Unit, duration = (approach.Magnitude - 22) / 16 + 0.1})
            assert(movement.corrections == 0 and movement.rewinds == 0, "Flank approach was corrected")
        end
        raise(); cool(warrior, "heavy"); cast(warrior, "heavy", site + Vector3.yAxis * 4)
        waitFor(function() return own(combat(caster).hands, caster) == nil end, 3, "Episode heavy did not break slab")
        print(token, "EPISODE_CHAIN_PASS: redirect flank E raise heavy break")
        task.wait(1)
        caption("3 / 4 · Плиту можно обойти. Обход сохраняет тяжёлый удар, но требует движения вокруг края.")
        cool(caster, "hands"); place(caster, site + Vector3.new(0, 3, 12)); place(warrior, site + Vector3.new(0, 3, -6)); raise()
        local damage = lost[caster] + lost[warrior]
        for _, leg in { {direction = Vector3.xAxis, duration = 0.65}, {direction = Vector3.zAxis, duration = 0.85}, {direction = -Vector3.xAxis, duration = 0.65} } do
            local movement = command(warrior, "move", leg)
            assert(movement.corrections == 0 and movement.rewinds == 0, "Bypass movement was corrected")
        end
        assert(root(warrior).Position.Z > site.Z + 4 and own(combat(caster).hands, caster), "Bypass did not reach the far side of live slab")
        assert(lost[caster] + lost[warrior] == damage, "Bypass caused damage")
        print(token, "EPISODE_BYPASS_PASS: live cover preserved; no damage; no corrections")
        caption("4 / 4 · Плита останавливает и стрелу мага. Разрушение расходует снаряд: за камнем нет сквозного попадания.")
        cool(caster, "hands"); place(caster, site + Vector3.new(0, 3, 12)); place(warrior, site + Vector3.new(0, 3, -6)); raise()
        cool(caster, "arrow"); damage = lost[warrior]; cast(caster, "arrow", root(warrior).Position)
        waitFor(function() return own(combat(caster).hands, caster) == nil and own(combat(caster).arrow, caster) == nil end, 3, "Episode arrow did not finish at cover")
        assert(lost[warrior] == damage, "Episode arrow damaged through slab")
        print(token, "EPISODE_COVER_ARROW_PASS: arrow spent; target protected")
        task.wait(1.5)
        for _, p in players do
            local metrics = command(p, "metrics")
            assert(metrics.frames > 30 and metrics.inspect.physicsViolations == 0)
            print(token, "EPISODE_CLIENT_METRICS", p.UserId, game:GetService("HttpService"):JSONEncode(metrics))
        end
        print(token, "EPISODE_COMPLETE: four alternatives, genuine input; no balance/art/interest verdict")
        busy = false
        if automatic then
            free(); task.wait(0.3)
            for _, p in players do
                local ui = command(p, "reviewUi")
                assert(not ui.showcasing and ui.hidden == 0 and ui.matchHudEnabled and ui.customCamera,
                    "Episode did not restore normal HUD/camera after examples")
            end
            print(token, "EPISODE_FREEPLAY_RESTORE_PASS")
            Studio:EndTest({ok = true}); break
        end
        startPositions(); free(); waitFor(function() return requested end, 1800, "Episode session finished")
    until false
end, debug.traceback)
if not ok then
    warn(token, "EPISODE_FAILURE", problem)
    caption("Показ остановлен. Обычное управление доступно; для нового показа перезапусти тест с двумя клиентами.", false, true, false)
    if automatic then Studio:EndTest({ok = false, error = tostring(problem)}) end
end
script.Destroying:Connect(function()
    for _, connection in connections do connection:Disconnect() end
    for _, connection in healthConnections do connection:Disconnect() end
    if decor then decor:Destroy() end
end)
