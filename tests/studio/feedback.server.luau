--!strict
-- Measures actual input/visible joints separately from authoritative actions and dash physics.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
-- The generator disables only effects.preview in an isolated current-source copy.
-- This is a controlled preview-on/off comparison, never an old-revision baseline.
local feedbackBaseline = ServerStorage:GetAttribute("FeedbackBaseline") == true
local feedbackVariant = if feedbackBaseline then "current_preview_off" else "current_preview_on"
local control = ReplicatedStorage:WaitForChild("FeedbackTestControl", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local receipts: { [string]: any } = {}
local losses: { [Player]: { any } } = {}
local connections: { RBXScriptConnection } = {}
local healthConnections: { [Player]: RBXScriptConnection } = {}
local sequence = 0
local failure: string? = nil
local pendingCancel: any = nil
local function now(): number return workspace:GetServerTimeNow() end
local function root(player: Player): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
local function human(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function life(player: Player): number return (player.Character :: Model):GetAttribute("CombatLife") :: number end
local function readyLife(player: Player, previous: number): boolean
	local character = player.Character
	if not character or not character.Parent then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local characterRoot = character:FindFirstChild("HumanoidRootPart")
	local token = character:GetAttribute("CombatLife")
	return humanoid ~= nil and humanoid.Health > 0 and characterRoot ~= nil and characterRoot:IsA("BasePart")
		and type(token) == "number" and token > previous
end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function key(player: Player, ability: string, requestId: number): string return player.UserId .. ":" .. ability .. ":" .. requestId end
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat if failure then error(failure) end; if predicate() then return end; task.wait(0.015) until os.clock() >= deadline
	error(message)
end
local function beginCommand(player: Player, action: string, data: any?): number
	sequence += 1; control:FireClient(player, sequence, action, data); return sequence
end
local function finishCommand(player: Player, id: number): any
	waitFor(function() return reports[id] ~= nil end, 14, "Feedback command timed out: " .. id)
	local result = reports[id]; reports[id] = nil
	assert(result.player == player and result.report.ok, result.report.error); return result.report.data
end
local function command(player: Player, action: string, data: any?): any return finishCommand(player, beginCommand(player, action, data)) end
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
	if kind == "ready" then ready[player] = true
	elseif kind == "failure" then failure = tostring(id)
	elseif kind == "report" then reports[id] = { player = player, report = data } end
end))
local remoteNames: { [string]: string } = { melee = "MeleeRemote", heavy = "HeavyRemote", arrow = "ArrowRemote", dash = "DashRemote" }
for ability, remoteName in remoteNames do
	local remote = ReplicatedStorage:WaitForChild(remoteName, 20) :: RemoteEvent
	table.insert(connections, remote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" or (request.action ~= "cast" and request.action ~= "teleport") then return end
		local receipt = { at = now(), requestId = request.requestId, life = request.life, action = request.action, ability = ability,
			position = root(player).Position, speed = human(player).WalkSpeed }
		receipts[key(player, ability, request.requestId)] = receipt
		local cancel = pendingCancel
		if cancel and cancel.player == player and cancel.ability == ability and request.action == "cast" then
			pendingCancel = nil
			task.delay(0.04, function()
				cancel.at = now()
				if cancel.mode == "dead" then bridge:Invoke("kill", player.UserId)
				else cancel.commandId = beginCommand(cancel.other, "exit") end
			end)
		end
	end))
end
local function watch(player: Player)
	if healthConnections[player] then healthConnections[player]:Disconnect() end
	local value = human(player); value.MaxHealth, value.Health = 1000, 1000
	local previous = value.Health
	losses[player] = {}
	healthConnections[player] = value.HealthChanged:Connect(function(current)
		if current < previous then table.insert(losses[player], { at = now(), amount = previous - current }) end
		previous = current
	end)
end
local function settle(player: Player, position: Vector3)
	bridge:Invoke("place", player.UserId, position)
	waitFor(function() return (command(player, "inspect").position - position).Magnitude < 0.8 end, 5, "Owner did not receive feedback setup placement")
end
local function mark(players: { Player }, ability: string, case: string): { [Player]: number }
	local starts: { [Player]: number } = {}
	for _, player in players do starts[player] = command(player, "feedbackMark", { label = "scenario_begin", data = { ability = ability, case = case, variant = feedbackVariant } }).at end
	return starts
end
local function accepted(state: any, player: Player): any
	for _, event in state.active do if event.owner == player.UserId and event.life == life(player) then return event end end
	error("Accepted input omitted its authoritative action")
end
local function cooldown(player: Player, ability: string)
	local state = command(player, "inspect").states[ability]
	waitFor(function() return now() >= state.readyAt + 0.08 end, 10, "Feedback cooldown did not elapse")
end
local function matching(events: { any }, label: string, ability: string, player: Player, requestId: number?, actionId: number?): { any }
	local found = {}
	for _, event in events do
		local data = event.data
		if event.label ~= label or not data or data.ability ~= ability then continue end
		if data.owner ~= nil and data.owner ~= player.UserId then continue end
		if requestId ~= nil and data.requestId ~= requestId then
			if not actionId or (data.swingId ~= actionId and data.castId ~= actionId) then continue end
		end
		table.insert(found, event)
	end
	return found
end
local function inputWindow(report: any, ability: string, token: number): any
	local code = if ability == "heavy" then "Q" else if ability == "dash" then "E" else "LMB"
	for _, input in report.inputs do if input.code == code and input.life == token then return input end end
	error("Feedback probe omitted actual " .. code .. " input on the tested life")
end
local function collect(players: { Player }, starts: { [Player]: number }): { [Player]: any }
	local result: { [Player]: any } = {}
	for _, player in players do result[player] = command(player, "feedbackInspect", { since = starts[player] - 0.001 }) end
	return result
end
local function traceReceipt(players: { Player }, actor: Player, ability: string, reply: any, active: any?)
	local receipt = receipts[key(actor, ability, reply.requestId)]
	assert(receipt and receipt.life == reply.life, "No exact server receipt for the actual input request/life")
	if active then assert(active.requestId == reply.requestId and math.abs(active.startedAt - receipt.at) < 0.05, "Accepted callback start was not the received request") end
	for _, player in players do
		command(player, "feedbackMark", { label = "server_receipt", data = { serverAt = receipt.at, requestId = reply.requestId, life = reply.life, ability = ability, actor = actor.UserId } })
		if active then command(player, "feedbackMark", { label = "server_accepted", data = { serverAt = active.startedAt, requestId = active.requestId, hitAt = active.hitAt or active.launchAt, ability = ability } }) end
	end
end
local function assertSuccess(players: { Player }, actor: Player, target: Player, ability: string, point: Vector3, expected: number)
	-- A previous action is excluded from the read-only natural-motion calibration.
	-- Wait for an observed quiet window instead of silently measuring with no history.
	waitFor(function() return command(actor, "feedbackInspect").probe.calibration.ready end,
		7, "Feedback did not collect a full pre-input natural joint history")
	local starts = mark(players, ability, "accepted")
	local before = #losses[target]
	local result = command(actor, "cast", { ability = ability, point = point, ok = true })
	local action = accepted(result.state, actor)
	local deadline = action.hitAt or action.launchAt
	traceReceipt(players, actor, ability, result.reply, action)
	waitFor(function() return #losses[target] > before end, 3, "Actual accepted action did not damage its target")
	local hit = losses[target][before + 1]
	assert(hit.amount == expected and hit.at >= deadline - 0.002, "Server damage was early or changed its exact amount")
	waitFor(function() return now() >= deadline + 0.75 end, 3, "Feedback did not reach recovery observation")
	assert(#losses[target] == before + 1, "One actual action damaged the target more than once")
	local reportsByPlayer = collect(players, starts)
	local ownerReport = reportsByPlayer[actor].probe
	local input = inputWindow(ownerReport, ability, result.reply.life)
	assert(input.calibrated and input.historyMinimumSpan >= 0.5 and input.historyMinimumSamples >= 10,
		"Accepted input lacked the required observed natural joint history")
	print("FeedbackCalibration", ability, "variant", feedbackVariant, "samplesMin", input.historyMinimumSamples,
		"spanMin", input.historyMinimumSpan, "policy", input.envelopePolicy, "baselineSource", input.baselineSource,
		"rawToRenderedMax", input.rawToRenderedAngleMax)
	for _, candidate in ownerReport.events do
		local data = candidate.data
		if (candidate.label == "joint_change_candidate" or candidate.label == "joint_simulation_candidate")
			and data and data.inputId == input.inputId then
			print("FeedbackJointCandidate", ability, candidate.label, "joint", data.joint, "at", candidate.at,
				"angle", data.angle, "threshold", data.angleThreshold, "envelope", data.preInputAngleEnvelope,
				"baselineSource", data.baselineSource, "rawDelta", data.rawToRenderedAngle)
		end
	end
	local actionId = action.swingId or action.castId
	local prepared = matching(ownerReport.events, "remote_preparing", ability, actor, result.reply.requestId, actionId)
	assert(#prepared == 1, "One input produced duplicate accepted starts or lost its request correlation")
	for _, event in ownerReport.events do
		if (event.label == "joint_change_candidate" or event.label == "joint_simulation_candidate")
			and event.data.inputId == input.inputId then
			print("FeedbackJointCandidate", ability, feedbackVariant, "input", input.at, "received", prepared[1].at,
				"at", event.at, "joint", event.data.joint, "angle", event.data.angle,
				"translation", event.data.translation, "elapsed", event.data.elapsed)
		end
	end
	if feedbackBaseline then
		assert(input.firstJointChangeSimulation and input.firstJointChange,
			"Preview-off control omitted actual visible preparation joints")
		assert(input.firstJointChangeSimulation >= prepared[1].at - 0.002 and input.firstJointChange >= prepared[1].at - 0.002,
			"Preview-off joint candidate preceded authoritative preparation; it cannot measure confirmation latency")
		assert(input.firstJointChangeSimulation - prepared[1].at <= 0.101 and input.firstJointChange - prepared[1].at <= 0.101,
			"Preview-off accepted action did not produce a visible preparation within 0.1 seconds of receipt")
	else
		assert(input.firstJointChangeSimulation and input.firstJointChangeSimulation - input.at <= 0.101,
			"Actual preparation did not visibly change the simulation joints within 0.1 seconds")
		assert(input.firstJointChange and input.firstJointChange - input.at <= 0.101, "Actual rendered preparation exceeded 0.1 seconds")
		assert(input.firstJointChangeSimulation < prepared[1].at - 0.04, "Measured preparation waited for the authoritative acceptance")
	end
	assert(not input.firstSpeedAboveWalk, "A visual preview was counted as physical acceleration")
	for _, player in players do
		local observed = reportsByPlayer[player]
		local releases = matching(observed.probe.events, "visual_release", ability, actor, nil, nil)
		assert(#releases == 1 and releases[1].at >= deadline - 0.002, "Visual release was early or duplicated on a client")
		local label = if ability == "arrow" then "remote_launched" else "remote_struck"
		local events = matching(observed.probe.events, label, ability, actor, result.reply.requestId, actionId)
		assert(#events == 1 and events[1].at >= deadline - 0.002, "Client received an early/duplicate release")
		assert(observed.driver.physicsViolations == 0 and observed.driver.corrections == 0, "Feedback presentation entered physics or corrected the root")
	end
	print("FeedbackAccepted", ability, "variant", feedbackVariant, "request", result.reply.requestId, "life", result.reply.life,
		"input", input.at, "firstSimulation", input.firstJointChangeSimulation, "firstRendered", input.firstJointChange,
		"acceptedReceived", prepared[1].at, "serverReceived", receipts[key(actor, ability, result.reply.requestId)].at,
		"serverStarted", action.startedAt, "hitAt", deadline, "damageAt", hit.at,
		"inputToSimulation", input.firstJointChangeSimulation - input.at, "inputToRender", input.firstJointChange - input.at,
		"baseline", input.baselineJointStep, "threshold", input.jointThreshold)
end
local ok, problem = xpcall(function()
	waitFor(function() local n = 0; for _ in ready do n += 1 end; return n == 2 end, 60, "Two feedback clients did not initialize")
	local players = Players:GetPlayers(); table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local warrior, warlock = players[1], players[2]
	command(warrior, "class", "warrior"); command(warlock, "class", "warrior"); command(warlock, "class", "warlock")
	command(warrior, "ready"); command(warlock, "ready")
	waitFor(function() return context(warrior).mode == "match" and not context(warrior).frozen end, 8, "Actual R pair did not start feedback match")
	for _, player in players do watch(player) end
	-- Both actors are still on their own original protected pads: input may preview,
	-- but only the server can authorize an attack, so it must reject both classes.
	for _, pair in { { player = warrior, ability = "melee" }, { player = warlock, ability = "arrow" } } do
		local actor, ability = pair.player, pair.ability
		local starts = mark(players, ability, "rejected_spawn")
		local result = command(actor, "cast", { ability = ability, point = root(actor).Position + Vector3.new(0, 0, -10), ok = false, reason = "spawn_protected" })
		traceReceipt(players, actor, ability, result.reply, nil)
		task.wait(0.25)
		local captured = collect(players, starts)
		for _, player in players do
			assert(#matching(captured[player].probe.events, "remote_preparing", ability, actor, result.reply.requestId, nil) == 0
				and #matching(captured[player].probe.events, "visual_release", ability, actor, nil, nil) == 0,
				"Rejected preview became an authoritative/visible release")
		end
		print("FeedbackRejected", ability, result.reply.requestId, result.reply.reason)
	end
	settle(warrior, Vector3.new(5, 3, 40)); settle(warlock, Vector3.new(0, 3, 40)); task.wait(0.3)
	assertSuccess(players, warrior, warlock, "melee", Vector3.new(0, 3, 40), 20)
	assertSuccess(players, warrior, warlock, "heavy", Vector3.new(0, 3, 40), 25)
	assertSuccess(players, warlock, warrior, "arrow", Vector3.new(5, 3, 40), 25)
	-- Dash is measured as a physical event. Its server mover/acceleration latency is
	-- never substituted with the faster visual preparation latency above.
	settle(warrior, Vector3.new(0, 3, 40)); settle(warlock, Vector3.new(0, 3, 60))
	local dashStarts = mark(players, "dash", "physical")
	local moved = command(warrior, "move", { direction = Vector3.xAxis, duration = 1.5, dashAt = 0.3 })
	local dashReports = collect(players, dashStarts)
	local dashInput = inputWindow(dashReports[warrior].probe, "dash", moved.dashReply.life)
	local dashReceipt = receipts[key(warrior, "dash", moved.dashReply.requestId)]
	local moverAt: number? = nil
	for _, event in dashReports[warrior].probe.events do if event.label == "mover_added" then moverAt = event.at; break end end
	assert(moved.dashReply.ok and moved.corrections == 0 and moved.rewinds == 0, "Physical dash introduced a correction")
	assert(dashReceipt and dashReceipt.life == moved.dashReply.life and moverAt, "Physical dash omitted its exact server receipt or actual local mover")
	assert(dashInput.firstRootAcceleration and dashInput.firstSpeedAboveWalk, "No real physical dash acceleration observed")
	print("FeedbackDashPhysical", "input", dashInput.at, "rootAcceleration", dashInput.firstRootAcceleration,
		"speedAboveWalk", dashInput.firstSpeedAboveWalk, "latency", dashInput.firstRootAcceleration - dashInput.at,
		"serverReceived", dashReceipt.at, "requestId", moved.dashReply.requestId, "life", moved.dashReply.life,
		"moverAdded", moverAt, "moverLatency", (moverAt :: number) - dashInput.at,
		"distance", moved.distance, "duration", moved.duration, "samples", moved.samples)
	-- Death is scheduled from the actual server receipt, safely before heavy hitAt.
	cooldown(warrior, "heavy"); settle(warrior, Vector3.new(5, 3, 40)); settle(warlock, Vector3.new(0, 3, 40))
	local deathStarts = mark(players, "heavy", "death_cancel")
	local oldLife, beforeDeathTarget = life(warrior), #losses[warlock]
	pendingCancel = { player = warrior, ability = "heavy", mode = "dead" }
	local dying = command(warrior, "cast", { ability = "heavy", point = Vector3.new(0, 3, 40), ok = true })
	local dyingAction = accepted(dying.state, warrior)
	waitFor(function() return now() > dyingAction.hitAt + 0.3 end, 3, "Death cancellation window did not elapse")
	assert(#losses[warlock] == beforeDeathTarget, "Dead preparation still damaged the opponent")
	local deathReports = collect(players, deathStarts)
	for _, player in players do assert(#matching(deathReports[player].probe.events, "visual_release", "heavy", warrior, nil, nil) == 0, "Death preview released on a client") end
	waitFor(function() return readyLife(warrior, oldLife) end, 9, "Caster did not receive a fresh life after cancelled preparation")
	watch(warrior)
	print("FeedbackDeathCancel", "oldLife", oldLife, "newLife", life(warrior), "request", dying.reply.requestId)
	-- An opponent leaves through actual B while the warlock is still gathering.
	settle(warlock, Vector3.new(0, 3, 40)); settle(warrior, Vector3.new(5, 3, 40)); cooldown(warlock, "arrow")
	local pauseStarts = mark(players, "arrow", "pause_cancel")
	local beforePauseDamage = #losses[warrior]
	local cancellation: any = { player = warlock, other = warrior, ability = "arrow", mode = "pause" }
	pendingCancel = cancellation
	local paused = command(warlock, "cast", { ability = "arrow", point = Vector3.new(5, 3, 40), ok = true })
	local pausedAction = accepted(paused.state, warlock)
	waitFor(function() return cancellation.commandId ~= nil end, 2, "Actual B cancellation was not scheduled")
	finishCommand(warrior, cancellation.commandId)
	waitFor(function() return now() > pausedAction.launchAt + 0.25 end, 3, "Pause cancellation did not reach release deadline")
	assert(#losses[warrior] == beforePauseDamage, "Paused preparation still damaged a target")
	local pauseReports = collect(players, pauseStarts)
	for _, player in players do assert(#matching(pauseReports[player].probe.events, "visual_release", "arrow", warlock, nil, nil) == 0, "Paused arrow visibly launched") end
	local oldArrowLife = paused.reply.life
	waitFor(function()
		return context(warrior).mode == "training" and context(warlock).mode == "training"
			and readyLife(warrior, 0) and readyLife(warlock, oldArrowLife)
	end, 8, "Global pause did not resolve to fresh training lives")
	assert(life(warlock) > oldArrowLife, "Global cancellation did not create a new warlock life")
	command(warrior, "ready"); command(warlock, "ready")
	waitFor(function() return context(warlock).mode == "match" and not context(warlock).frozen end, 8, "New-life real R did not start the next match")
	watch(warrior); watch(warlock)
	settle(warlock, Vector3.new(0, 3, 40)); settle(warrior, Vector3.new(5, 3, 40)); task.wait(0.3)
	assertSuccess(players, warlock, warrior, "arrow", Vector3.new(5, 3, 40), 25)
	for _, player in players do
		local report = command(player, "feedbackInspect")
		assert(report.driver.physicsViolations == 0 and report.driver.heartbeatFrames >= 60 and report.probe.snapshot.simulationFrames >= 60,
			"Feedback observer did not receive real background simulation frames")
		print("FeedbackClientFinal", player.UserId, "life", report.driver.life, "heartbeatFrames", report.driver.heartbeatFrames,
			"renderFrames", report.driver.renderFrames, "simulationFrames", report.probe.snapshot.simulationFrames)
	end
	print("PASS feedback", feedbackVariant, "2 clients: real GUI/R/LMB/Q/E/B, exact request receipt and accepted timing, local joint response, single authoritative/visible release, no early damage, denial/death/pause/new-life cleanup; dash physics reported separately")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
for _, connection in healthConnections do connection:Disconnect() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
