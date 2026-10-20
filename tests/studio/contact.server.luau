--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local control = ReplicatedStorage:WaitForChild("ContactTestControl", 20) :: RemoteEvent
local dash = ReplicatedStorage:WaitForChild("DashRemote", 20) :: RemoteEvent
local melee = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local phases: { [string]: { [Player]: any } } = {}
local results: { any } = {}
local failure: string? = nil
local sequence = 0
local connections: { RBXScriptConnection } = {}
local deathTrace: any = nil
local deathOwner: Player? = nil
local currentTag = "initial"
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
	if kind == "ready" then ready[player] = true
	elseif kind == "failure" then failure = tostring(id)
	elseif kind == "report" then reports[id] = { player = player, report = data }
	elseif kind == "completed" then
		local bucket = phases[id] or {}; phases[id] = bucket; bucket[player] = data
	end
end))
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function humanoid(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function corrections(player: Player): number return ((player.Character :: Model):GetAttribute("CombatMovementCorrections") or 0) :: number end
table.insert(connections, melee.OnServerEvent:Connect(function(player: Player, request: any)
	if type(request) ~= "table" or request.action ~= "cast" or typeof(request.direction) ~= "Vector3" then return end
	local tag = currentTag
	local function geometry(label: string)
		local character = player.Character
		if not character then return end
		local source = character:FindFirstChild("HumanoidRootPart")
		if not source or not source:IsA("BasePart") then return end
		local target: BasePart? = nil
		if bridge:Invoke("context", player.UserId).mode == "training" then
			local dummy = workspace.ControlArena:FindFirstChild("Мишень")
			target = if dummy then dummy:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		else
			for _, other in Players:GetPlayers() do
				if other ~= player and other.Character then target = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?; break end
			end
		end
		if not target then return end
		local delta = target.Position - source.Position
		local flat = delta * Vector3.new(1, 0, 1)
		local direction = request.direction * Vector3.new(1, 0, 1)
		local dot = if flat.Magnitude > 0.01 and direction.Magnitude > 0.01 then flat.Unit:Dot(direction.Unit) else 1
		print("ContactCastGeometry", tag, label, player.UserId, request.requestId, "at", workspace:GetServerTimeNow(),
			"gap", flat.Magnitude, "dy", delta.Y, "aimDot", dot, "direction", direction)
	end
	geometry("delivery")
	task.delay(0.3, function() geometry("windupPlus0.3") end)
end))
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat
		if failure then error(failure) end
		if predicate() then return end
		task.wait(0.025)
	until os.clock() >= deadline
	error(message)
end
local function command(player: Player, action: string, data: any?): any
	sequence += 1
	local id = sequence
	control:FireClient(player, id, action, data)
	waitFor(function() return reports[id] ~= nil end, 8, "Contact client command timed out: " .. action)
	local delivery = reports[id]; reports[id] = nil
	assert(delivery.player == player and delivery.report.ok, delivery.report.error)
	return delivery.report.data
end
local function place(player: Player, point: Vector3)
	bridge:Invoke("place", player.UserId, point)
	waitFor(function() return (command(player, "inspect").position - point).Magnitude < 1 end, 4, "Contact owner has not received placement")
	task.wait(0.15)
end
local function phase(tag: string, first: Player, second: Player, pointA: Vector3, pointB: Vector3, a: any, b: any): (any, any)
	currentTag = tag
	place(first, pointA); place(second, pointB)
	local beforeA, beforeB = corrections(first), corrections(second)
	local at = workspace:GetServerTimeNow() + 1.4
	a.tag, a.at, b.tag, b.at = tag, at, tag, at
	local attacking = (a.attacks ~= nil and #a.attacks > 0) or (b.attacks ~= nil and #b.attacks > 0)
	a.followTarget, b.followTarget = attacking, attacking
	a.targetOwner, b.targetOwner = if a.targetPoint then nil else second.UserId, if b.targetPoint then nil else first.UserId
	command(first, "start", a); command(second, "start", b)
	waitFor(function() return phases[tag] ~= nil and phases[tag][first] ~= nil and phases[tag][second] ~= nil end,
		math.max(a.duration, b.duration) + 5, "Both contact owner probes did not finish: " .. tag)
	local reportA, reportB = phases[tag][first], phases[tag][second]
	assert(reportA.ok and reportB.ok, reportA.error or reportB.error)
	reportA.data.serverCorrections, reportB.data.serverCorrections = corrections(first) - beforeA, corrections(second) - beforeB
	print("ContactAuthority", tag, first.UserId, reportA.data.serverCorrections, second.UserId, reportB.data.serverCorrections)
	table.insert(results, reportA.data); table.insert(results, reportB.data)
	return reportA.data, reportB.data
end
table.insert(connections, dash.OnServerEvent:Connect(function(player: Player, request: any)
	if player ~= deathOwner or type(request) ~= "table" or request.action ~= "cast" then return end
	deathOwner = nil
	task.defer(function()
		local body = root(player)
		deathTrace.startedAt = workspace:GetServerTimeNow()
		deathTrace.active = body:FindFirstChild("WarriorDashVelocity") ~= nil
		task.wait(0.06)
		deathTrace.killedAt = workspace:GetServerTimeNow()
		bridge:Invoke("kill", player.UserId)
		task.wait(0.03)
		deathTrace.cleaned = body:FindFirstChild("WarriorDashVelocity") == nil and body:FindFirstChild("WarriorDashAttachment") == nil
	end)
end))
local ok, problem = xpcall(function()
	waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end, 60, "Two contact clients did not initialize")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local fighter, opponent = players[1], players[2]
	command(fighter, "class"); command(opponent, "class")
	local dummy = Vector3.new(230, 2.5, -38)
	local approach = (dummy - Vector3.new(228.8, 2.5, -33)).Unit
	phase("dummy-walk", fighter, opponent, Vector3.new(228.8, 3, -33), Vector3.new(210, 3, 40),
		{ direction = approach, targetPoint = dummy, move = true, duration = 2.2 },
		{ direction = Vector3.new(0, 0, -1), move = false, duration = 2.2 })
	local dummyAttack = phase("dummy-attacks", fighter, opponent, Vector3.new(228.8, 3, -33), Vector3.new(210, 3, 40),
		{ direction = approach, targetPoint = dummy, move = true, duration = 4.2, attacks = { 0.4, 1.55, 2.7 } },
		{ direction = Vector3.new(0, 0, -1), move = false, duration = 4.2 })
	command(fighter, "ready"); command(opponent, "ready")
	waitFor(function() local state = bridge:Invoke("context", fighter.UserId); return state.mode == "match" and not state.frozen end,
		8, "Contact match did not become active")
	-- Test-only health prevents five real sword strikes from ending the measurement.
	for _, player in players do humanoid(player).MaxHealth = 1000; humanoid(player).Health = 1000 end
	phase("turn-baseline", fighter, opponent, Vector3.new(0, 3, 55), Vector3.new(-70, 3, 55),
		{ direction = Vector3.new(0, 0, -1), move = true, duration = 3.5, turn = true },
		{ direction = Vector3.new(0, 0, -1), move = true, duration = 3.5, turn = true })
	phase("idle-spin", fighter, opponent, Vector3.new(0, 3, 35), Vector3.new(-70, 3, 35),
		{ direction = Vector3.new(0, 0, -1), move = false, duration = 2.5, spin = true },
		{ direction = Vector3.new(0, 0, -1), move = false, duration = 2.5, spin = true })
	phase("enemy-walk", fighter, opponent, Vector3.new(-12, 3, 30), Vector3.new(12, 3, 30),
		{ direction = Vector3.xAxis, move = true, duration = 3 },
		{ direction = -Vector3.xAxis, move = true, duration = 3 })
	local victim, attacker = phase("enemy-attacks", fighter, opponent, Vector3.new(-12, 3, 30), Vector3.new(12, 3, 30),
		{ direction = Vector3.xAxis, move = true, keepGap = true, duration = 5.3 },
		{ direction = -Vector3.xAxis, move = true, keepGap = true, duration = 5.3, attacks = { 0.9, 2.05, 3.2, 4.35 } })
	local duelA, duelB = phase("mutual-attacks", fighter, opponent, Vector3.new(-12, 3, 30), Vector3.new(12, 3, 30),
		{ direction = Vector3.xAxis, move = true, duration = 5.3, keepGap = true, keepGapAfter = 1.6,
			attacks = { 0.9, 2.05, 3.2, 4.35 } },
		{ direction = -Vector3.xAxis, move = true, duration = 5.3, keepGap = true, keepGapAfter = 1.6,
			attacks = { 0.95, 2.1, 3.25, 4.4 } })
	local closingA, closingB = phase("dash-contact", fighter, opponent, Vector3.new(0, 3, 45), Vector3.new(0, 3, 28),
		{ direction = Vector3.new(0, 0, -1), move = true, duration = 3.5, dashAt = 0.25,
			keepGap = true, gapAfterDash = true, attacks = { 1, 2.15 } },
		{ direction = Vector3.zAxis, move = false, duration = 3.5 })
	deathTrace, deathOwner = {}, fighter
	local dying = phase("dash-death", fighter, opponent, Vector3.new(65, 3, 45), Vector3.new(-65, 3, -35),
		{ direction = Vector3.new(0, 0, -1), move = true, duration = 1.6, dashAt = 0.25 },
		{ direction = Vector3.zAxis, move = false, duration = 1.6 })
	print("ContactDeath", deathTrace.active, deathTrace.startedAt, deathTrace.killedAt, deathTrace.cleaned)
	-- Collect every diagnostic phase before asserting movement, so the first
	-- correction cannot hide the training/enemy/input/dash comparisons.
	for _, result in results do
		assert(result.samples >= 10, "Insufficient native root samples in " .. result.tag)
		assert(result.serverCorrections == 0 and result.corrections == 0, "Authoritative contact correction in " .. result.tag)
		assert(result.unexplainedJumps == 0, "Root jumped away from any native contact in " .. result.tag)
		assert(result.groundRemaining == 0, "Ground dash presentation leaked after " .. result.tag)
		assert(result.impactRemaining == 0, "Confirmed sword impact presentation leaked after " .. result.tag)
	end
	assert(dummyAttack.accepted == 3, "Three actual LMBs did not attack the training dummy")
	assert(attacker.accepted == 4 and victim.damageTaken > 0 and victim.closeSamples > 0,
		"Enemy-only contact did not produce four real attacking inputs and damage")
	assert(attacker.contacts > 0 and victim.contacts > 0 and attacker.impactPeak > 0 and victim.impactPeak > 0,
		"Confirmed enemy contact/impact was not received and displayed on both clients")
	assert(duelA.accepted == 4 and duelB.accepted == 4 and duelA.damageTaken > 0 and duelB.damageTaken > 0,
		"Both moving warriors did not exchange real close-contact sword hits")
	assert(duelA.gapControlAt ~= nil and duelB.gapControlAt ~= nil and duelA.gapControlAt >= 1.6 and duelB.gapControlAt >= 1.6,
		"Mutual attack fixture did not preserve its initial continuous-W contact interval")
	assert(closingA.dashAccepted == 1 and closingA.accepted == 2 and closingB.damageTaken > 0,
		"Actual E into an enemy followed by LMB did not complete")
	assert(closingA.groundPeak > 0 and closingA.shards > 0 and closingA.dust > 0 and closingB.groundPeak > 0,
		"Dash ground rupture/dust was not visible on both clients")
	assert(dying.dashAccepted == 1 and deathTrace.active and deathTrace.cleaned and deathTrace.killedAt < deathTrace.startedAt + 0.28,
		"Death did not cancel a real active dash and its physics")
	for _, player in players do
		local info = command(player, "inspect")
		assert(info.ground == 0 and not info.constraint and info.meleeChildren == 0, "Contact death retained ability resources")
	end
	print("PASS contact: training dummy W/LMB, no-attack turn/spin, opposing W baseline, enemy-only and mutual real LMB, both owner roots/authority corrections, actual E close/attacks, both-client ground art and death cleanup")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
