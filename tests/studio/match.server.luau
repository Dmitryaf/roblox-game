--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StudioTestService = game:GetService("StudioTestService")
local control = ReplicatedStorage:WaitForChild("MatchTestControl") :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local initialFailure: string? = nil
local sequence = 0
local connection = control.OnServerEvent:Connect(function(player, kind, id, report)
	if kind == "ready" then ready[player] = true
	elseif kind == "initialFailure" then initialFailure = tostring(report.error)
	elseif kind == "report" then reports[id] = { player = player, report = report } end
end)

local function untilTrue(predicate: () -> boolean, seconds: number, reason: string)
	local deadline = os.clock() + seconds
	repeat
		if initialFailure then error(initialFailure) end
		if predicate() then return end
		task.wait(0.04)
	until os.clock() >= deadline
	error(reason)
end
local function snapshot(player: Player): any return bridge:Invoke("snapshot", player.UserId) end
local function position(player: Player): Vector3?
	return bridge:Invoke("position", player.UserId)
end
local function command(player: Player, action: string, data: any?): any
	sequence += 1
	local id = sequence
	control:FireClient(player, action, id, data)
	untilTrue(function() return reports[id] ~= nil end, 6, "Client command timed out: " .. action)
	local delivery = reports[id]
	reports[id] = nil
	assert(delivery.player == player, "Report came from another client")
	assert(delivery.report.ok, delivery.report.error)
	return delivery.report.data
end
local function place(player: Player, point: Vector3)
	bridge:Invoke("place", player.UserId, point)
	local actual = position(player)
	assert(actual and (actual - point).Magnitude < 3, "World fixture failed to move participant")
end
local function allOutside(players: { Player })
	for index, player in players do place(player, Vector3.new(40, 4, -30 + index * 8)) end
end
local function healthOf(player: Player): Humanoid
	local character = player.Character :: Model
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid
end
local function lifeOf(player: Player): number
	local character = player.Character :: Model
	local value = character:GetAttribute("CombatLife")
	assert(type(value) == "number", "Registered character has no CombatLife")
	return value
end
local function livesOf(players: { Player }): { [Player]: number }
	local lives = {}
	for _, player in players do lives[player] = lifeOf(player) end
	return lives
end
local function verifyRenewed(players: { Player }, lives: { [Player]: number }, id: number)
	for _, player in players do
		assert(snapshot(player).matchId == id and snapshot(player).mode == "match", "Resume changed match identity")
		assert(lifeOf(player) > lives[player], "Resume retained an old combat life")
		assert(healthOf(player).Health == 100, "Resume did not restore health")
		local p = position(player) :: Vector3
		assert(math.abs(math.abs(p.Z) - 118) < 10, "Resume did not return participant to team pad")
	end
end
local function participants(players: { Player }): number
	local count = 0
	for _, player in players do
		local state = snapshot(player)
		if state.mode == "match" and not state.frozen then count += 1 end
	end
	return count
end
local function inspectClient(player: Player, phase: string, mode: string, id: number)
	untilTrue(function()
		local report = command(player, "inspect")
		return report.state ~= nil and report.state.phase == phase and report.state.mode == mode
			and report.state.matchId == id and report.snapshots >= 2
			and (if mode == "match" then report.hud.exitVisible else report.hud.readyVisible)
	end, 5, "Client snapshot/HUD did not display " .. phase .. "/" .. mode)
end

local ok, err = xpcall(function()
	local args = StudioTestService:GetTestArgs()
	local expected = if type(args) == "table" and args.clients then args.clients else 2
	assert(expected == 2 or expected == 6, "Match fixture supports two or six clients")
	untilTrue(function()
		local count = 0
		for player in ready do if player.Parent == Players then count += 1 end end
		return count == expected
	end, 100, "Clients did not initialize production HUD and synchronization")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	assert(#players == expected, "Unexpected player count")
	for index, player in players do
		local state = snapshot(player)
		assert(state.mode == "training" and not state.ready, "Player did not begin in solo training")
		if index == 1 then
			local clicked = command(player, "readyClick")
			assert(clicked.state.ready and clicked.preparingBefore == clicked.preparingAfter,
				"Ready GUI click did not remain separate from combat input")
		else command(player, "ready") end
	end
	untilTrue(function() return participants(players) == expected end, 10, "Ready input did not start equal teams")
	local first = snapshot(players[1])
	local firstId = first.matchId
	assert(first.phase == "active" and firstId > 0, "First match did not become active")
	local teamA: Player? = nil
	local teamB: Player? = nil
	for _, player in players do
		local state = snapshot(player)
		if state.team == 1 then teamA = player else teamB = player end
	end
	assert(teamA and teamB, "Match did not allocate two teams")
	local a, b = teamA :: Player, teamB :: Player
	inspectClient(a, "active", "match", firstId)
	assert(not command(a, "cast", Vector3.new(0, 0, -1)).ok, "Protected pad permitted arrow launch")
	allOutside(players)
	task.wait(0.4)
	assert(snapshot(a).zone == "neutral", "Empty objective was not neutral")
	place(a, Vector3.new(-20, 4, 30))
	place(b, Vector3.new(10, 4, 30))
	assert(command(a, "cast", Vector3.xAxis).ok, "Active outside-pad arrow was rejected")
	untilTrue(function() return healthOf(b).Health < 100 end, 3, "Match arrow did not damage opponent")
	assert(healthOf(b).Health == 75, "Match arrow did not deal exactly one damage application")
	if expected == 6 then
		local ally: Player? = nil
		for _, player in players do
			if player ~= a and snapshot(player).team == 1 then ally = player; break end
		end
		assert(ally, "Six-player fixture did not provide an ally")
		place(b, Vector3.new(40, 4, -38))
		place(ally :: Player, Vector3.new(10, 4, 30))
		task.wait(3.6)
		assert(command(a, "cast", Vector3.xAxis).ok, "Friendly-fire probe did not launch")
		task.wait(1.1)
		assert(healthOf(ally :: Player).Health == 100, "Arrow damaged a teammate")
		place(ally :: Player, Vector3.new(40, 4, -46))
	end
	place(a, Vector3.new(-4, 4, 0))
	place(b, Vector3.new(4, 4, 0))
	untilTrue(function() return snapshot(a).zone == "contested" end, 2, "Enemy presence did not contest objective")
	local disputed = snapshot(a)
	task.wait(1.2)
	local afterDispute = snapshot(a)
	assert(afterDispute.scoreA == disputed.scoreA and afterDispute.scoreB == disputed.scoreB,
		"Contested zone awarded points")
	local deadCharacter = b.Character
	local killedAt = os.clock()
	bridge:Invoke("kill", b.UserId)
	untilTrue(function() return snapshot(a).countB == 0 end, 1, "Dead participant still occupied zone")
	place(a, Vector3.new(40, 4, -38))
	local empty = snapshot(a)
	assert(empty.scoreA < 3 and empty.scoreB < 3, "Death test prematurely completed match")
	untilTrue(function()
		local character = b.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		return character ~= nil and character ~= deadCharacter and humanoid ~= nil and humanoid.Health > 0
			and position(b) ~= nil
	end, 9, "Participant did not respawn after five seconds")
	assert(os.clock() - killedAt >= 4.5, "Participant respawned before the agreed five-second delay")
	local spawned = position(b) :: Vector3
	assert(math.abs(math.abs(spawned.Z) - 118) < 10, "Respawn did not return participant to team pad")
	assert(snapshot(a).scoreA == empty.scoreA and snapshot(a).scoreB == empty.scoreB,
		"Empty zone accumulated points during respawn")
	place(a, Vector3.new(-4, 4, 0))
	untilTrue(function() return snapshot(a).phase == "finished" end, 6, "Exclusive control did not finish match")
	for _, player in players do
		local state = snapshot(player)
		assert(state.mode == "training" and not state.ready, "Finished participant did not return to training")
		assert(state.result and state.result.matchId == firstId and state.result.reason == "score"
			and state.result.winner == 1 and state.result.scoreA == 3, "Incorrect score result")
	end
	inspectClient(a, "finished", "training", firstId)
	local result = snapshot(a)
	task.wait(1.1)
	assert(snapshot(a).scoreA == result.scoreA and snapshot(a).scoreB == result.scoreB,
		"Score continued after completion")

	-- Start from one pair; the six-client run then introduces two late pairs.
	command(players[1], "ready")
	command(players[2], "ready")
	untilTrue(function() return participants(players) == 2 end, 8, "Second match did not start from a pair")
	local second = snapshot(players[1])
	local secondId = second.matchId
	assert(secondId > firstId and second.scoreA == 0 and second.scoreB == 0 and second.result == nil,
		"Second match retained previous identity, result or score")
	if expected == 6 then
		for index = 3, 6 do command(players[index], "ready") end
		untilTrue(function() return participants(players) == 6 end, 7, "Late pairs did not expand to three versus three")
		local counts = { 0, 0 }
		for _, player in players do
			local state = snapshot(player)
			assert(state.matchId == secondId, "Late pair entered a different match")
			counts[state.team] += 1
		end
		assert(counts[1] == 3 and counts[2] == 3, "Late entry produced unequal active rosters")
	end
	allOutside(players)
	local quitter = players[2]
	local remaining = players[1]
	local beforeReplacement = livesOf(players)
	command(quitter, "exit")
	untilTrue(function() return snapshot(remaining).phase == "paused" end, 2, "Exit input did not pause match")
	assert(snapshot(quitter).mode == "training", "Exit input did not return quitter to training")
	local paused = snapshot(remaining)
	place(remaining, Vector3.new(0, 4, 0))
	local character = remaining.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local health = humanoid.Health
	local rejected = command(remaining, "cast", Vector3.new(0, 0, 1))
	assert(not rejected.ok, "Paused participant could launch arrow")
	task.wait(0.9)
	local stillPaused = snapshot(remaining)
	assert(stillPaused.phase == "paused" and stillPaused.frozen, "Pause ended before replacement timeout")
	assert(stillPaused.scoreA == paused.scoreA and stillPaused.scoreB == paused.scoreB
		and math.abs(stillPaused.remaining - paused.remaining) < 0.05, "Score or match time advanced during pause")
	assert(humanoid.Health == health, "Participant lost health during paused cast probe")
	command(quitter, "ready")
	untilTrue(function() return snapshot(remaining).phase == "resuming" end, 2, "Ready replacement did not begin resuming")
	local resuming = snapshot(remaining)
	assert(resuming.matchId == secondId and resuming.scoreA == paused.scoreA and resuming.scoreB == paused.scoreB
		and math.abs(resuming.remaining - paused.remaining) < 0.05, "Replacement reset score, match identity or clock")
	untilTrue(function() return participants(players) == expected end, 3, "Replacement did not restore active equal teams")
	verifyRenewed(players, beforeReplacement, secondId)
	allOutside(players)
	local excluded: { [Player]: boolean } = {}
	if expected == 6 then
		local smaller: { Player } = {}
		local firstQuitter = players[2]
		local team = snapshot(firstQuitter).team
		local opposite: Player? = nil
		for _, player in players do
			if snapshot(player).team ~= team then opposite = player; break end
		end
		assert(opposite, "Balanced departure has no opposite-team participant")
		for _, player in players do
			if player ~= firstQuitter and player ~= opposite then table.insert(smaller, player) end
		end
		local previousLives = livesOf(smaller)
		remaining = smaller[1]
		local beforeBalancedExit = snapshot(remaining)
		command(firstQuitter, "exit")
		untilTrue(function() return snapshot(remaining).phase == "paused" end, 2, "First balanced departure did not pause")
		local balancedPaused = snapshot(remaining)
		command(opposite :: Player, "exit")
		excluded[firstQuitter], excluded[opposite :: Player] = true, true
		untilTrue(function() return snapshot(remaining).phase == "resuming" end, 2, "Equal reduced teams did not resume")
		local reduced = snapshot(remaining)
		assert(reduced.matchId == secondId and reduced.scoreA == beforeBalancedExit.scoreA
			and reduced.scoreB == beforeBalancedExit.scoreB and math.abs(reduced.remaining - balancedPaused.remaining) < 0.05,
			"Balanced departure changed match score, paused time or identity")
		untilTrue(function() return participants(players) == 4 end, 3, "Balanced departure did not yield two versus two")
		verifyRenewed(smaller, previousLives, secondId)
		for player in excluded do
			assert(snapshot(player).mode == "training" and not snapshot(player).ready, "Departed participant re-entered without ready input")
		end
		allOutside(smaller)
		quitter = smaller[2]
	end
	command(quitter, "exit")
	excluded[quitter] = true
	untilTrue(function() return snapshot(remaining).phase == "paused" end, 2, "Final unequal departure did not pause")
	untilTrue(function() return snapshot(remaining).phase == "finished" end, 5, "Missing replacement did not interrupt match")
	for _, player in players do
		local state = snapshot(player)
		assert(state.mode == "training" and not state.frozen, "Interrupted participant retained match context")
		if not excluded[player] then
			assert(state.result and state.result.reason == "interrupted" and state.result.winner == nil,
				"Interruption incorrectly assigned victory")
		end
	end
	inspectClient(remaining, "finished", "training", secondId)
	print("PASS match: " .. tostring(expected) .. " clients, R/B input, synchronized HUD, pad protection, opponent damage, equal teams, neutral/contested/exclusive zone, death exclusion, respawn, score victory, replay, replacement with fresh lives, pause/interruption"
		.. (if expected == 6 then ", friendly-fire refusal, two late pairs, balanced departure to two versus two" else ""))
	for _, player in players do command(player, "finish") end
end, debug.traceback)
connection:Disconnect()
StudioTestService:EndTest({ ok = ok, error = if ok then nil else tostring(err) })
