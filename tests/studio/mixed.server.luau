--!strict
-- Integration of already approved actions. This is not a class-balance test.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local control = ReplicatedStorage:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local arrowRemote = ReplicatedStorage:WaitForChild("ArrowRemote", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local damage: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local sequence = 0
local failure: string? = nil
local slowedCaster: Player? = nil
local slowedInputs: { [string]: any } = {}
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
	if kind == "ready" then ready[player] = true
	elseif kind == "failure" then failure = tostring(id)
	elseif kind == "report" then reports[id] = { player = player, report = data } end
end))
local function body(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function human(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function corrections(player: Player): number return ((player.Character :: Model):GetAttribute("CombatMovementCorrections") or 0) :: number end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat
		if failure then error(failure) end
		if predicate() then return end
		task.wait(0.02)
	until os.clock() >= deadline
	error(message)
end
local function beginCommand(player: Player, action: string, data: any?): number
	sequence += 1
	control:FireClient(player, sequence, action, data)
	return sequence
end
local function finishCommand(player: Player, id: number): any
	waitFor(function() return reports[id] ~= nil end, 10, "Mixed client command timed out: " .. tostring(id))
	local response = reports[id]; reports[id] = nil
	assert(response.player == player and response.report.ok, response.report.error)
	return response.report.data
end
local function command(player: Player, action: string, data: any?): any
	return finishCommand(player, beginCommand(player, action, data))
end
local function inspect(player: Player): any return command(player, "inspect") end
local function settle(player: Player, position: Vector3)
	bridge:Invoke("place", player.UserId, position)
	waitFor(function() return (inspect(player).position - position).Magnitude < 1 end, 4, "Mixed owner did not receive fixture placement")
	task.wait(0.1)
end
local function cast(player: Player, ability: string, point: Vector3?): any
	local result = command(player, "cast", { ability = ability, point = point, ok = true })
	assert(result.reply.ok, "Mixed actual input was refused: " .. tostring(result.reply.reason))
	return result
end
local function owned(state: any, player: Player): any
	for _, active in state.active do if active.owner == player.UserId then return active end end
	error("Accepted mixed cast omitted its active authoritative action")
end
local function cooldown(player: Player, ability: string)
	local at = inspect(player).states[ability].readyAt
	waitFor(function() return workspace:GetServerTimeNow() >= at + 0.1 end, 10, "Mixed cooldown did not elapse: " .. ability)
end
local function watchDamage(player: Player)
	local humanoid = human(player)
	humanoid.MaxHealth, humanoid.Health = 1000, 1000
	damage[player] = 0
	local previous = humanoid.Health
	table.insert(connections, humanoid.HealthChanged:Connect(function(current)
		if current < previous then damage[player] += previous - current end
		previous = current
	end))
end
local function closePair(warrior: Player, warlock: Player)
	settle(warrior, Vector3.new(5, 3, 40)); settle(warlock, Vector3.new(0, 3, 40))
end
table.insert(connections, arrowRemote.OnServerEvent:Connect(function(player: Player, request: any)
	if player ~= slowedCaster or type(request) ~= "table" or (request.action ~= "cast" and request.action ~= "teleport") then return end
	local trace: any = { at = workspace:GetServerTimeNow(), speed = human(player).WalkSpeed,
		position = body(player).Position, corrections = corrections(player) }
	slowedInputs[request.action] = trace
	print("MixedSlowedInput", request.action, player.UserId, "at", trace.at, "speed", trace.speed, "position", trace.position)
	if request.action == "teleport" then
		task.defer(function()
			trace.after = bridge:Invoke("position", player.UserId)
			print("MixedTeleportServer", "actual", body(player).Position, "trusted", trace.after,
				"speed", human(player).WalkSpeed, "corrections", corrections(player))
		end)
	end
end))
local ok, problem = xpcall(function()
	waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end, 60, "Two mixed-class clients did not initialize")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local warrior, warlock = players[1], players[2]
	command(warrior, "class", "warrior")
	command(warlock, "class", "warrior"); command(warlock, "class", "warlock")
	assert(inspect(warrior).classId == "warrior" and inspect(warlock).classId == "warlock", "Real class choice did not establish two different classes")
	command(warrior, "ready"); command(warlock, "ready")
	waitFor(function() return context(warrior).mode == "match" and not context(warrior).frozen end, 8, "Mixed 1v1 did not activate")
	assert(context(warrior).team ~= context(warlock).team, "Mixed fixture participants are not opponents")
	for _, player in players do watchDamage(player) end
	settle(warlock, Vector3.new(-5, 3, 40)); settle(warrior, Vector3.new(0, 3, 40))
	local initialWarrior, initialWarlock = corrections(warrior), corrections(warlock)
	local handsCenter = Vector3.new(0, 0, 40)
	local handCast = owned(cast(warlock, "hands", handsCenter).state, warlock)
	waitFor(function() return math.abs(human(warrior).WalkSpeed - 10.4) < 0.001 and damage[warrior] >= 3 end,
		4, "Real hands did not slow and periodically damage the opposing warrior")
	local escape = command(warrior, "move", { direction = Vector3.xAxis, duration = 1.7, dashAt = 0.3 })
	assert(escape.dashReply ~= nil and escape.dashReply.ok and escape.corrections == 0,
		"Actual warrior W/E did not escape hands without a movement correction")
	local outside = bridge:Invoke("position", warrior.UserId) :: Vector3
	assert(((outside - handsCenter) * Vector3.new(1, 0, 1)).Magnitude > handCast.radius and human(warrior).WalkSpeed == 16,
		"Warrior remained inside hands or retained their slow after real W/E")
	local damageAfterExit = damage[warrior]
	task.wait(0.65)
	assert(damage[warrior] == damageAfterExit, "Hands damaged the warrior after the confirmed exit")
	print("MixedHandsEscape", "distance", escape.distance, "speed", human(warrior).WalkSpeed,
		"damage", damage[warrior], "corrections", corrections(warrior) - initialWarrior)
	waitFor(function() return workspace:GetServerTimeNow() > handCast.expiresAt + 0.1 end, 5, "Hands did not finish before the next mixed scenario")
	closePair(warrior, warlock)
	local beforeHeavy = damage[warlock]
	local heavy = owned(cast(warrior, "heavy", Vector3.new(0, 3, 40)).state, warrior)
	waitFor(function() return damage[warlock] >= beforeHeavy + 25 and math.abs(human(warlock).WalkSpeed - 9.6) < 0.001 end,
		3, "Heavy did not apply 25 damage and slow to the warlock")
	assert(damage[warlock] == beforeHeavy + 25, "Heavy hit the same warlock more than once")
	slowedCaster = warlock
	local arrow = owned(cast(warlock, "arrow", Vector3.new(0, 1, -30)).state, warlock)
	assert(math.abs(arrow.launchAt - arrow.startedAt - 0.7) < 0.001
		and math.abs(arrow.expiresAt - arrow.launchAt - 2.2) < 0.001 and arrow.speed == 58, "Mixed scenario changed the accepted arrow contract")
	-- The landing is three studs behind the arrow. Give it enough travel for the
	-- unchanged >=5-stud assertion, without depending on input/network overhead.
	waitFor(function() return workspace:GetServerTimeNow() >= arrow.launchAt + 0.18 end, 2, "Slowed warlock arrow did not reach its travel time")
	local teleported = cast(warlock, "teleport", nil)
	slowedCaster = nil
	assert(slowedInputs.cast ~= nil and slowedInputs.teleport ~= nil and math.abs(slowedInputs.cast.speed - 9.6) < 0.001
		and math.abs(slowedInputs.teleport.speed - 9.6) < 0.001,
		"Real LMB/E were not both delivered while the warlock was slowed")
	assert(slowedInputs.teleport.at < heavy.hitAt + 2 and slowedInputs.teleport.at >= arrow.launchAt
		and slowedInputs.teleport.at < arrow.expiresAt, "Slowed teleport missed the heavy lease or live-arrow window")
	local landing = bridge:Invoke("position", warlock.UserId) :: Vector3
	assert((landing - Vector3.new(0, 3, 40)).Magnitude >= 5 and math.abs(landing.X) < 3 and landing.Z < 35
		and landing.Y > 1 and landing.Y < 10 and math.abs(landing.Z) < 100,
		"Real teleport did not reach a supported landing in the clear non-pad corridor")
	waitFor(function() return (inspect(warlock).position - landing).Magnitude < 1 end, 4, "Teleport owner did not receive its authoritative landing")
	for _, action in teleported.state.active do assert(action.owner ~= warlock.UserId, "Teleport did not consume the owner's arrow") end
	waitFor(function() return human(warlock).WalkSpeed == 16 end, 3, "Warlock teleport retained heavy slow after its expiry")
	print("MixedSlowedTeleport", "landing", landing, "actual", body(warlock).Position,
		"trusted", bridge:Invoke("position", warlock.UserId), "corrections", corrections(warlock) - initialWarlock)
	cooldown(warrior, "heavy")
	closePair(warrior, warlock)
	local beforeCombo = damage[warlock]
	local comboHeavy = owned(cast(warrior, "heavy", Vector3.new(0, 3, 40)).state, warrior)
	waitFor(function() return damage[warlock] >= beforeCombo + 25 end, 3, "Mixed heavy follow-up did not begin with its 25 damage")
	assert(damage[warlock] == beforeCombo + 25, "Mixed heavy applied duplicate damage")
	waitFor(function() return workspace:GetServerTimeNow() > comboHeavy.expiresAt + 0.05 end, 2, "Heavy recovery did not finish before ordinary follow-up")
	cast(warrior, "melee", Vector3.new(0, 3, 40))
	waitFor(function() return damage[warlock] >= beforeCombo + 45 end, 3, "Actual LMB did not follow heavy with its 20 damage")
	assert(damage[warlock] == beforeCombo + 45, "Heavy plus normal swing did not apply exactly 25 plus 20 negative health loss")
	print("MixedSwordFollowup", "negativeHealthLoss", damage[warlock] - beforeCombo, "healthWithHealing", human(warlock).Health)
	waitFor(function() return human(warlock).WalkSpeed == 16 end, 3, "Follow-up heavy slow failed to expire")
	cooldown(warrior, "heavy")
	closePair(warrior, warlock)
	local beforeDodge = damage[warlock]
	-- Deliver both real-input commands together. Waiting through the Q reply's
	-- four network hops would consume the entire .65-second dodge opportunity.
	local castId = beginCommand(warrior, "cast", { ability = "heavy", point = Vector3.new(0, 3, 40), ok = true })
	local movementId = beginCommand(warlock, "move", { direction = Vector3.new(0, 0, -1), duration = 1.3 })
	local dodge = owned(finishCommand(warrior, castId).state, warrior)
	waitFor(function() return workspace:GetServerTimeNow() >= dodge.hitAt - 0.05 end, 2, "Dodge did not reach the pre-hit observation window")
	local beforeHitAt = workspace:GetServerTimeNow()
	local gap = ((body(warrior).Position - body(warlock).Position) * Vector3.new(1, 0, 1)).Magnitude
	print("MixedDodgeBeforeHit", "at", beforeHitAt, "hitAt", dodge.hitAt, "gap", gap, "warlock", body(warlock).Position)
	assert(beforeHitAt < dodge.hitAt and gap > 7, "Actual W did not move the warlock beyond sword range before contact")
	local movement = finishCommand(warlock, movementId)
	waitFor(function() return workspace:GetServerTimeNow() > dodge.expiresAt + 0.1 end, 3, "Dodged heavy did not finish")
	assert(damage[warlock] == beforeDodge and human(warlock).WalkSpeed == 16 and movement.corrections == 0,
		"A dodged heavy still damaged/slowed the warlock or corrected its movement")
	for _, player in players do
		local data = inspect(player)
		local baseline = if player == warrior then initialWarrior else initialWarlock
		assert(corrections(player) == baseline and data.physicsViolations == 0,
			"Mixed class actions introduced authoritative corrections or physical presentation parts")
	end
	print("PASS mixed classes: real GUI Warrior/Warlock 1v1, real hands/warrior W+E escape, slowed warlock LMB+E safe live-arrow landing, heavy25 plus ordinary20, real W dodge before hit, negative-health accounting and no additional authoritative corrections")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
