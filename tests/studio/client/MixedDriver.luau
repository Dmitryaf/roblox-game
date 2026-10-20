--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Driver = {}
local folders: { [string]: string } = { arrow = "LocalArrowEffects", hands = "LocalHandsEffects", melee = "LocalMeleeEffects", heavy = "LocalHeavyEffects", dash = "LocalDashEffects" }
local remoteNames: { [string]: string } = { arrow = "ArrowRemote", hands = "HandsRemote", melee = "MeleeRemote", heavy = "HeavyRemote", dash = "DashRemote" }
local attached = {
	MovingSwordEdge = "melee", SwordTrailHeel = "melee", SwordTrailTip = "melee", WarriorSwordBrace = "melee",
	HeavySwordEdge = "heavy", HeavyTrailHeel = "heavy", HeavyTrailTip = "heavy", HeavyBladePreparation = "heavy", WarriorHeavyBrace = "heavy",
	WarriorDashTrail = "dash", DashTrailLow = "dash", DashTrailHigh = "dash", DashLaunchGlint = "dash", WarriorDashWhoosh = "dash",
}

function Driver.new(player: Player)
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local loadModule = require :: any
	local ClassDriver: any = loadModule(ReplicatedStorage:WaitForChild("MixedClassDriver", 20) :: ModuleScript)
	local selection = ClassDriver.new(player)
	local remotes: { [string]: RemoteEvent } = {}
	local replies: { [string]: { any } } = {}
	local latest: { [string]: number } = {}
	local states: { [string]: any } = {}
	local events: { [string]: { [string]: number } } = {}
	local visuals: { [string]: any } = {}
	local contacts, ownContacts = { melee = 0, heavy = 0 }, { melee = 0, heavy = 0 }
	local connections: { RBXScriptConnection } = {}
	local healthConnections: { RBXScriptConnection } = {}
	local damageByLife: { [number]: any } = {}
	local cumulativeDamage, damageEvents, physicsViolations, renderFrames, heartbeatFrames = 0, 0, 0, 0, 0
	local badParts: { [Instance]: boolean } = {}
	local firstPhysics, failure: string? = nil, nil
	local lastScan, busy, stopped = 0, false, false
	local cleanupInput: (() -> ())? = nil
	local function waitFor(predicate: () -> boolean, seconds: number, message: string)
		local deadline = os.clock() + seconds
		repeat
			assert(not stopped, "Mixed driver destroyed while waiting")
			if predicate() then return end
			task.wait(0.02)
		until os.clock() >= deadline
		error(message)
	end
	local function root(): BasePart
		local character = player.Character
		local body = if character then character:FindFirstChild("HumanoidRootPart") else nil
		assert(body and body:IsA("BasePart"), "Current body root absent")
		return body
	end
	local function human(): Humanoid
		local value = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
		assert(value, "Current Humanoid absent"); return value
	end
	local function life(): number return ((player.Character :: Model):GetAttribute("CombatLife") or 0) :: number end
	local function corrections(): number return ((player.Character :: Model):GetAttribute("CombatMovementCorrections") or 0) :: number end
	local function bindHealth(character: Model)
		for _, connection in healthConnections do connection:Disconnect() end; table.clear(healthConnections)
		local current: Humanoid? = nil
		local function watch()
			local value = character:FindFirstChildOfClass("Humanoid")
			if not value or value == current then return end
			current = value
			local previous = value.Health
			table.insert(healthConnections, value.HealthChanged:Connect(function(health: number)
				local lost = math.max(0, previous - health); previous = health
				if lost <= 0 then return end
				local token = (character:GetAttribute("CombatLife") or 0) :: number
				local record = damageByLife[token] or { damage = 0, events = 0 }
				record.damage += lost; record.events += 1; damageByLife[token] = record
				cumulativeDamage += lost; damageEvents += 1
			end))
		end
		table.insert(healthConnections, character.ChildAdded:Connect(watch)); watch()
	end
	table.insert(connections, player.CharacterAdded:Connect(bindHealth))
	if player.Character then bindHealth(player.Character) end
	for key, name in folders do
		replies[key], latest[key], events[key], visuals[key] = {}, 0, {}, { live = 0, seen = 0, peak = 0 }
		local remote = ReplicatedStorage:WaitForChild(remoteNames[key], 20) :: RemoteEvent
		remotes[key] = remote
		table.insert(connections, remote.OnClientEvent:Connect(function(event: any)
			if type(event) ~= "table" then return end
			if event.kind == "reply" then
				table.insert(replies[key], { event = event, at = workspace:GetServerTimeNow() })
				latest[key] = math.max(latest[key], event.requestId)
			end
			if event.kind == "reply" or event.kind == "snapshot" then states[key] = event.state end
			events[key][event.kind] = (events[key][event.kind] or 0) + 1
			if event.kind == "contact" and (key == "melee" or key == "heavy") then
				contacts[key] += 1
				if event.owner == player.UserId then ownContacts[key] += 1 end
			end
		end))
	end
	local match = ReplicatedStorage:WaitForChild("MatchRemote", 20) :: RemoteEvent
	local matchReplies: { any } = {}
	local matchState: any = nil
	local matchLatest = 0
	table.insert(connections, match.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" then table.insert(matchReplies, event); matchLatest = math.max(matchLatest, event.requestId) end
		if event.kind == "reply" or event.kind == "snapshot" then matchState = event.state end
	end))
	local function violation(part: Instance, message: string)
		if badParts[part] then return end
		badParts[part] = true; physicsViolations += 1; firstPhysics = firstPhysics or message
	end
	local function scan()
		local counts: { [string]: number } = {}
		local include: { Instance } = {}
		for key, name in folders do
			counts[key] = 0
			local folder = workspace:FindFirstChild(name)
			if not folder then continue end
			table.insert(include, folder)
			local descendants = folder:GetDescendants(); counts[key] += #descendants
			for _, object in descendants do
				if object:IsA("BasePart") and (not object.Anchored or object.CanCollide or object.CanQuery or object.CanTouch) then
					violation(object, "Ability VFX entered physics: " .. object:GetFullName())
				end
			end
		end
		for _, owner in Players:GetPlayers() do
			if not owner.Character then continue end
			for _, object in owner.Character:GetDescendants() do
				local key = (attached :: { [string]: string })[object.Name]
				if key then counts[key] += 1 end
			end
			for _, name in { "WarriorArmour", "WarlockCostume" } do
				local costume = owner.Character:FindFirstChild(name)
				if not costume then continue end
				for _, object in costume:GetDescendants() do
					if object:IsA("BasePart") and (not object.Massless or object.CanCollide or object.CanQuery or object.CanTouch) then
						violation(object, "Class appearance entered physics: " .. object:GetFullName())
					end
				end
			end
		end
		if #include > 0 then
			local query = OverlapParams.new(); query.FilterType, query.FilterDescendantsInstances, query.RespectCanCollide = Enum.RaycastFilterType.Include, include, false
			for _, part in workspace:GetPartBoundsInBox(CFrame.new(0, 10, 0), Vector3.new(450, 100, 450), query) do violation(part, "Ability VFX entered combat overlap") end
		end
		for key, count in counts do
			visuals[key].live, visuals[key].peak = count, math.max(visuals[key].peak, count)
			if count > 0 then visuals[key].seen += 1 end
		end
	end
	table.insert(connections, RunService.RenderStepped:Connect(function() renderFrames += 1 end))
	table.insert(connections, RunService.Heartbeat:Connect(function()
		heartbeatFrames += 1
		if os.clock() - lastScan < 0.08 then return end
		lastScan = os.clock()
		local ok, problem = pcall(function() scan(); return true end); if not ok then failure = tostring(problem) end
	end))
	local function inspect(): any
		assert(not failure, failure); scan()
		local damage = damageByLife[life()] or { damage = 0, events = 0 }
		return { sampledAt = workspace:GetServerTimeNow(), position = root().Position, health = human().Health, speed = human().WalkSpeed, life = life(), classId = (player.Character :: Model):GetAttribute("CombatClass"),
			team = (player.Character :: Model):GetAttribute("MatchTeam"), corrections = corrections(), states = states, matchState = matchState,
			visuals = visuals, events = events, contacts = contacts, ownContacts = ownContacts, physicsViolations = physicsViolations, firstPhysicsViolation = firstPhysics,
			cumulativeDamage = cumulativeDamage, cumulativeDamageLife = damage.damage, damageEvents = damageEvents, lifeDamageEvents = damage.events,
			renderFrames = renderFrames, heartbeatFrames = heartbeatFrames }
	end
	local function virtual(): any local input = UserInputService:CreateVirtualInput(); assert(input, "VirtualInput unavailable for mixed combat"); return input end
	local function tap(input: any, ability: string, mouse: Vector2)
		local function matches(event: InputObject): boolean
			return if ability == "arrow" or ability == "melee" then event.UserInputType == Enum.UserInputType.MouseButton1
				else event.KeyCode == (if ability == "hands" or ability == "heavy" then Enum.KeyCode.Q else if ability == "ready" then Enum.KeyCode.R else if ability == "exit" then Enum.KeyCode.B else if ability == "transfer" then Enum.KeyCode.F else Enum.KeyCode.E)
		end
		local observed = false
		local listener = UserInputService.InputBegan:Connect(function(event) if matches(event) then observed = true end end)
		local ok, problem = pcall(function()
			if ability == "arrow" or ability == "melee" then
				input:SendMouseButton(mouse, Enum.UserInputType.MouseButton1, true); input:SendMouseButton(mouse, Enum.UserInputType.MouseButton1, false)
			else
				local code = if ability == "hands" or ability == "heavy" then Enum.KeyCode.Q else if ability == "ready" then Enum.KeyCode.R else if ability == "exit" then Enum.KeyCode.B else if ability == "transfer" then Enum.KeyCode.F else Enum.KeyCode.E
				input:SendKey(true, code, false); input:SendKey(false, code, false)
			end
			waitFor(function() return observed end, 3, "Mixed ability never entered actual input stream: " .. ability)
		end)
		listener:Disconnect(); assert(ok, tostring(problem))
	end
	local function withView(frame: CFrame, action: (any, Camera) -> any): any
		local camera = workspace.CurrentCamera :: Camera
		local oldType, oldFrame = camera.CameraType, camera.CFrame
		local function view() camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame end
		local render, heartbeat = RunService.RenderStepped:Connect(view), RunService.Heartbeat:Connect(view)
		local input = virtual(); view()
		local function cleanup()
			input:SendKey(false, Enum.KeyCode.W, false)
			render:Disconnect(); heartbeat:Disconnect(); camera.CameraType, camera.CFrame = oldType, oldFrame
		end
		cleanupInput = cleanup
		local ok, result = xpcall(function()
			local mouse = camera.ViewportSize / 2
			input:SendMousePosition(mouse); input:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, true); input:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, false)
			task.wait(0.12)
			return action(input, camera)
		end, debug.traceback)
		cleanup(); cleanupInput = nil; assert(ok, tostring(result)); return result
	end
	local function waitReply(key: string, before: number, token: number): any
		local reply: any = nil
		waitFor(function()
			for _, item in replies[key] do if item.event.requestId > before and item.event.life == token then reply = item; return true end end
			return false
		end, 5, "Actual input produced no production " .. key .. " reply")
		return reply
	end
	local function cast(data: any): any
		local ability: string = data.ability
		local key = if (ability == "teleport" or ability == "transfer") then "arrow" else ability
		assert(remotes[key], "Unknown ability " .. ability)
		local function perform(input: any, mouse: Vector2): any
			local before, token, sentAt = latest[key], life(), workspace:GetServerTimeNow()
			tap(input, ability, mouse)
			local item = waitReply(key, before, token); local reply = item.event
			assert(reply.ok == data.ok and (not data.reason or reply.reason == data.reason), ability .. " result: " .. tostring(reply.reason))
			return { reply = reply, state = reply.state, ability = ability, sentAt = sentAt, repliedAt = item.at, inspect = inspect() }
		end
		if ability == "teleport" or ability == "transfer" then return perform(virtual(), UserInputService:GetMouseLocation()) end
		local point: Vector3 = data.point or root().Position + root().CFrame.LookVector * 10
		return withView(CFrame.lookAt(point + Vector3.new(14, 16, 18), point), function(input, camera)
			local projected, visible = camera:WorldToViewportPoint(point); assert(visible, "Mixed aim target outside viewport")
			local mouse = Vector2.new(projected.X, projected.Y); input:SendMousePosition(mouse)
			return perform(input, mouse)
		end)
	end
	local function move(data: any): any
		local body, humanoid, token = root(), human(), life()
		local flat = data.direction * Vector3.new(1, 0, 1); assert(flat.Magnitude > 0.1, "Movement axis absent")
		local axis = flat.Unit
		local frame = CFrame.lookAt(body.Position - axis * 18 + Vector3.new(0, 9, 0), body.Position + axis * 25)
		return withView(frame, function(input, camera)
			local before, began, start = corrections(), os.clock(), body.Position
			local previous, previousAt, speed, stableSince, lastDash = start, began, humanoid.WalkSpeed, began, began
			local previousVelocity, previousCorrections = body.AssemblyLinearVelocity, before
			local metrics: any = { start = start, samples = 0, rewinds = 0, backward = 0, maxStep = 0, stableSpeedSegments = {},
				rewindTrace = {}, correctionsBefore = before }
			for _, value in { "10.4", "9.6", "16" } do metrics.stableSpeedSegments[value] = { distance = 0, time = 0, samples = 0, speed = 0 } end
			local sample = RunService.Heartbeat:Connect(function()
				local at, point = os.clock(), body.Position
				local dt, progress = at - previousAt, (point - previous):Dot(axis)
				local velocity, currentCorrections = body.AssemblyLinearVelocity, corrections()
				local nearest: any = nil
				for _, other in Players:GetPlayers() do
					local character = other.Character
					if other == player or not character or not character.Parent then continue end
					local otherRoot = character:FindFirstChild("HumanoidRootPart")
					if not otherRoot or not otherRoot:IsA("BasePart") then continue end
					local gap = (otherRoot.Position - point).Magnitude
					if not nearest or gap < nearest.gap then
						nearest = { owner = other.UserId, name = other.Name, character = character:GetFullName(),
							root = otherRoot.Name, position = otherRoot.Position, gap = gap }
					end
				end
				if nearest then metrics.minOtherRootGap = math.min(metrics.minOtherRootGap or math.huge, nearest.gap) end
				metrics.samples += 1; metrics.maxStep = math.max(metrics.maxStep, progress)
				if progress < -0.1 then
					metrics.rewinds += 1
					if #metrics.rewindTrace < 4 then
						table.insert(metrics.rewindTrace, { at = workspace:GetServerTimeNow(), dt = dt, progress = progress,
							previous = previous, current = point, previousVelocity = previousVelocity, velocity = velocity,
							correctionsBefore = previousCorrections, correctionsAfter = currentCorrections, other = nearest })
					end
				end
				if progress < 0 then metrics.backward += -progress end
				local mover = body:FindFirstChild("WarriorDashVelocity")
				local dashing = mover ~= nil and mover:IsA("LinearVelocity") and mover.Enabled
				if dashing then lastDash = at end
				if humanoid.WalkSpeed ~= speed then speed, stableSince = humanoid.WalkSpeed, at end
				if dt > 0 and at - began >= 0.2 and at - stableSince >= 0.12 and at - lastDash >= 0.16
					and not dashing and humanoid.MoveDirection:Dot(axis) > 0.98 and math.abs(body.AssemblyLinearVelocity.Y) < 4 then
					for _, value in { "10.4", "9.6", "16" } do
						if math.abs(speed - (tonumber(value) :: number)) < 0.05 then
							local segment = metrics.stableSpeedSegments[value]; segment.distance += progress; segment.time += dt; segment.samples += 1
						end
					end
				end
				previous, previousAt = point, at
				previousVelocity, previousCorrections = velocity, currentCorrections
			end)
			local ok, problem = xpcall(function()
				input:SendKey(true, Enum.KeyCode.W, false)
				local dashed = false
				while os.clock() - began < data.duration do
					assert(not stopped and life() == token, "Movement life changed during the probe")
					if data.dashAt and not dashed and os.clock() - began >= data.dashAt then
						dashed = true; local prior = latest.dash
						tap(input, "dash", camera.ViewportSize / 2); metrics.dashReply = waitReply("dash", prior, token).event
						assert(metrics.dashReply.ok, "Moving E rejected: " .. tostring(metrics.dashReply.reason))
					end
					task.wait(0.01)
				end
			end, debug.traceback)
			input:SendKey(false, Enum.KeyCode.W, false); sample:Disconnect(); assert(ok, tostring(problem))
			metrics.finish, metrics.duration, metrics.corrections = body.Position, os.clock() - began, corrections() - before
			metrics.correctionsAfter = corrections()
			metrics.distance = (body.Position - start):Dot(axis)
			metrics.lateral = ((body.Position - start) - axis * metrics.distance) * Vector3.new(1, 0, 1); metrics.lateral = metrics.lateral.Magnitude
			for _, segment in metrics.stableSpeedSegments do if segment.time > 0 then segment.speed = segment.distance / segment.time end end
			metrics.inspect = inspect(); return metrics
		end)
	end
	local driver = {}
	function driver.ready()
		selection.ready()
		waitFor(function()
			for key in folders do if not states[key] or states[key].life ~= life() or states[key].life <= 0 then return false end end
			return matchState ~= nil and playerGui:FindFirstChild("HeavyHud") ~= nil
		end, 45, "Mixed production controllers/states/HUD did not initialize")
	end
	function driver.run(action: string, data: any?): any
		if action == "inspect" then return inspect() end
		assert(not busy, "Mixed driver already owns an input action")
		busy = true
		local ok, result = xpcall(function()
			if action == "class" then
				if (player.Character :: Model):GetAttribute("CombatClass") ~= data then selection.run("class", data) end
				return inspect()
			elseif action == "cast" then return cast(data)
            elseif action == "tap" then
                tap(virtual(), data.ability, UserInputService:GetMouseLocation())
                return inspect()
			elseif action == "move" then return move(data)
			elseif action == "ready" or action == "exit" then
				local before = matchLatest
				tap(virtual(), action, UserInputService:GetMouseLocation())
				local reply: any = nil
				waitFor(function() for _, value in matchReplies do if value.requestId > before then reply = value; return true end end; return false end,
					5, "Real match key produced no reply")
				assert(reply.ok, "Real match key rejected: " .. tostring(reply.reason)); return inspect()
			else error("Unknown mixed fixture action: " .. action) end
		end, debug.traceback)
		busy = false; assert(ok, tostring(result)); return result
	end
	function driver.destroy()
		stopped = true
		if cleanupInput then cleanupInput(); cleanupInput = nil end
		for _, connection in connections do connection:Disconnect() end
		for _, connection in healthConnections do connection:Disconnect() end
		selection.destroy()
	end
	return driver
end
return Driver
