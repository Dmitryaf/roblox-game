--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Driver = {}
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.02) until os.clock() >= deadline
	error(message)
end
function Driver.new(player: Player)
	local dash = ReplicatedStorage:WaitForChild("DashRemote", 20) :: RemoteEvent
	local melee = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent
	local match = ReplicatedStorage:WaitForChild("MatchRemote", 20) :: RemoteEvent
	local connections: { RBXScriptConnection } = {}
	local state: any = nil
	local matchState: any = nil
	local replies: { any } = {}
	local meleeReplies: { [number]: any } = {}
	local starts: { any } = {}
	local observed, violations = 0, 0
	local probeId, meleeId, matchId = 500000, 600000, 700000
	local function root(): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
	local function life(): number return (player.Character :: Model):GetAttribute("CombatLife") :: number end
	local function resources(character: Model?): number
		local count = 0
		if not character then return count end
		for _, item in character:GetDescendants() do
			if item.Name == "WarriorDashTrail" or item.Name == "DashTrailLow" or item.Name == "DashTrailHigh"
				or item.Name == "DashLaunchGlint" or item.Name == "WarriorDashWhoosh" then count += 1 end
		end
		return count
	end
	table.insert(connections, dash.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" then table.insert(replies, event) end
		if event.kind == "reply" or event.kind == "snapshot" then state = event.state end
		if event.kind == "started" then
			table.insert(starts, event)
			task.defer(function()
				local owner = game:GetService("Players"):GetPlayerByUserId(event.owner)
				local character = if owner then owner.Character else nil
				if resources(character) > 0 then observed += 1 end
				if character then
					for _, item in character:GetDescendants() do
						if item:IsA("BasePart") and item.Name:find("Dash") and (item.CanQuery or item.CanCollide or item.CanTouch) then violations += 1 end
					end
				end
			end)
		end
	end))
	table.insert(connections, melee.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" then meleeReplies[event.requestId] = event end
	end))
	table.insert(connections, match.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" or event.kind == "snapshot" then matchState = event.state end
	end))
	local function virtual(): any
		local value = UserInputService:CreateVirtualInput()
		assert(value, "VirtualInput unavailable for dash fixture")
		return value
	end
	local function key(code: Enum.KeyCode)
		local input = virtual()
		input:SendKey(true, code, false); input:SendKey(false, code, false)
	end
	local function buttonReady(button: GuiButton, hud: ScreenGui): boolean
		if not hud.Enabled or not button.Active or not button.Visible or button.AbsoluteSize.X <= 0 or button.AbsoluteSize.Y <= 0 then return false end
		local position = button.AbsolutePosition + button.AbsoluteSize / 2
		for _, item in player.PlayerGui:GetGuiObjectsAtPosition(position.X, position.Y) do if item == button then return true end end
		return false
	end
	local function waitButton(button: GuiButton, hud: ScreenGui)
		local ok, problem = pcall(function()
			waitFor(function() return buttonReady(button, hud) end, 5, "Class button not hit-testable after layout/state readiness wait")
		end)
		if not ok then
			local center = button.AbsolutePosition + button.AbsoluteSize / 2
			local camera = workspace.CurrentCamera
			print("ClassButtonDiag", button.Name, "hudEnabled", hud.Enabled, "active", button.Active, "visible", button.Visible,
				"size", button.AbsoluteSize, "position", button.AbsolutePosition, "displayOrder", hud.DisplayOrder)
			print("ClassLayoutDiag", "viewport", if camera then camera.ViewportSize else Vector2.zero,
				"inset", GuiService:GetGuiInset(), "ignoreInset", hud.IgnoreGuiInset, "center", center)
			local parent = button.Parent
			while parent and parent ~= player.PlayerGui do
				if parent:IsA("GuiObject") then print("ClassAncestorDiag", parent.Name, parent.Visible, parent.AbsoluteSize, parent.AbsolutePosition) end
				parent = parent.Parent
			end
			for index, item in player.PlayerGui:GetGuiObjectsAtPosition(center.X, center.Y) do
				if index > 8 then break end
				print("ClassHitDiag", index, item:GetFullName(), "z", item.ZIndex, "visible", item.Visible,
					"active", item.Active, "size", item.AbsoluteSize, "position", item.AbsolutePosition)
			end
		end
		assert(ok and buttonReady(button, hud), tostring(problem))
	end
	local function click(button: GuiButton, hud: ScreenGui)
		waitButton(button, hud)
		local position = button.AbsolutePosition + button.AbsoluteSize / 2
		local point = position + (if hud.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset())
		local input = virtual()
		input:SendMousePosition(point)
		input:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
		input:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
	end
	local function selectClass(classId: string)
		local hud = player.PlayerGui:FindFirstChild("ClassHud") :: ScreenGui
		local button = hud:FindFirstChild(if classId == "warrior" then "WarriorButton" else "WarlockButton", true) :: TextButton
		local old = life()
		click(button, hud)
		waitFor(function()
			return life() > old and (player.Character :: Model):GetAttribute("CombatClass") == classId
				and state ~= nil and state.life == life()
		end, 5, "Real class button did not update dash life")
	end
	local function inspect(): any
		local body = root()
		local remaining = 0
		for _, owner in game:GetService("Players"):GetPlayers() do remaining += resources(owner.Character) end
		local velocity = body:FindFirstChild("WarriorDashVelocity")
		return { position = body.Position, life = life(), classId = (player.Character :: Model):GetAttribute("CombatClass"),
			state = state, matchState = matchState, observed = observed, violations = violations, resources = remaining,
			constraint = velocity ~= nil, attachment = body:FindFirstChild("WarriorDashAttachment") ~= nil,
			health = ((player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid).Health,
			hud = player.PlayerGui:FindFirstChild("DashHud") ~= nil }
	end
	local function eReply(): any
		local before = #replies
		key(Enum.KeyCode.E)
		waitFor(function() return #replies > before end, 5, "Real E produced no production dash reply")
		return replies[#replies]
	end
	local function motion(data: any): any
		local body = root()
		local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		local camera = workspace.CurrentCamera :: Camera
		local oldType, oldFrame = camera.CameraType, camera.CFrame
		local direction: Vector3 = data.direction or Vector3.new(0, 0, -1)
		local center = body.Position
		local frame = CFrame.lookAt(center - direction * 18 + Vector3.new(0, 9, 0), center + direction * 25)
		local input = virtual()
		local aim = RunService.RenderStepped:Connect(function() camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame end)
		camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame
		local sample: RBXScriptConnection? = nil
		local metrics: any = { negativeSteps = 0, backward = 0, samples = 0, constraints = 0,
			postDistance = 0, postTime = 0, minStep = 0, recent = {}, rewinds = {} }
		local ok, problem = xpcall(function()
			local mouse = camera.ViewportSize / 2
			input:SendMousePosition(mouse)
			input:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, true)
			input:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, false)
			task.wait(0.15)
			if data.moving then input:SendKey(true, Enum.KeyCode.W, false); task.wait(0.35) end
			local axis = if data.moving then humanoid.MoveDirection else body.CFrame.LookVector
			axis = (axis * Vector3.new(1, 0, 1)).Unit
			assert(axis.Magnitude > 0.9, "Actual input did not establish dash direction")
			local began, start = os.clock(), body.Position
			local previous, previousAt = start, began
			local beforeStarts = #starts
			sample = RunService.Heartbeat:Connect(function()
				local at, point = os.clock(), body.Position
				local progress, dt = (point - previous):Dot(axis), at - previousAt
				local hasMover = body:FindFirstChild("WarriorDashVelocity") ~= nil
				table.insert(metrics.recent, { time = at - began, dt = dt, progress = progress,
					position = { point.X, point.Y, point.Z }, hasMover = hasMover })
				if #metrics.recent > 12 then table.remove(metrics.recent, 1) end
				metrics.samples += 1
				metrics.minStep = math.min(metrics.minStep, progress)
				if progress < -0.1 then
					metrics.negativeSteps += 1
					if #metrics.rewinds < 4 then table.insert(metrics.rewinds, table.clone(metrics.recent)) end
				end
				if progress < 0 then metrics.backward += -progress end
				if hasMover then metrics.constraints += 1 end
				if at - began >= 1 and data.moving then metrics.postDistance += progress; metrics.postTime += dt end
				previous, previousAt = point, at
			end)
			metrics.reply = eReply()
			assert(metrics.reply.ok, "Motion E rejected: " .. tostring(metrics.reply.reason))
			while os.clock() - began < 1.5 do task.wait(0.02) end
			metrics.duration, metrics.distance = os.clock() - began, (body.Position - start):Dot(axis)
			metrics.lateral = ((body.Position - start) - axis * metrics.distance) * Vector3.new(1, 0, 1)
			metrics.lateral = metrics.lateral.Magnitude
			for index = beforeStarts + 1, #starts do
				if starts[index].owner == player.UserId then metrics.started = starts[index]; break end
			end
			metrics.postSpeed = if metrics.postTime > 0 then metrics.postDistance / metrics.postTime else 0
			metrics.extra = metrics.distance - (if data.moving then 16 * metrics.duration else 0)
			print("DashMotionProbe", if data.moving then "moving" else "idle", "distance", metrics.distance,
				"duration", metrics.duration, "backward", metrics.backward, "rewinds", metrics.negativeSteps,
				"minStep", metrics.minStep, "samples", metrics.samples, "constraintSamples", metrics.constraints,
				"postSpeed", metrics.postSpeed, "extra", metrics.extra, "lateral", metrics.lateral,
				"acceptedDistance", if metrics.started then metrics.started.distance else -1,
				"acceptedDuration", if metrics.started then metrics.started.duration else -1)
			if metrics.negativeSteps > 0 then
				for index, samples in metrics.rewinds do
					print("DashRewindTrace", index, game:GetService("HttpService"):JSONEncode(samples))
				end
				print("DashRecentTrace", game:GetService("HttpService"):JSONEncode(metrics.recent))
			end
			assert(metrics.started and metrics.started.direction:Dot(axis) > 0.98, "Server dash did not follow real MoveDirection/idle facing")
			assert(metrics.samples >= 12 and metrics.constraints > 0, "No actual dash root/constraint samples")
			assert(metrics.negativeSteps == 0 and metrics.backward <= 0.35, "Dash caused backward root corrections")
			assert(metrics.lateral <= 1, "Dash deviated from accepted direction")
			if data.moving then
				assert(metrics.postSpeed >= 14 and metrics.postSpeed <= 18, "Dash failed to restore ordinary running speed")
				assert(metrics.extra >= 7 and metrics.extra <= 17, "Moving E did not provide a bounded extra dash distance")
			else
				assert(metrics.distance >= (data.minimum or 12) and metrics.distance <= (data.maximum or 20), "Idle E dash distance outside accepted range")
			end
		end, debug.traceback)
		input:SendKey(false, Enum.KeyCode.W, false)
		if sample then sample:Disconnect() end
		aim:Disconnect(); camera.CameraType, camera.CFrame = oldType, oldFrame
		assert(ok, tostring(problem) .. "\n" .. game:GetService("HttpService"):JSONEncode(metrics))
		return metrics
	end
	local driver = {}
	function driver.ready()
		waitFor(function()
			return player.Character ~= nil and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
				and state ~= nil and state.life > 0 and matchState ~= nil and player.PlayerGui:FindFirstChild("DashHud") ~= nil
				and player.PlayerGui:FindFirstChild("ClassHud") ~= nil
		end, 45, "Dash controller/HUD did not initialize")
		local hud = player.PlayerGui:FindFirstChild("ClassHud") :: ScreenGui
		waitButton(hud:FindFirstChild("WarriorButton", true) :: TextButton, hud)
	end
	function driver.run(action: string, data: any?): any
		if action == "inspect" then return inspect()
		elseif action == "class" then selectClass(data :: string); return inspect()
		elseif action == "motion" then return motion(data)
		elseif action == "key" then return eReply()
		elseif action == "ready" then key(Enum.KeyCode.R)
		elseif action == "exitAt" then
			task.spawn(function()
				while workspace:GetServerTimeNow() < data do task.wait(0.005) end
				matchId += 1; match:FireServer({ action = "exit", requestId = matchId, matchId = matchState.matchId })
			end)
		elseif action == "eAt" then
			while workspace:GetServerTimeNow() < data do task.wait(0.005) end
			return eReply()
		elseif action == "cancelClass" then
			local before = #replies
			key(Enum.KeyCode.E); task.wait(0.04); selectClass("warlock")
			waitFor(function() return #replies > before end, 4, "Class cancellation E got no reply")
			return replies[before + 1]
		elseif action == "busy" then
			meleeId += 1
			local timeline: any = { mode = data }
			local function swing()
				timeline.sentMeleeAt = workspace:GetServerTimeNow()
				melee:FireServer({ action = "cast", requestId = meleeId, life = life(), direction = Vector3.new(0, 0, -1) })
			end
			local function sendE() timeline.sentEKeyAt = workspace:GetServerTimeNow(); key(Enum.KeyCode.E) end
			local before = #replies
			if data == "meleeFirst" then swing(); task.wait(0.04); sendE()
			else
				local seen = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
					if input.KeyCode == Enum.KeyCode.E then
						timeline.observedEAt, timeline.inputProcessed = workspace:GetServerTimeNow(), processed
					end
				end)
				local inputOk, inputProblem = pcall(function()
					sendE()
					waitFor(function() return timeline.observedEAt ~= nil end, 3, "Virtual E did not enter the actual input stream")
				end)
				seen:Disconnect()
				assert(inputOk, tostring(inputProblem))
				task.wait(0.04); swing()
			end
			waitFor(function() return #replies > before and meleeReplies[meleeId] ~= nil end, 5, "Busy probes did not receive both replies")
			timeline.repliedAt = workspace:GetServerTimeNow()
			return { dash = replies[before + 1], melee = meleeReplies[meleeId], timeline = timeline }
		elseif action == "probe" then
			probeId += 1
			local before = #replies
			dash:FireServer({ action = "cast", requestId = probeId, life = data.life or life(), direction = data.direction })
			if data.silent then task.wait(0.65); assert(#replies == before, "Malformed zero direction reached application"); return inspect() end
			waitFor(function() return #replies > before end, 4, "Dash refusal probe received no reply")
			local reply = replies[#replies]
			assert(reply.ok == data.ok and reply.reason == data.reason, "Unexpected dash refusal: " .. tostring(reply.reason))
			return reply
		else error("Unknown dash fixture command: " .. action) end
		return inspect()
	end
	function driver.destroy() for _, connection in connections do connection:Disconnect() end end
	return driver
end
return Driver
