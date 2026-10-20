--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local control = ReplicatedStorage:WaitForChild("DashTestControl", 20) :: RemoteEvent
local dash = ReplicatedStorage:WaitForChild("DashRemote", 20) :: RemoteEvent
local melee = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local armed: { [Player]: any } = {}
local failure: string? = nil
local sequence = 0
local connections: { RBXScriptConnection } = {}
local owned: { Instance } = {}
local delivered: { [Player]: { any } } = {}
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
	if kind == "ready" then ready[player] = true
	elseif kind == "failure" then failure = tostring(id)
	elseif kind == "report" then reports[id] = { player = player, report = data } end
end))
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function health(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function constrained(body: BasePart): boolean
	return body:FindFirstChild("WarriorDashVelocity") ~= nil or body:FindFirstChild("WarriorDashAttachment") ~= nil
end
local function record(player: Player, ability: string, request: any)
	if type(request) ~= "table" or request.action ~= "cast" then return end
	local samples = delivered[player] or {}
	delivered[player] = samples
	local position = root(player).Position
	table.insert(samples, { ability = ability, requestId = request.requestId, life = request.life,
		at = workspace:GetServerTimeNow(), position = { position.X, position.Y, position.Z }, constrained = constrained(root(player)) })
	if #samples > 10 then table.remove(samples, 1) end
end
table.insert(connections, melee.OnServerEvent:Connect(function(player, request) record(player, "melee", request) end))
-- Observe/cancel at the authenticated cast delivery. A client round trip would
-- miss the 0.28-second ability at 150 ms in each direction.
table.insert(connections, dash.OnServerEvent:Connect(function(player, request)
	record(player, "dash", request)
	local trace = armed[player]
	if not trace or type(request) ~= "table" or request.action ~= "cast" then return end
	armed[player] = nil
	task.defer(function()
		local body, humanoid = root(player), health(player)
		trace.startedAt, trace.constrained = workspace:GetServerTimeNow(), constrained(body)
		trace.healthBefore = humanoid.Health
		if trace.mode == "damage" then
			humanoid:TakeDamage(7)
			trace.healthAfter = humanoid.Health
		elseif trace.mode == "death" then
			task.wait(0.04)
			trace.cancelledAt = workspace:GetServerTimeNow()
			bridge:Invoke("kill", player.UserId)
			task.wait(0.05)
			trace.cleaned = not constrained(body)
		elseif trace.mode == "pause" then
			task.wait(0.18)
			trace.checkedAt, trace.frozen = workspace:GetServerTimeNow(), context(player).frozen
			trace.cleaned = not constrained(body)
		end
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
	waitFor(function() return reports[id] ~= nil end, 9, "Dash client command timed out: " .. action)
	local response = reports[id]; reports[id] = nil
	assert(response.player == player and response.report.ok, response.report.error)
	return response.report.data
end
local function settle(player: Player, point: Vector3)
	bridge:Invoke("place", player.UserId, point)
	waitFor(function() return (command(player, "inspect").position - point).Magnitude < 1 end,
		4, "Dash owner did not receive fixture placement")
	task.wait(0.15)
end
local function cooldown(player: Player)
	local state = command(player, "inspect").state
	waitFor(function() return workspace:GetServerTimeNow() > state.readyAt + 0.1 end, 6, "Dash cooldown did not elapse")
end
local function clean(player: Player)
	assert(not constrained(root(player)), "Dash physics resources leaked on server")
	for _, observer in Players:GetPlayers() do
		local info = command(observer, "inspect")
		assert(info.resources == 0 and info.violations == 0, "Dash cosmetic resources leaked/entered physics")
	end
end
local function busyReport(player: Player, mode: string, result: any, damageTrace: any?)
	print("BusyProbe", mode, "dash", result.dash.ok, result.dash.reason, "melee", result.melee.ok, result.melee.reason)
	print("BusyTimeline", mode, game:GetService("HttpService"):JSONEncode(result.timeline))
	for _, key in { "dash", "melee" } do
		local reply = result[key]
		print("BusyState", mode, key, "id", reply.requestId, "life", reply.state.life, "readyAt", reply.state.readyAt)
		for _, action in reply.state.active do
			print("BusyActive", mode, key, action.owner, action.startedAt, action.expiresAt, action.hitAt)
		end
	end
	local samples = delivered[player] or {}
	for index = math.max(1, #samples - 1), #samples do
		local sample = samples[index]
		print("BusyDelivery", mode, sample.ability, "id", sample.requestId, "at", sample.at,
			"constraint", sample.constrained, "position", table.concat(sample.position, ","))
	end
	if damageTrace then print("BusyDamage", game:GetService("HttpService"):JSONEncode(damageTrace)) end
	if mode == "dashFirst" then
		local first, second = samples[#samples - 1], samples[#samples]
		assert(first and second and first.ability == "dash" and second.ability == "melee" and first.at <= second.at,
			"Busy fixture did not deliver the real E before the competing melee request")
		assert(second.constrained and second.at - first.at < 0.28,
			"Competing melee request missed the authoritative active dash window")
	end
end
local ok, problem = xpcall(function()
	waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end,
		60, "Two dash clients did not initialize")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local fighter, observer = players[1], players[2]
	command(observer, "probe", { direction = Vector3.new(0, 0, -1), ok = false, reason = "wrong_class" })
	local chosen = command(fighter, "class", "warrior")
	assert(chosen.classId == "warrior" and chosen.hud, "Real class selection did not enable dash HUD")
	settle(fighter, Vector3.new(230, 3, 35))
	local target = workspace.ControlArena:FindFirstChild("Мишень") :: Model
	local targetHealth = (target:FindFirstChildOfClass("Humanoid") :: Humanoid).Health
	local idle = command(fighter, "motion", { moving = false })
	assert(idle.started.distance == 16 and math.abs(idle.started.duration - 0.28) < 0.001, "Unexpected initial dash tuning")
	local refused = command(fighter, "key")
	assert(not refused.ok and refused.reason == "cooldown", "Real repeated E bypassed cooldown")
	assert(health(fighter).Health == 100 and health(observer).Health == 100
		and (target:FindFirstChildOfClass("Humanoid") :: Humanoid).Health == targetHealth, "Dash added unapproved damage")
	assert(command(observer, "inspect").observed > 0, "Other client missed actual dash cosmetics")
	clean(fighter)
	cooldown(fighter)
	settle(fighter, Vector3.new(230, 3, 50))
	local moving = command(fighter, "motion", { moving = true, direction = Vector3.new(0, 0, -1) })
	clean(fighter)
	cooldown(fighter)
	-- Rotate the camera and hold the real W key: MoveDirection must win over
	-- the facing inherited from the previous -Z dash, including sideways travel.
	settle(fighter, Vector3.new(210, 3, 15))
	local sideways = command(fighter, "motion", { moving = true, direction = Vector3.xAxis })
	assert(sideways.started.direction:Dot(Vector3.xAxis) > 0.98, "Camera-relative movement did not direct E")
	cooldown(fighter)
	local wall = Instance.new("Part")
	wall.Name, wall.Size, wall.Position, wall.Anchored = "DashThinWall", Vector3.new(0.15, 10, 18), Vector3.new(240, 5, 15), true
	wall.Parent = workspace; table.insert(owned, wall)
	settle(fighter, Vector3.new(230, 3, 15))
	local clipped = command(fighter, "motion", { moving = false, minimum = 3, maximum = 10 })
	assert(clipped.started.distance < 10 and root(fighter).Position.X < 239, "Dash crossed a thin physical wall")
	cooldown(fighter)
	settle(fighter, Vector3.new(236.7, 3, 15))
	local short = command(fighter, "motion", { moving = false, minimum = 0.3, maximum = 2.5 })
	assert(short.started.distance >= 1 and short.started.distance <= 2.5 and short.started.duration < 0.05,
		"Close wall did not exercise a real dash shorter than one-way network latency")
	assert(root(fighter).Position.X < 239, "Very short accepted E crossed the thin wall")
	local shortCooldown = command(fighter, "key")
	assert(not shortCooldown.ok and shortCooldown.reason == "cooldown", "Very short accepted E did not consume its cooldown")
	cooldown(fighter)
	settle(fighter, Vector3.new(238.5, 3, 15))
	local blocked = command(fighter, "key")
	assert(not blocked.ok and blocked.reason == "blocked", "E against adjacent wall was not rejected")
	wall:Destroy()
	settle(fighter, Vector3.new(230, 3, 35))
	local busy = command(fighter, "busy", "meleeFirst")
	busyReport(fighter, "meleeFirst", busy, nil)
	assert(busy.melee.ok and not busy.dash.ok and busy.dash.reason == "busy", "Dash interrupted the ordinary swing")
	task.wait(0.7)
	local damageTrace: any = { mode = "damage" }; armed[fighter] = damageTrace
	local reverse = command(fighter, "busy", "dashFirst")
	busyReport(fighter, "dashFirst", reverse, damageTrace)
	assert(reverse.dash.ok and not reverse.melee.ok and reverse.melee.reason == "busy", "Swing interrupted an active dash")
	assert(damageTrace.constrained and damageTrace.healthBefore == 100 and damageTrace.healthAfter == 93,
		"Dash made the actor invulnerable or damage probe missed its active window")
	cooldown(fighter)
	settle(fighter, Vector3.new(230, 3, 35))
	local beforeClassLife = (fighter.Character :: Model):GetAttribute("CombatLife") :: number
	local cancelled = command(fighter, "cancelClass")
	assert(cancelled.ok and (fighter.Character :: Model):GetAttribute("CombatLife") > beforeClassLife,
		"Class change did not cancel an accepted dash into a new life")
	task.wait(0.3); clean(fighter)
	command(fighter, "class", "warrior")
	settle(fighter, Vector3.new(230, 3, 35))
	local oldCharacter = fighter.Character :: Model
	local oldLife = oldCharacter:GetAttribute("CombatLife") :: number
	local deathTrace: any = { mode = "death" }; armed[fighter] = deathTrace
	assert(command(fighter, "key").ok, "Death cancellation E was not accepted")
	waitFor(function() return deathTrace.cleaned ~= nil end, 2, "Dash death trace did not complete")
	assert(deathTrace.constrained and deathTrace.cleaned and deathTrace.cancelledAt < deathTrace.startedAt + 0.28,
		"Death did not remove an active dash constraint before its natural expiry")
	waitFor(function()
		local character = fighter.Character
		local life = if character then character:GetAttribute("CombatLife") else nil
		return character ~= nil and character ~= oldCharacter and type(life) == "number" and life > oldLife
	end, 12, "Dash owner did not respawn into a new life")
	waitFor(function() return command(fighter, "inspect").state.life == (fighter.Character :: Model):GetAttribute("CombatLife") end,
		5, "New life dash snapshot not received")
	clean(fighter)
	command(fighter, "ready"); command(observer, "ready")
	waitFor(function() return context(fighter).mode == "match" and not context(fighter).frozen end, 8, "Dash fixture match did not activate")
	local protected = command(fighter, "key")
	assert(not protected.ok and protected.reason == "spawn_protected", "Dash bypassed starting-pad combat protection")
	settle(fighter, Vector3.new(70, 3, 55)); settle(observer, Vector3.new(-70, 3, -55))
	local pauseTrace: any = { mode = "pause" }; armed[fighter] = pauseTrace
	local at = workspace:GetServerTimeNow() + 1.1
	command(observer, "exitAt", at + 0.08)
	local paused = command(fighter, "eAt", at)
	assert(paused.ok, "Scheduled real E did not begin before opponent exit")
	waitFor(function() return pauseTrace.cleaned ~= nil end, 2, "Dash pause trace did not complete")
	assert(pauseTrace.constrained and pauseTrace.cleaned and pauseTrace.frozen
		and pauseTrace.checkedAt < pauseTrace.startedAt + 0.28, "Real opponent exit did not cancel active dash before natural expiry")
	clean(fighter)
	waitFor(function() return context(fighter).mode == "training" end, 6, "Interrupted match did not return dash owner to training")
	-- Direct adversarial messages are last: their monotonic request ids must not
	-- poison subsequent tests of the production controller's real E producer.
	command(fighter, "probe", { life = oldLife, direction = Vector3.new(0, 0, -1), ok = false, reason = "stale_life" })
	command(fighter, "probe", { direction = Vector3.yAxis, ok = false, reason = "invalid_aim" })
	command(fighter, "probe", { direction = Vector3.zero, silent = true })
	clean(fighter)
	print("DashMotion", "idle", idle.distance, "runningExtra", moving.extra, "runningSpeedAfter", moving.postSpeed,
		"sidewaysExtra", sideways.extra, "sidewaysSpeedAfter", sideways.postSpeed, "thinWallDistance", clipped.distance,
		"shortWallDistance", short.distance, "shortWallDuration", short.started.duration)
	print("PASS dash: two clients/real class button/E idle and camera-relative W, bounded root motion without rewinds, normal speed restoration, observer cosmetics, cooldown/wrong-class/stale-life/invalid-aim, thin and adjacent walls, busy both ways, no damage/invulnerability, class/death/new-life/pad/pause cleanup")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
for _, item in owned do item:Destroy() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
