--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local control = ReplicatedStorage:WaitForChild("HeavyTestControl", 20) :: RemoteEvent
local remote = ReplicatedStorage:WaitForChild("HeavyRemote", 20) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction
local ready: { [Player]: boolean } = {}
local reports: { [number]: any } = {}
local connections: { RBXScriptConnection } = {}
local owned: { Instance } = {}
local failure: string? = nil
local sequence = 0
local armed: Player? = nil
local deathTrace: any = nil
table.insert(connections, control.OnServerEvent:Connect(function(player, kind, id, data)
	if kind == "ready" then ready[player] = true
	elseif kind == "failure" then failure = tostring(id)
	elseif kind == "report" then reports[id] = { player = player, report = data } end
end))
local function health(player: Player): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
local function context(player: Player): any return bridge:Invoke("context", player.UserId) end
local function correctionCount(player: Player): number return ((player.Character :: Model):GetAttribute("CombatMovementCorrections") or 0) :: number end
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat
		if failure then error(failure) end
		if predicate() then return end
		task.wait(0.02)
	until os.clock() >= deadline
	error(message)
end
local function command(player: Player, action: string, data: any?): any
	sequence += 1
	local id = sequence
	control:FireClient(player, id, action, data)
	waitFor(function() return reports[id] ~= nil end, 10, "Heavy fixture client timed out: " .. action)
	local response = reports[id]; reports[id] = nil
	assert(response.player == player and response.report.ok, response.report.error)
	return response.report.data
end
local function settle(player: Player, point: Vector3)
	bridge:Invoke("place", player.UserId, point)
	waitFor(function() return (command(player, "inspect").position - point).Magnitude < 1 end, 4, "Heavy owner did not receive placement")
	task.wait(0.1)
end
local function cooldown(player: Player)
	local snapshot = command(player, "inspect").state
	waitFor(function() return workspace:GetServerTimeNow() >= snapshot.readyAt + 0.1 end, 9, "Heavy cooldown did not elapse")
end
local function cast(player: Player, point: Vector3): any return command(player, "cast", { point = point, ok = true }) end
local function active(reply: any, player: Player): any
	for _, swing in reply.state.active do
		assert(swing.style == "heavy", "Heavy snapshot omitted style")
		if swing.owner == player.UserId then return swing end
	end
	error("Accepted actual Q omitted its active authoritative swing")
end
local function longLife(player: Player)
	health(player).MaxHealth, health(player).Health = 1000, 1000
end
local function respawn(player: Player, old: Model)
	local oldLife = old:GetAttribute("CombatLife") :: number
	waitFor(function()
		local character = player.Character
		local currentLife = if character then character:GetAttribute("CombatLife") else nil
		return character ~= nil and character ~= old and type(currentLife) == "number" and currentLife > oldLife
			and character:FindFirstChild("HumanoidRootPart") ~= nil
	end, 12, "Heavy participant did not respawn with a new life")
	waitFor(function() return command(player, "inspect").state.life == (player.Character :: Model):GetAttribute("CombatLife") end,
		5, "Heavy controller did not receive new-life snapshot")
	longLife(player)
end
local function combatPositions(caster: Player, victim: Player)
	settle(caster, Vector3.new(0, 3, -35)); settle(victim, Vector3.new(0, 3, -30))
end
local function hit(caster: Player, victim: Player): (any, number)
	local before = health(victim).Health
	local reply = cast(caster, Vector3.new(0, 3, -30))
	local swing = active(reply, caster)
	assert(math.abs(swing.hitAt - swing.startedAt - 0.65) < 0.001
		and math.abs(swing.expiresAt - swing.hitAt - 0.6) < 0.001, "Heavy preparation/recovery contract changed")
	assert(health(victim).Health == before, "Heavy Q damaged before its preparation completed")
	waitFor(function() return health(victim).Health < before end, 3, "Actual Q did not hit the real opponent")
	assert(health(victim).Health == before - 25 and math.abs(health(victim).WalkSpeed - 9.6) < 0.001,
		"One heavy hit did not apply exactly 25 damage and a 0.6 movement multiplier")
	return reply, before
end
local function busy(caster: Player, first: string, thenAbilities: { string })
	local result = command(caster, "busy", { first = first, thenAbilities = thenAbilities, point = Vector3.new(70, 0, 35) })
	print("HeavyBusy", first, result[first].ok, result[first].reason)
	assert(result[first].ok, "Busy fixture's first action was not accepted: " .. tostring(result[first].reason))
	for _, ability in thenAbilities do
		local refused = result[ability]
		print("HeavyBusyRefusal", first, ability, refused.ok, refused.reason, refused.state.readyAt, result.before[ability])
		assert(not refused.ok and refused.reason == "busy", "Mutually exclusive ability bypassed heavy busy: " .. ability)
		assert(refused.state.readyAt == result.before[ability], "Busy refusal spent an unrelated cooldown: " .. ability)
	end
end
table.insert(connections, remote.OnServerEvent:Connect(function(player: Player, request: any)
	if player ~= armed or type(request) ~= "table" or request.action ~= "cast" then return end
	armed = nil
	task.defer(function()
		deathTrace.receivedAt = workspace:GetServerTimeNow()
		task.wait(0.1)
		deathTrace.killedAt = workspace:GetServerTimeNow()
		bridge:Invoke("kill", player.UserId)
		deathTrace.dead = health(player).Health == 0
	end)
end))
local ok, problem = xpcall(function()
	waitFor(function() local count = 0; for _ in ready do count += 1 end; return count == 2 end, 60, "Two heavy clients did not initialize")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local caster, victim = players[1], players[2]
	command(victim, "probe", { direction = Vector3.new(0, 0, -1), reason = "wrong_class" })
	command(caster, "class", "warrior"); command(victim, "class", "warrior")
	command(caster, "layout"); command(victim, "layout")
	command(caster, "ready"); command(victim, "ready")
	waitFor(function() return context(caster).mode == "match" and not context(caster).frozen end, 8, "Heavy match did not activate")
	longLife(caster); longLife(victim)
	local beforePad = command(caster, "inspect").state.readyAt
	local padRefusal = command(caster, "cast", { point = Vector3.new(0, 3, 80), ok = false, reason = "spawn_protected" })
	print("HeavyPadCooldown", "before", beforePad, "after", padRefusal.state.readyAt, "reason", padRefusal.reason)
	assert(padRefusal.state.readyAt == beforePad, "Protected-pad refusal spent heavy cooldown")
	settle(caster, Vector3.new(70, 3, 55)); settle(victim, Vector3.new(-70, 3, -55))
	busy(caster, "melee", { "heavy" })
	task.wait(0.9)
	busy(caster, "dash", { "heavy" })
	task.wait(0.6)
	busy(caster, "heavy", { "melee", "dash" })
	command(caster, "layout", { cooldown = true })
	cooldown(caster)
	combatPositions(caster, victim)
	local correctionsBefore = correctionCount(victim)
	local landed = hit(caster, victim)
	local delivered = active(landed, caster)
	local moving = command(victim, "slowRunDash")
	assert(correctionCount(victim) == correctionsBefore and moving.corrections == 0, "Slow/dash validation corrected real movement")
	assert(health(victim).WalkSpeed == 16, "Heavy slow failed to expire")
	assert(workspace:GetServerTimeNow() >= delivered.hitAt + 2, "Movement probe did not cover the full slow lease")
	local art = command(caster, "inspect")
	local observer = command(victim, "inspect")
	assert(art.pose ~= nil and art.pose.finite and art.pose.samples >= 10 and art.pose.maximum >= 0.35,
		"Actual heavy Q did not move the live sword hand through a finite preparation/strike")
	assert(observer.observed and observer.contacts >= 1 and observer.struck >= 1,
		"Other player missed actual heavy presentation/contact")
	cooldown(caster)
	combatPositions(caster, victim)
	local wall = Instance.new("Part")
	wall.Name, wall.Size, wall.Position, wall.Anchored = "HeavyTestCover", Vector3.new(14, 10, 0.2), Vector3.new(0, 5, -32.5), true
	wall.Parent = workspace; table.insert(owned, wall)
	local wallHealth = health(victim).Health
	local blocked = active(cast(caster, Vector3.new(0, 3, -30)), caster)
	waitFor(function() return workspace:GetServerTimeNow() > blocked.expiresAt + 0.1 end, 3, "Covered heavy swing did not finish")
	assert(health(victim).Health == wallHealth and health(victim).WalkSpeed == 16, "Heavy struck or slowed through physical cover")
	wall:Destroy()
	cooldown(caster)
	combatPositions(caster, victim)
	local deadCaster = caster.Character :: Model
	local deadLife = deadCaster:GetAttribute("CombatLife") :: number
	local healthBefore = health(victim).Health
	deathTrace, armed = {}, caster
	local cancelled = active(cast(caster, Vector3.new(0, 3, -30)), caster)
	waitFor(function() return deathTrace.dead == true end, 2, "Heavy death fixture did not kill during preparation")
	waitFor(function() return workspace:GetServerTimeNow() > cancelled.hitAt + 0.2 end, 2, "Cancelled heavy hit window did not pass")
	assert(deathTrace.killedAt < cancelled.hitAt and health(victim).Health == healthBefore and health(victim).WalkSpeed == 16,
		"Cancelled heavy preparation damaged or slowed the opponent")
	respawn(caster, deadCaster)
	combatPositions(caster, victim)
	hit(caster, victim)
	local deadVictim = victim.Character :: Model
	local oldVictimBody = health(victim)
	bridge:Invoke("kill", victim.UserId)
	waitFor(function() return oldVictimBody.WalkSpeed == 16 end, 2, "Victim death retained its heavy slow contribution")
	respawn(victim, deadVictim)
	assert(health(victim).WalkSpeed == 16, "Victim new life inherited heavy slow")
	cooldown(caster)
	combatPositions(caster, victim)
	hit(caster, victim)
	deadCaster = caster.Character :: Model
	bridge:Invoke("kill", caster.UserId)
	waitFor(function() return health(victim).WalkSpeed == 16 end, 2, "Caster death did not revoke an already applied heavy slow")
	respawn(caster, deadCaster)
	combatPositions(caster, victim)
	hit(caster, victim)
	command(caster, "exit")
	waitFor(function() return context(victim).frozen and health(victim).WalkSpeed == 16 end, 3, "Real B pause did not clear heavy slow")
	waitFor(function() return context(caster).mode == "training" and context(victim).mode == "training" end, 6, "Interrupted heavy match did not return both participants")
	local stale = command(caster, "probe", { life = deadLife, direction = Vector3.new(0, 0, -1), reason = "stale_life" })
	assert(stale.state.readyAt == 0, "Stale-life refusal spent a fresh heavy cooldown")
	command(caster, "class", "warlock")
	command(caster, "probe", { direction = Vector3.new(0, 0, -1), reason = "wrong_class" })
	task.wait(0.8)
	for _, player in players do
		assert(command(player, "inspect").heavyChildren == 0, "Heavy visuals survived life/class/pause cleanup")
	end
	print("PASS heavy 2 clients: real Q/HUD/class/match, 25 damage/0.6 slow/expiry, real slowed W and E without corrections, busy Q/LMB/E without refused cooldown, wall/pad/wrong-class/stale-life, death preparation cancellation, victim/caster life and real B pause cleanup")
end, debug.traceback)
for _, connection in connections do connection:Disconnect() end
for _, item in owned do item:Destroy() end
game:GetService("StudioTestService"):EndTest({ ok = ok, error = if ok then nil else tostring(problem) })
