--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Driver = {}
function Driver.new(player: Player, completed: (string, boolean, any) -> ())
	local loadModule = require :: any
	local ClassDriver: any = loadModule(ReplicatedStorage:WaitForChild("ContactClassDriver", 20) :: ModuleScript)
	local selection = ClassDriver.new(player)
	local melee = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent
	local dash = ReplicatedStorage:WaitForChild("DashRemote", 20) :: RemoteEvent
	local replies: { any } = {}
	local dashReplies: { any } = {}
	local contacts: { any } = {}
	local connections: { RBXScriptConnection } = {}
	local running, stopped = false, false
	table.insert(connections, melee.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" then table.insert(replies, { event = event, at = workspace:GetServerTimeNow() }) end
		if event.kind == "contact" then table.insert(contacts, event) end
	end))
	table.insert(connections, dash.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" then table.insert(dashReplies, { event = event, at = workspace:GetServerTimeNow() }) end
	end))
	local function root(): BasePart return (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart end
	local function ground(): (number, number, number)
		local folder = workspace:FindFirstChild("LocalDashEffects")
		if not folder then return 0, 0, 0 end
		local count, shards, dust = 0, 0, 0
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				count += 1
				assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch, "Dash ground art entered physics: " .. item.Name)
				if item.Name == "DashGroundShard" then shards += 1 end
			elseif item:IsA("ParticleEmitter") and item.Name == "DashGroundDust" then dust += 1 end
		end
		if count > 0 then
			local query = OverlapParams.new()
			query.FilterType, query.FilterDescendantsInstances = Enum.RaycastFilterType.Include, { folder }
			assert(#workspace:GetPartBoundsInBox(CFrame.new(root().Position), Vector3.one * 100, query) == 0, "Dash ground art appeared in combat overlap")
		end
		return count, shards, dust
	end
	local function impacts(): number
		local folder = workspace:FindFirstChild("LocalMeleeEffects")
		if not folder then return 0 end
		local count = 0
		for _, burst in folder:GetChildren() do
			if burst.Name ~= "ConfirmedSwordImpact" then continue end
			count += 1
			for _, item in burst:GetDescendants() do
				if item:IsA("BasePart") then
					assert(item.Anchored and item.Massless and not item.CanCollide and not item.CanQuery and not item.CanTouch,
						"Confirmed sword impact entered combat physics")
				end
			end
		end
		if count > 0 then
			local query = OverlapParams.new()
			query.FilterType, query.FilterDescendantsInstances = Enum.RaycastFilterType.Include, { folder }
			assert(#workspace:GetPartBoundsInBox(CFrame.new(root().Position), Vector3.one * 100, query) == 0,
				"Confirmed sword impact appeared in combat overlap")
		end
		return count
	end
	local function runPhase(data: any): any
		local character = player.Character :: Model
		local body = root()
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		local camera = workspace.CurrentCamera :: Camera
		local previousType, previousFrame = camera.CameraType, camera.CFrame
		local virtual = UserInputService:CreateVirtualInput()
		assert(virtual, "VirtualInput unavailable for real contact combat")
		local axis: Vector3 = data.direction
		local beforeReplies, beforeDash, beforeContacts = #replies, #dashReplies, #contacts
		local correctionsBefore = (character:GetAttribute("CombatMovementCorrections") or 0) :: number
		local m: any = { tag = data.tag, owner = player.UserId, samples = 0, negativeSteps = 0, negativeDistance = 0,
			maxExcess = 0, maxFlatStep = 0, minStep = 0, maxYaw = 0, closeSamples = 0, damageTaken = 0,
			bad = {}, groundPeak = 0, shards = 0, dust = 0, accepted = 0, rejected = 0, dashAccepted = 0,
			hits = {}, unexplainedJumps = 0, impactPeak = 0 }
		local function target(): Vector3
			local other = if data.targetOwner then Players:GetPlayerByUserId(data.targetOwner) else nil
			local otherRoot = if other and other.Character then other.Character:FindFirstChild("HumanoidRootPart") else nil
			return if otherRoot and otherRoot:IsA("BasePart") then otherRoot.Position else data.targetPoint or body.Position + axis * 8
		end
		local cameraYaw, lastCameraAt = math.atan2(axis.X, -axis.Z), os.clock()
		local function cameraStep()
			local age = workspace:GetServerTimeNow() - data.at
			local yaw = if data.spin then math.clamp(age / data.duration, 0, 1) * math.pi * 2
				else if data.turn then math.clamp((age - 1.2) / 0.8, 0, 1) * math.pi / 4 else 0
			local forward = CFrame.Angles(0, -yaw, 0):VectorToWorldSpace(axis)
			local point = target()
			local at = os.clock()
			if data.followTarget then
				local delta = (point - body.Position) * Vector3.new(1, 0, 1)
				if delta.Magnitude > 0.2 then
					local desired = math.atan2(delta.X, -delta.Z)
					local difference = math.atan2(math.sin(desired - cameraYaw), math.cos(desired - cameraYaw))
					cameraYaw += difference * (1 - math.exp(-10 * math.max(0, at - lastCameraAt)))
				end
				forward = Vector3.new(math.sin(cameraYaw), 0, -math.cos(cameraYaw))
			end
			lastCameraAt = at
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(body.Position - forward * 18 + Vector3.new(0, 9, 0),
				if data.followTarget then point else body.Position + forward * 25)
		end
		local aim = RunService.RenderStepped:Connect(cameraStep)
		cameraStep()
		local sampled: RBXScriptConnection? = nil
		local oldHealth = humanoid.Health
		local changed = humanoid.HealthChanged:Connect(function(value)
			if value < oldHealth then m.damageTaken += oldHealth - value; table.insert(m.hits, { at = workspace:GetServerTimeNow(), damage = oldHealth - value }) end
			oldHealth = value
		end)
		local ok, problem = xpcall(function()
			local center = camera.ViewportSize / 2
			virtual:SendMousePosition(center)
			virtual:SendMouseButton(center, Enum.UserInputType.MouseButton2, true)
			virtual:SendMouseButton(center, Enum.UserInputType.MouseButton2, false)
			while workspace:GetServerTimeNow() < data.at do task.wait(0.01) end
			local start, previous = body.Position, body.Position
			local previousAt = workspace:GetServerTimeNow()
			local previousLook = body.CFrame.LookVector
			if data.move then virtual:SendKey(true, Enum.KeyCode.W, false) end
			sampled = RunService.Heartbeat:Connect(function()
				local at, point = workspace:GetServerTimeNow(), body.Position
				local age, dt = at - data.at, at - previousAt
				local delta = (point - previous) * Vector3.new(1, 0, 1)
				local intended = humanoid.MoveDirection * Vector3.new(1, 0, 1)
				if intended.Magnitude < 0.1 then intended = axis else intended = intended.Unit end
				local progress, flat = delta:Dot(intended), delta.Magnitude
				local mover = body:FindFirstChild("WarriorDashVelocity")
				local speed = if mover then 16 / 0.28 else 16
				local excess = flat - speed * dt
				local look = body.CFrame.LookVector
				local yaw = math.acos(math.clamp(previousLook:Dot(look), -1, 1))
				if age >= 0.2 and age <= data.duration - 0.2 and dt > 0 then
					m.samples += 1
					-- A dead ragdoll is native physics, not live character control.
					-- Authority corrections and resource cleanup are still checked below.
					if humanoid.Health > 0 then
						m.minStep, m.maxFlatStep = math.min(m.minStep, progress), math.max(m.maxFlatStep, flat)
						m.maxExcess, m.maxYaw = math.max(m.maxExcess, excess), math.max(m.maxYaw, yaw)
						if progress < -0.1 then m.negativeSteps += 1 end
						if progress < 0 then m.negativeDistance += -progress end
						local gap = (target() - point).Magnitude
						if gap < 6 then m.closeSamples += 1 end
						if excess > 0.75 and gap >= 4 then m.unexplainedJumps += 1 end
						if (progress < -0.1 or excess > 0.75) and #m.bad < 8 then
							table.insert(m.bad, { time = age, dt = dt, progress = progress, excess = excess,
								position = { point.X, point.Y, point.Z }, velocity = body.AssemblyLinearVelocity.Magnitude,
								gap = (target() - point).Magnitude, mover = mover ~= nil })
						end
					end
				end
				local artOk, count, shards, dust = pcall(ground)
				if artOk then
					m.groundPeak, m.shards, m.dust = math.max(m.groundPeak, count), math.max(m.shards, shards), math.max(m.dust, dust)
				else m.sampleError = tostring(count) end
				local impactOk, impactCount = pcall(impacts)
				if impactOk then m.impactPeak = math.max(m.impactPeak, impactCount) else m.sampleError = tostring(impactCount) end
				previous, previousAt, previousLook = point, at, look
			end)
			local shot, didDash, stoppedMoving = 1, false, false
			local walking = data.move == true
			local gapReady = data.gapAfterDash ~= true
			local attacks = data.attacks or {}
			while workspace:GetServerTimeNow() - data.at < data.duration do
				local age = workspace:GetServerTimeNow() - data.at
				if not gapReady and didDash and #dashReplies > beforeDash then
					local response = dashReplies[beforeDash + 1].event
					local mover = body:FindFirstChild("WarriorDashVelocity")
					local physicalDone = not mover or (mover:IsA("LinearVelocity") and not mover.Enabled)
					for _, active in response.state.active do
						if response.ok and active.owner == player.UserId and physicalDone
							and workspace:GetServerTimeNow() >= active.expiresAt + 0.2 then
							gapReady = true
							print("ContactPursuit", data.tag, player.UserId, "dashFinishedBeforeGapControl",
								"age", age, "expiresAt", active.expiresAt, "physicalDone", physicalDone)
						end
					end
				end
				if gapReady and data.keepGap and data.move and not stoppedMoving and age >= (data.keepGapAfter or 0) then
					if m.gapControlAt == nil then
						m.gapControlAt = age
						print("ContactPursuit", data.tag, player.UserId, "gapControlEnabled", "age", age,
							"continuousWBefore", walking, "minimumAge", data.keepGapAfter or 0)
					end
					local gap = ((target() - body.Position) * Vector3.new(1, 0, 1)).Magnitude
					if walking and gap <= 7 then
						virtual:SendKey(false, Enum.KeyCode.W, false); walking = false
						print("ContactPursuit", data.tag, player.UserId, "stopW", "age", age, "visibleFlatGap", gap)
					elseif not walking and gap >= 8 then
						virtual:SendKey(true, Enum.KeyCode.W, false); walking = true
						print("ContactPursuit", data.tag, player.UserId, "resumeW", "age", age, "visibleFlatGap", gap)
					end
				end
				if data.stopMovingAt and age >= data.stopMovingAt and not stoppedMoving then
					virtual:SendKey(false, Enum.KeyCode.W, false); stoppedMoving = true
				end
				if data.dashAt and age >= data.dashAt and not didDash then
					virtual:SendKey(true, Enum.KeyCode.E, false); virtual:SendKey(false, Enum.KeyCode.E, false); didDash = true
				elseif shot <= #attacks and age >= attacks[shot] then
					cameraStep()
					local pointToHit = target()
					local projected, visible = camera:WorldToViewportPoint(pointToHit)
					if not visible then
						camera.CFrame = CFrame.lookAt(camera.CFrame.Position, pointToHit)
						projected, visible = camera:WorldToViewportPoint(pointToHit)
					end
					assert(visible, "Close opponent/target left contact camera")
					local point = Vector2.new(projected.X, projected.Y)
					for _, object in player.PlayerGui:GetGuiObjectsAtPosition((point - GuiService:GetGuiInset()).X, (point - GuiService:GetGuiInset()).Y) do
						assert(not object:IsA("GuiButton"), "Real contact LMB overlaps GUI")
					end
					virtual:SendMousePosition(point)
					local ray = camera:ViewportPointToRay(point.X, point.Y)
					local parameters = RaycastParams.new()
					parameters.FilterType, parameters.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
					local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, parameters)
					local actual = if hit then hit.Position else ray.Origin + ray.Direction * 500
					local intended = (pointToHit - body.Position) * Vector3.new(1, 0, 1)
					local aimDirection = (actual - body.Position) * Vector3.new(1, 0, 1)
					local dot = if intended.Magnitude > 0.1 and aimDirection.Magnitude > 0.1 then intended.Unit:Dot(aimDirection.Unit) else 0
					print("ContactAim", data.tag, player.UserId, "shot", shot, "gap", intended.Magnitude,
						"dy", pointToHit.Y - body.Position.Y, "rayDot", dot,
						"hit", if hit then hit.Instance:GetFullName() else "none")
					virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
					task.wait(0.05)
					virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
					shot += 1
				else task.wait(0.01) end
			end
			m.distance = ((body.Position - start) * Vector3.new(1, 0, 1)).Magnitude
			if sampled then sampled:Disconnect(); sampled = nil end
			virtual:SendKey(false, Enum.KeyCode.W, false)
			task.wait(1.2)
			for index = beforeReplies + 1, #replies do
				local delivery = replies[index]
				if delivery.event.ok then m.accepted += 1 else m.rejected += 1 end
				print("ContactReply", data.tag, player.UserId, delivery.at, delivery.event.ok, delivery.event.reason)
			end
			for index = beforeDash + 1, #dashReplies do
				if dashReplies[index].event.ok then m.dashAccepted += 1 end
				print("ContactDashReply", data.tag, player.UserId, dashReplies[index].at, dashReplies[index].event.ok, dashReplies[index].event.reason)
			end
			m.groundRemaining = ground()
			m.impactRemaining, m.contacts = impacts(), #contacts - beforeContacts
			for index = beforeContacts + 1, #contacts do
				local contact = contacts[index]
				print("ContactHit", data.tag, "observer", player.UserId, "owner", contact.owner,
					"swing", contact.swingId, "id", contact.contactId, "hitAt", contact.hitAt)
			end
			m.corrections = ((character:GetAttribute("CombatMovementCorrections") or 0) :: number) - correctionsBefore
			print("ContactMotion", data.tag, player.UserId, "samples", m.samples, "negative", m.negativeSteps,
				"backward", m.negativeDistance, "minStep", m.minStep, "maxExcess", m.maxExcess, "maxFlat", m.maxFlatStep,
				"distance", m.distance, "close", m.closeSamples, "yaw", m.maxYaw, "damage", m.damageTaken, "accepted", m.accepted,
				"corrections", m.corrections, "unexplained", m.unexplainedJumps)
			print("ContactGround", data.tag, player.UserId, m.groundPeak, m.shards, m.dust, m.groundRemaining)
			print("ContactImpact", data.tag, player.UserId, "contacts", m.contacts, "peak", m.impactPeak, "remaining", m.impactRemaining)
			for _, bad in m.bad do print("ContactBadFrame", data.tag, player.UserId, game:GetService("HttpService"):JSONEncode(bad)) end
			assert(not m.sampleError, m.sampleError)
		end, debug.traceback)
		virtual:SendKey(false, Enum.KeyCode.W, false)
		if sampled then sampled:Disconnect() end
		changed:Disconnect(); aim:Disconnect()
		camera.CameraType, camera.CFrame = previousType, previousFrame
		assert(ok, tostring(problem))
		return m
	end
	local driver = {}
	function driver.ready() selection.ready() end
	function driver.run(action: string, data: any?): any
		if action == "class" then return selection.run("class", "warrior")
		elseif action == "ready" then return selection.run("ready")
		elseif action == "inspect" then
			local count, shards, dust = ground()
			return { position = root().Position, ground = count, shards = shards, dust = dust,
				constraint = root():FindFirstChild("WarriorDashVelocity") ~= nil,
				meleeChildren = #(workspace:FindFirstChild("LocalMeleeEffects") :: Folder):GetChildren() }
		elseif action == "start" then
			assert(not running and not stopped, "Contact probe overlaps a previous phase")
			running = true
			task.spawn(function()
				local ok, result = xpcall(function() return runPhase(data) end, debug.traceback)
				running = false; completed(data.tag, ok, result)
			end)
			return { armed = true }
		end
		error("Unknown contact fixture action")
	end
	function driver.destroy()
		stopped = true
		selection.destroy()
		for _, connection in connections do connection:Disconnect() end
	end
	return driver
end
return Driver
