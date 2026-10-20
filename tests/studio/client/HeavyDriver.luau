--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Driver = {}
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.02) until os.clock() >= deadline
	error(message)
end
function Driver.new(player: Player)
	local loadModule = require :: any
	local ClassDriver: any = loadModule(ReplicatedStorage:WaitForChild("HeavyClassDriver", 20) :: ModuleScript)
	local selection = ClassDriver.new(player)
	local remotes: { [string]: RemoteEvent } = {
		heavy = ReplicatedStorage:WaitForChild("HeavyRemote", 20) :: RemoteEvent,
		melee = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent,
		dash = ReplicatedStorage:WaitForChild("DashRemote", 20) :: RemoteEvent,
	}
	local replies: { [string]: { any } } = { heavy = {}, melee = {}, dash = {} }
	local states: { [string]: any } = {}
	local connections: { RBXScriptConnection } = {}
	local probeId = 900000
	local preparing, struck, contacts, observed = 0, 0, 0, false
	local eventFailure: string? = nil
	local pose: any = nil
	local lastPose: any = nil
	local function root(): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
	local function humanoid(): Humanoid return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid end
	local function life(): number return (player.Character :: Model):GetAttribute("CombatLife") :: number end
	local function corrections(): number return ((player.Character :: Model):GetAttribute("CombatMovementCorrections") or 0) :: number end
	local function visual(): number
		local folder = workspace:FindFirstChild("LocalHeavyEffects")
		if not folder then return 0 end
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch, "Heavy art entered physics")
			end
		end
		return #folder:GetChildren()
	end
	local function observeVisual()
		local ok, count = pcall(visual)
		if not ok then eventFailure = tostring(count) elseif count > 0 then observed = true end
	end
	for key, remote in remotes do
		table.insert(connections, remote.OnClientEvent:Connect(function(event: any)
			if event.kind == "reply" then table.insert(replies[key], event) end
			if event.kind == "reply" or event.kind == "snapshot" then states[key] = event.state end
			if key ~= "heavy" then return end
			if event.kind == "preparing" then
				preparing += 1
				task.defer(observeVisual)
			elseif event.kind == "struck" then struck += 1; task.defer(observeVisual)
			elseif event.kind == "contact" then contacts += 1; task.defer(observeVisual) end
			if event.kind == "preparing" or event.kind == "struck" or event.kind == "contact" or event.kind == "ended" then
				if event.style ~= "heavy" then eventFailure = "Heavy presentation event omitted its authoritative style" end
			end
		end))
	end
	table.insert(connections, RunService.Heartbeat:Connect(function()
		if not pose then return end
		if not pose.hand.Parent or not pose.body.Parent or os.clock() >= pose.untilAt then lastPose = pose; pose = nil; return end
		local relative = pose.body.CFrame:ToObjectSpace(pose.hand.CFrame)
		local distance = (relative.Position - pose.rest.Position).Magnitude
		pose.finite = pose.finite and distance == distance and distance < 100
		pose.maximum = math.max(pose.maximum, distance)
		pose.samples += 1
	end))
	local function input(): any
		local value = UserInputService:CreateVirtualInput(); assert(value, "VirtualInput unavailable for heavy fixture"); return value
	end
	local function key(code: Enum.KeyCode)
		local virtual = input()
		virtual:SendKey(true, code, false); virtual:SendKey(false, code, false)
	end
	local function beginPose()
		local character = player.Character :: Model
		local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart
		pose = { hand = hand, body = root(), rest = root().CFrame:ToObjectSpace(hand.CFrame), untilAt = os.clock() + 2,
			maximum = 0, samples = 0, finite = true }
	end
	local function withAim(point: Vector3, action: (any, Vector2) -> any): any
		local camera = workspace.CurrentCamera :: Camera
		local oldType, oldFrame = camera.CameraType, camera.CFrame
		local frame = CFrame.lookAt(point + Vector3.new(14, 16, 18), point)
		camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame
		local aim = RunService.RenderStepped:Connect(function() camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame end)
		local virtual = input()
		local projected, visible = camera:WorldToViewportPoint(point)
		assert(visible, "Heavy aim target outside viewport")
		local mouse = Vector2.new(projected.X, projected.Y)
		virtual:SendMousePosition(mouse)
		virtual:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, true)
		virtual:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, false)
		task.wait(0.12)
		local ok, result = xpcall(function() return action(virtual, mouse) end, debug.traceback)
		aim:Disconnect(); camera.CameraType, camera.CFrame = oldType, oldFrame
		assert(ok, tostring(result))
		return result
	end
	local function activate(ability: string, virtual: any, point: Vector2)
		local observedInput = false
		local listener = UserInputService.InputBegan:Connect(function(event: InputObject)
			if (ability == "heavy" and event.KeyCode == Enum.KeyCode.Q) or (ability == "dash" and event.KeyCode == Enum.KeyCode.E)
				or (ability == "melee" and event.UserInputType == Enum.UserInputType.MouseButton1) then observedInput = true end
		end)
		local ok, problem = pcall(function()
			if ability == "melee" then
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
			else
				if ability == "heavy" then beginPose() end
				local code = if ability == "heavy" then Enum.KeyCode.Q else Enum.KeyCode.E
				virtual:SendKey(true, code, false); virtual:SendKey(false, code, false)
			end
			waitFor(function() return observedInput end, 3, "Requested ability never entered real input stream")
		end)
		listener:Disconnect(); assert(ok, tostring(problem))
	end
	local function inspect(): any
		assert(not eventFailure, eventFailure)
		local p = pose or lastPose
		return { position = root().Position, health = humanoid().Health, speed = humanoid().WalkSpeed,
			life = life(), state = states.heavy, heavyChildren = visual(), preparing = preparing, struck = struck,
			contacts = contacts, observed = observed, corrections = corrections(),
			pose = if p then { maximum = p.maximum, samples = p.samples, finite = p.finite } else nil,
			hud = player.PlayerGui:FindFirstChild("HeavyHud") ~= nil }
	end
	local function layout(data: any?): any
		local hud = player.PlayerGui:FindFirstChild("HeavyHud") :: ScreenGui
		local label = hud:FindFirstChild("Ability") :: TextLabel
		waitFor(function()
			return hud.Enabled and label.AbsoluteSize.X > 0 and label.AbsoluteSize.Y > 0
				and label.Text:find("Q", 1, true) ~= nil
		end, 4, "Heavy HUD did not expose its Q hint")
		if data and data.cooldown then
			waitFor(function() return label.Text:find("Восстановление", 1, true) ~= nil end, 4, "Heavy HUD did not show its real cooldown")
		end
		local viewport = (workspace.CurrentCamera :: Camera).ViewportSize
		local guiInset = game:GetService("GuiService"):GetGuiInset()
		local position = label.AbsolutePosition + (if hud.IgnoreGuiInset then Vector2.zero else guiInset)
		assert(position.X >= 0 and position.Y >= 0 and position.X + label.AbsoluteSize.X <= viewport.X + 1
			and position.Y + label.AbsoluteSize.Y <= viewport.Y + 1, "Heavy ability label left the actual PC viewport")
		for _, name in { "DashHud", "MeleeHud" } do
			local otherHud = player.PlayerGui:FindFirstChild(name) :: ScreenGui
			local other = otherHud:FindFirstChild("Ability") :: TextLabel
			local a, b, sa, sb = label.AbsolutePosition, other.AbsolutePosition, label.AbsoluteSize, other.AbsoluteSize
			local intersects = a.X < b.X + sb.X and a.X + sa.X > b.X and a.Y < b.Y + sb.Y and a.Y + sa.Y > b.Y
			assert(not intersects, "Heavy HUD overlaps " .. name)
		end
		assert(label.TextBounds.X <= label.AbsoluteSize.X + 1 and label.TextBounds.Y <= label.AbsoluteSize.Y + 1,
			"Heavy Q/status text overflowed its ability panel")
		print("HeavyHudLayout", viewport, label.AbsolutePosition, label.AbsoluteSize, label.TextBounds, label.Text)
		return { viewport = viewport, text = label.Text }
	end
	local function slowRunDash(): any
		local body, human = root(), humanoid()
		assert(math.abs(human.WalkSpeed - 9.6) < 0.01, "Slow movement probe did not start under actual heavy slow")
		local camera = workspace.CurrentCamera :: Camera
		local oldType, oldFrame = camera.CameraType, camera.CFrame
		local frame = CFrame.lookAt(body.Position + Vector3.new(-18, 9, 0), body.Position + Vector3.xAxis * 25)
		local view = RunService.RenderStepped:Connect(function() camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame end)
		camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame
		local virtual = input()
		local center = camera.ViewportSize / 2
		virtual:SendMousePosition(center)
		virtual:SendMouseButton(center, Enum.UserInputType.MouseButton2, true); virtual:SendMouseButton(center, Enum.UserInputType.MouseButton2, false)
		local before, beforeDash = corrections(), #replies.dash
		local began, previousAt, previous = os.clock(), os.clock(), body.Position
		local m: any = { slowDistance = 0, slowTime = 0, normalDistance = 0, normalTime = 0, slowSamples = 0, normalSamples = 0,
			negativeSteps = 0, backward = 0, maxExcess = 0, samples = 0 }
		local sampled = RunService.Heartbeat:Connect(function()
			local at, point = os.clock(), body.Position
			local age, dt = at - began, at - previousAt
			local progress = point.X - previous.X
			local mover = body:FindFirstChild("WarriorDashVelocity")
			local dashing = mover ~= nil and mover:IsA("LinearVelocity") and mover.Enabled
			if age >= 0.2 and dt > 0 then
				m.samples += 1
				if progress < -0.1 then m.negativeSteps += 1 end
				if progress < 0 then m.backward += -progress end
				m.maxExcess = math.max(m.maxExcess, progress - (if dashing then 16 / 0.28 else 16) * dt)
				if not dashing and (age < 0.25 or age > 1.05) then
					if math.abs(human.WalkSpeed - 9.6) < 0.01 then m.slowDistance += progress; m.slowTime += dt; m.slowSamples += 1
					elseif human.WalkSpeed == 16 then m.normalDistance += progress; m.normalTime += dt; m.normalSamples += 1 end
				end
			end
			previous, previousAt = point, at
		end)
		local ok, problem = xpcall(function()
			virtual:SendKey(true, Enum.KeyCode.W, false)
			while os.clock() - began < 0.3 do task.wait(0.01) end
			activate("dash", virtual, center)
			while os.clock() - began < 3.5 do task.wait(0.02) end
		end, debug.traceback)
		virtual:SendKey(false, Enum.KeyCode.W, false)
		sampled:Disconnect(); view:Disconnect(); camera.CameraType, camera.CFrame = oldType, oldFrame
		task.wait(0.35)
		m.corrections, m.dashAccepted = corrections() - before, #replies.dash > beforeDash and replies.dash[beforeDash + 1].ok
		m.slowSpeed, m.normalSpeed = m.slowDistance / m.slowTime, m.normalDistance / m.normalTime
		print("HeavySlowMotion", player.UserId, "slow", m.slowSpeed, m.slowSamples, "normal", m.normalSpeed, m.normalSamples,
			"rewinds", m.negativeSteps, "backward", m.backward, "excess", m.maxExcess, "corrections", m.corrections)
		assert(ok, tostring(problem))
		assert(m.dashAccepted and m.corrections == 0 and m.negativeSteps == 0 and m.maxExcess <= 0.75, "Slow/dash introduced a root correction or unexplained jump")
		assert(m.slowSamples >= 6 and m.slowSpeed >= 8.4 and m.slowSpeed <= 10.8, "Real W did not respect the 9.6 slow speed")
		assert(m.normalSamples >= 12 and m.normalSpeed >= 14 and m.normalSpeed <= 18 and human.WalkSpeed == 16,
			"Heavy expiry did not restore ordinary real movement")
		return m
	end
	local driver = {}
	function driver.ready()
		selection.ready()
		waitFor(function() return states.heavy ~= nil and states.heavy.life > 0 and player.PlayerGui:FindFirstChild("HeavyHud") ~= nil end,
			45, "Production HeavyController/HUD did not initialize")
	end
	function driver.run(action: string, data: any?): any
		if action == "inspect" then return inspect()
		elseif action == "layout" then return layout(data)
		elseif action == "class" then return selection.run("class", data)
		elseif action == "ready" then return selection.run("ready")
		elseif action == "exit" then key(Enum.KeyCode.B)
		elseif action == "slowRunDash" then return slowRunDash()
		elseif action == "cast" then
			return withAim(data.point, function(virtual, point)
				local before = #replies.heavy
				activate("heavy", virtual, point)
				waitFor(function() return #replies.heavy > before end, 5, "Real Q produced no heavy reply")
				local reply = replies.heavy[before + 1]
				assert(reply.ok == data.ok and (not data.reason or reply.reason == data.reason), "Real Q result: " .. tostring(reply.reason))
				return reply
			end)
		elseif action == "busy" then
			return withAim(data.point, function(virtual, point)
				local before: { [string]: number } = {}
				local cooldowns: { [string]: number } = {}
				for ability in remotes do before[ability] = #replies[ability]; cooldowns[ability] = states[ability].readyAt end
				activate(data.first, virtual, point)
				for _, ability in data.thenAbilities do task.wait(0.04); activate(ability, virtual, point) end
				waitFor(function()
					if #replies[data.first] <= before[data.first] then return false end
					for _, ability in data.thenAbilities do if #replies[ability] <= before[ability] then return false end end
					return true
				end, 5, "Busy matrix did not receive all ability replies")
				local result: any = { before = cooldowns }
				result[data.first] = replies[data.first][before[data.first] + 1]
				for _, ability in data.thenAbilities do result[ability] = replies[ability][before[ability] + 1] end
				return result
			end)
		elseif action == "probe" then
			probeId += 1
			local before = #replies.heavy
			remotes.heavy:FireServer({ action = "cast", requestId = probeId, life = data.life or life(), direction = data.direction })
			waitFor(function() return #replies.heavy > before end, 4, "Adversarial heavy probe received no reply")
			local reply = replies.heavy[before + 1]
			assert(not reply.ok and reply.reason == data.reason, "Unexpected heavy probe result: " .. tostring(reply.reason))
			return reply
		else error("Unknown heavy fixture command") end
		return inspect()
	end
	function driver.destroy()
		selection.destroy()
		for _, connection in connections do connection:Disconnect() end
	end
	return driver
end
return Driver
