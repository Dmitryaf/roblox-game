--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local control = ReplicatedStorage:WaitForChild("WarriorTestControl", 20) :: RemoteEvent
local melee = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local failure: string? = nil
local sequence = 0
local deathArmed: { [Player]: boolean } = {}
local deathTrace: { [Player]: any } = {}
local connections: { RBXScriptConnection } = {}
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
	if kind == "ready" then ready[player] = true
	elseif kind == "failure" then failure = tostring(id)
	elseif kind == "report" then reports[id] = { player = player, report = data } end
end))
-- Kill on the same authenticated cast delivery, after its production gateway.
-- A round trip to the client would already exceed the 0.3 s windup at 150 ms lag.
table.insert(connections, melee.OnServerEvent:Connect(function(player, request)
	if not deathArmed[player] or type(request) ~= "table" or request.action ~= "cast" then return end
	deathArmed[player] = nil
	local trace = deathTrace[player]
	trace.castReceivedAt, trace.requestId = workspace:GetServerTimeNow(), request.requestId
	task.defer(function()
		if player.Parent ~= Players then return end
		trace.killRequestedAt = workspace:GetServerTimeNow()
		bridge:Invoke("kill", player.UserId)
		trace.killedAt = workspace:GetServerTimeNow()
		local character = player.Character
		local body = if character then character:FindFirstChildOfClass("Humanoid") else nil
		trace.casterHealthAfterKill = if body then body.Health else -1
	end)
end))
local function waitFor(predicate: () -> boolean, seconds: number, reason: string)
	local deadline = os.clock() + seconds
	repeat
		if failure then error(failure) end
		if predicate() then return end
		task.wait(0.025)
	until os.clock() >= deadline
	error(reason)
end
local function command(player: Player, action: string, data: any?): any
	sequence += 1
	local id = sequence
	control:FireClient(player, id, action, data)
	waitFor(function() return reports[id] ~= nil end, 9, "Warrior client command timed out: " .. action)
	local response = reports[id]; reports[id] = nil
	assert(response.player == player and response.report.ok, response.report.error)
	return response.report.data
end
local function humanoid(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function state(player: Player): any return bridge:Invoke("snapshot", player.UserId) end
local function settled(player: Player, point: Vector3)
	bridge:Invoke("place", player.UserId, point)
	waitFor(function()
		local observed = command(player, "inspect")
		return observed.position ~= nil and (observed.position - point).Magnitude < 1
	end, 4, "Client has not received fixture placement")
end
local ok, problem = xpcall(function()
	waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end,
		60, "Two warrior fixture clients did not initialize")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	assert(#players == 2)
	local fighter, target = players[1], players[2]
	local initial = (fighter.Character :: Model):GetAttribute("CombatLife")
	local chosen = command(fighter, "chooseWarrior")
	assert(chosen.classId == "warrior" and chosen.life > initial and chosen.sword and not chosen.warlock)
	assert((target.Character :: Model):GetAttribute("CombatClass") == "warlock", "Selection changed the other player")
	command(fighter, "ready")
	waitFor(function() return state(fighter).ready end, 3, "R did not enter queue")
	command(fighter, "classProbe", { classId = "warlock", reason = "locked" })
	assert((fighter.Character :: Model):GetAttribute("CombatClass") == "warrior")
	command(target, "ready")
	waitFor(function() return state(fighter).phase == "active" and state(fighter).mode == "match" end, 8, "Match did not start")
	command(fighter, "classProbe", { classId = "warlock", reason = "locked" })
	local sourcePoint, targetPoint = Vector3.new(0, 3, -35), Vector3.new(0, 3, -30)
	settled(fighter, sourcePoint); settled(target, targetPoint)
	assert(humanoid(target).Health == 100 and humanoid(fighter).Health == 100)
	command(fighter, "wrongMagic")
	local first = command(fighter, "swing", targetPoint)
	assert(first.preparing >= 1 and first.reply.ok, "LMB did not begin a production swing")
	waitFor(function() return humanoid(target).Health < 100 end, 3, "Real LMB did not damage opponent")
	assert(humanoid(target).Health == 80, "Sword did not apply one 20-damage hit")
	task.wait(0.7)
	assert(humanoid(target).Health == 80, "One swing applied damage more than once")
	local observer = command(target, "inspect")
	assert(observer.struck >= 1 and observer.visualSeen, "Opponent missed real sword strike presentation")
	local deadCharacter = fighter.Character
	local deadLife = (deadCharacter :: Model):GetAttribute("CombatLife")
	local health = humanoid(target).Health
	local trace: any = { healthBefore = health, changes = {}, damage = 0, armedAt = workspace:GetServerTimeNow() }
	deathTrace[fighter] = trace
	local lastHealth = health
	local watched = humanoid(target).HealthChanged:Connect(function(current)
		local delta = current - lastHealth
		table.insert(trace.changes, { at = workspace:GetServerTimeNow(), health = current, delta = delta })
		if delta < 0 then trace.damage += -delta end
		lastHealth = current
	end)
	table.insert(connections, watched)
	deathArmed[fighter] = true
	local cancelled = command(fighter, "swing", targetPoint)
	for _, swing in cancelled.reply.state.active do
		if swing.owner == fighter.UserId and swing.life == deadLife then trace.hitAt = swing.hitAt; break end
	end
	waitFor(function() return humanoid(fighter).Health == 0 end, 2, "Death during preparation did not execute")
	task.wait(0.6)
	watched:Disconnect()
	trace.healthAfter = humanoid(target).Health
	print("WarriorDeathProbe", game:GetService("HttpService"):JSONEncode(trace))
	assert(type(trace.hitAt) == "number" and type(trace.killedAt) == "number" and trace.killedAt < trace.hitAt,
		"Death fixture missed the authoritative preparation window")
	assert(trace.casterHealthAfterKill == 0, "Death fixture did not kill the caster")
	assert(trace.damage == 0, "A cancelled preparation reduced opponent health: " .. game:GetService("HttpService"):JSONEncode(trace))
	waitFor(function()
		local character = fighter.Character
		return character ~= nil and character ~= deadCharacter and character:GetAttribute("CombatLife") ~= deadLife
			and character:GetAttribute("CombatClass") == "warrior" and character:FindFirstChild("HumanoidRootPart") ~= nil
	end, 12, "Warrior did not respawn with a fresh life and preserved class")
	waitFor(function() return command(fighter, "inspect").sword == true end, 5, "Respawn did not restore warrior presentation")
	local fresh = command(fighter, "inspect")
	assert(fresh.life > deadLife and fresh.classId == "warrior" and fresh.effectChildren == 0,
		"New warrior life retained previous swing effects")
	command(fighter, "classProbe", { classId = "warlock", reason = "locked" })
	-- Existing static hit/death checks above remain unchanged. Exercise a separate
	-- clear lane only after the full first-swing lifecycle has completed.
	settled(fighter, Vector3.new(70, 3, 55))
	settled(target, Vector3.new(-70, 3, -55))
	local motion = command(fighter, "runWhileMoving")
	local final = bridge:Invoke("position", fighter.UserId)
	assert(motion.accepted == 3 and motion.distance >= 52 and final ~= nil and final.Z < 3,
		"Server did not observe the moving warrior crossing its lane")
	print("WarriorMotionServer", motion.distance, motion.attackSpeed, final)
	print("PASS warrior: real ClassHud WarriorButton -> new life/class/armour, queue/match lock, wrong-class magic refusal, real LMB -> one 20 damage, observer strike, death during windup, respawn with class and cleanup")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
