--!strict
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Probe = {}
export type Ports = { root: () -> BasePart?, inspect: () -> any, click: (Vector2) -> (),
	replyCount: () -> number, reply: () -> any, history: { any } }
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.025) until os.clock() >= deadline
	error(message)
end
function Probe.run(player: Player, ports: Ports): any
	local character = player.Character :: Model
	local body = ports.root() :: BasePart
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	assert(humanoid.Health > 0 and humanoid.WalkSpeed == 16 and character:GetAttribute("CombatClass") == "warrior")
	local virtual = UserInputService:CreateVirtualInput()
	assert(virtual, "Virtual keyboard unavailable for moving attack")
	local camera = workspace.CurrentCamera :: Camera
	local previousCameraType, previousCameraFrame = camera.CameraType, camera.CFrame
	local originalAutoRotate = humanoid.AutoRotate
	local aim: RBXScriptConnection? = nil
	local start = body.Position
	local frame = CFrame.lookAt(start + Vector3.new(0, 8, 16), start + Vector3.new(0, 1, -40))
	local forward = Vector3.new(0, 0, -1)
	local metrics: any = { autoRotateBefore = originalAutoRotate, shots = {}, badFrames = {}, negativeSteps = 0, negativeDistance = 0,
		minForwardStep = 0, maxForwardStep = 0, maxFlatStep = 0, maxExcessStep = 0,
		minVelocity = 0, maxVelocity = 0, maxSampleDt = 0, samples = 0,
		maxYawStep = 0, maxYawSpeed = 0, maxYawExcess = 0, vfxPartSamples = 0, vfxPhysicsViolations = 0 }
	local movement: RBXScriptConnection? = nil
	local poseSample: RBXScriptConnection? = nil
	local geometrySample: RBXScriptConnection? = nil
	local function coordinates(value: Vector3): { number } return { value.X, value.Y, value.Z } end
	local function trailResources(): (number, number)
		local trails, nodes = 0, 0
		for _, item in character:GetDescendants() do
			if item:IsA("Trail") and item.Name == "MovingSwordEdge" then trails += 1 end
			if item:IsA("Attachment") and (item.Name == "SwordTrailHeel" or item.Name == "SwordTrailTip") then nodes += 1 end
		end
		return trails, nodes
	end
	local function aimPoint(): Vector2
		-- Aim 45 degrees across the running direction at real ground. The camera
		-- stays aligned with the lane, so W never changes its movement direction.
		local point = body.Position + Vector3.new(18, 0.1 - body.Position.Y, -18)
		local projected, visible = camera:WorldToViewportPoint(point)
		assert(visible, "Sideways motion-test aim left the camera viewport")
		local screen = Vector2.new(projected.X, projected.Y)
		local guiPoint = screen - GuiService:GetGuiInset()
		for _, object in player.PlayerGui:GetGuiObjectsAtPosition(guiPoint.X, guiPoint.Y) do
			assert(not object:IsA("GuiButton"), "Motion-test aim overlapped a GUI button")
		end
		return screen
	end
	local ok, problem = xpcall(function()
		if aim then aim:Disconnect() end
		camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame
		aim = RunService.RenderStepped:Connect(function() camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, frame end)
		task.wait(0.2)
		-- Isolate the real swing's overlay from walking animation: observe an idle
		-- right shoulder, strike once, then verify recovery without editing the rig.
		local shoulder: any = nil
		for _, item in character:GetDescendants() do
			if not item:IsA("Motor6D") and not item:IsA("AnimationConstraint") then continue end
			local attachment = if item:IsA("AnimationConstraint") then item.Attachment0 else nil
			if item.Name == "RightShoulder" or item.Name == "Right Shoulder"
				or (attachment and attachment.Name == "RightShoulderRigAttachment") then shoulder = item; break end
		end
		assert(shoulder, "Live warrior rig has no right shoulder animation joint")
		local rest: CFrame = shoulder.Transform
		local c0 = if shoulder:IsA("Motor6D") then shoulder.C0 else nil
		local maxAngle = 0
        local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart
        local handRest = body.CFrame:ToObjectSpace(hand.CFrame)
        local maxHandDistance, maxHandAngle = 0, 0
        print("WarriorJointInfo", shoulder.ClassName, shoulder.Name,
            if shoulder:IsA("AnimationConstraint") then shoulder.IsKinematic else true,
            if shoulder:IsA("AnimationConstraint") and shoulder.Attachment0 then shoulder.Attachment0.Parent:GetFullName() else "motor",
            if shoulder:IsA("AnimationConstraint") and shoulder.Attachment1 then shoulder.Attachment1.Parent:GetFullName() else "motor")
		local armour = character:FindFirstChild("WarriorArmour") :: Folder
		local tip = armour:FindFirstChild("WarriorSwordTip") :: BasePart
		local grip = armour:FindFirstChild("WarriorSwordGrip") :: BasePart
		assert(tip and grip, "Production sword tip/grip geometry absent")
		local geometry: { any } = {}
        local gripWeld = grip:FindFirstChild("WarriorVisualWeld") :: Weld
        assert(gripWeld and gripWeld.Part0 == hand, "Sword grip is not attached to the current hand")
        local maximumGripError = 0
		geometrySample = RunService.RenderStepped:Connect(function()
			local now = workspace:GetServerTimeNow()
			local enabled = false
			for _, item in armour:GetDescendants() do
				if item:IsA("Trail") and item.Name == "MovingSwordEdge" and item.Enabled then enabled = true end
			end
			local blade = tip.Position - grip.Position
            maximumGripError = math.max(maximumGripError, (grip.Position - (hand.CFrame * gripWeld.C0).Position).Magnitude)
			table.insert(geometry, { at = now, tip = tip.Position, grip = grip.Position, root = body.Position,
				tipRoot = coordinates(body.CFrame:PointToObjectSpace(tip.Position)),
				gripRoot = coordinates(body.CFrame:PointToObjectSpace(grip.Position)),
				axis = if blade.Magnitude > 0 then blade.Unit else Vector3.zero, trailEnabled = enabled, handRoot = coordinates(body.CFrame:PointToObjectSpace(hand.Position)) })
		end)
		poseSample = RunService.Heartbeat:Connect(function()
			local _, angle = rest:ToObjectSpace(shoulder.Transform):ToAxisAngle()
			maxAngle = math.max(maxAngle, math.abs(angle))
            local handLocal = body.CFrame:ToObjectSpace(hand.CFrame)
            maxHandDistance = math.max(maxHandDistance, (handLocal.Position - handRest.Position).Magnitude)
            local _, handAngle = handRest.Rotation:ToObjectSpace(handLocal.Rotation):ToAxisAngle()
            maxHandAngle = math.max(maxHandAngle, math.abs(handAngle))
		end)
		local idleStarted, idleBefore = os.clock(), ports.replyCount()
		ports.click(aimPoint())
		waitFor(function() return ports.replyCount() > idleBefore end, 4, "Idle pose LMB received no reply")
		local idleReply = ports.reply()
		assert(idleReply.ok, "Idle pose LMB rejected: " .. tostring(idleReply.reason))
		local idleSwing: any = nil
		for _, event in idleReply.state.active do if event.owner == player.UserId then idleSwing = event; break end end
		assert(idleSwing and type(idleSwing.hitAt) == "number", "Idle pose reply omitted authoritative hit time")
		while os.clock() - idleStarted < 1.35 do task.wait(0.025) end
		if poseSample then poseSample:Disconnect(); poseSample = nil end
		if geometrySample then geometrySample:Disconnect(); geometrySample = nil end
		local _, returned = rest:ToObjectSpace(shoulder.Transform):ToAxisAngle()
		print("WarriorHandMotion", maxHandDistance, maxHandAngle, "gripError", maximumGripError)
		metrics.pose = { gripError = maximumGripError, handDistance = maxHandDistance, handAngle = maxHandAngle, joint = shoulder.ClassName, maxAngle = maxAngle, returnedAngle = math.abs(returned),
			restUnchanged = c0 == nil or shoulder.C0 == c0 }
		local direction = (idleSwing.direction * Vector3.new(1, 0, 1)).Unit
		local contact, minTipY, minTipRootY, maxTipY = {}, tip.Position.Y, tip.Position.Y - body.Position.Y, tip.Position.Y
		metrics.trail = { insideEnabled = 0, outsideEnabled = 0, enabledSamples = 0, timingTolerance = 0.03 }
		for _, sample in geometry do
			local age = sample.at - idleSwing.hitAt
			minTipY, minTipRootY = math.min(minTipY, sample.tip.Y), math.min(minTipRootY, sample.tip.Y - sample.root.Y)
			maxTipY = math.max(maxTipY, sample.tip.Y)
			if math.abs(age) <= 0.05 then
				table.insert(contact, { age = age, tipY = sample.tip.Y, tipRoot = sample.tipRoot, gripRoot = sample.gripRoot,
					bladeAimDot = sample.axis:Dot(direction), tipForward = (sample.tip - sample.root):Dot(direction),
					gripForward = (sample.grip - sample.root):Dot(direction), handRoot = sample.handRoot })
			end
			if sample.trailEnabled then
				metrics.trail.enabledSamples += 1
				metrics.trail.minEnabledAge = math.min(metrics.trail.minEnabledAge or age, age)
				metrics.trail.maxEnabledAge = math.max(metrics.trail.maxEnabledAge or age, age)
				if age >= -0.08 and age <= 0.10 then metrics.trail.insideEnabled += 1 end
				-- Rendering can observe one preceding update at a window boundary.
				if age < -0.11 or age > 0.13 then metrics.trail.outsideEnabled += 1 end
			end
		end
		metrics.swordGeometry = { hitAt = idleSwing.hitAt, aim = coordinates(direction), contactWindow = 0.05,
			contact = contact, minimumTipY = minTipY, minimumTipRootY = minTipRootY, maximumTipY = maxTipY }
        for index, sample in contact do print("WarriorSwordContact", index, game:GetService("HttpService"):JSONEncode(sample)) end
        print("WarriorSwordPath", minTipY, minTipRootY, maxTipY)
		metrics.trail.afterDryTrails, metrics.trail.afterDryNodes = trailResources()
		metrics.autoRotateAfterDry = humanoid.AutoRotate

		local runningAt = os.clock()
		local previous, previousAt = body.Position, runningAt
		local previousLook = (body.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		local baselineDistance, baselineTime, attackDistance, attackTime = 0, 0, 0, 0
		local runningStart = body.Position
		local beforeReplies = #ports.history
		local effects = workspace:FindFirstChild("LocalMeleeEffects") :: Folder
		assert(effects, "Production melee effect owner absent")
		movement = RunService.Heartbeat:Connect(function()
			local at, position = os.clock(), body.Position
			local dt, elapsed = at - previousAt, at - runningAt
			local delta = position - previous
			local look = (body.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
			local yawStep = math.acos(math.clamp(previousLook:Dot(look), -1, 1))
			local progress = delta:Dot(forward)
			local flat = (delta * Vector3.new(1, 0, 1)).Magnitude
			if elapsed >= 0.2 and dt > 0 then
				local velocity = body.AssemblyLinearVelocity:Dot(forward)
				if metrics.samples == 0 then
					metrics.minForwardStep, metrics.maxForwardStep = progress, progress
					metrics.minVelocity, metrics.maxVelocity = velocity, velocity
				end
				metrics.samples += 1
				metrics.minForwardStep = math.min(metrics.minForwardStep, progress)
				metrics.maxForwardStep = math.max(metrics.maxForwardStep, progress)
				metrics.maxFlatStep = math.max(metrics.maxFlatStep, flat)
				metrics.maxExcessStep = math.max(metrics.maxExcessStep, flat - 16 * dt)
				metrics.minVelocity, metrics.maxVelocity = math.min(metrics.minVelocity, velocity), math.max(metrics.maxVelocity, velocity)
				metrics.maxSampleDt = math.max(metrics.maxSampleDt, dt)
				metrics.maxYawStep = math.max(metrics.maxYawStep, yawStep)
				metrics.maxYawSpeed = math.max(metrics.maxYawSpeed, yawStep / dt)
				metrics.maxYawExcess = math.max(metrics.maxYawExcess, yawStep - 9 * dt)
				if progress < 0 then metrics.negativeDistance += -progress end
				if progress < -0.1 then metrics.negativeSteps += 1 end
				if (progress < -0.1 or flat - 16 * dt > 0.75 or yawStep - 9 * dt > 0.25) and #metrics.badFrames < 8 then
					table.insert(metrics.badFrames, { t = elapsed, dt = dt, progress = progress, flat = flat,
						velocity = velocity, yawStep = yawStep, yawSpeed = yawStep / dt })
				end
				if elapsed <= 0.55 then baselineDistance += progress; baselineTime += dt end
				if elapsed >= 0.6 then attackDistance += progress; attackTime += dt end
			end
			for _, item in effects:GetDescendants() do
				if item:IsA("BasePart") then
					metrics.vfxPartSamples += 1
					if item.CanQuery or item.CanCollide or item.CanTouch then metrics.vfxPhysicsViolations += 1 end
				end
			end
			previous, previousAt, previousLook = position, at, look
		end)
		virtual:SendKey(true, Enum.KeyCode.W, false)
		local deadlines, shot = { 0.6, 1.65, 2.7 }, 1
		while os.clock() - runningAt < 3.8 do
			if shot <= #deadlines and os.clock() - runningAt >= deadlines[shot] then
				table.insert(metrics.shots, os.clock() - runningAt)
				ports.click(aimPoint())
				shot += 1
			else task.wait(0.01) end
		end
		local finishedAt = os.clock()
		if movement then movement:Disconnect(); movement = nil end
		virtual:SendKey(false, Enum.KeyCode.W, false)
		metrics.duration = finishedAt - runningAt
		metrics.distance = (body.Position - runningStart):Dot(forward)
		metrics.lateralDistance = math.abs(body.Position.X - runningStart.X)
		metrics.averageSpeed = metrics.distance / metrics.duration
		metrics.baselineSpeed, metrics.attackSpeed = baselineDistance / baselineTime, attackDistance / attackTime
		task.wait(0.9)
		metrics.accepted = 0
		for index = beforeReplies + 1, #ports.history do
			local event = ports.history[index].event
			if event.ok then metrics.accepted += 1 else
				table.insert(metrics.badFrames, { rejection = tostring(event.reason), requestId = event.requestId })
			end
		end
		for _, item in effects:GetDescendants() do
			if item:IsA("BasePart") then assert(not item.CanQuery and not item.CanCollide and not item.CanTouch, "Swing VFX entered physics") end
		end
		metrics.effectChildren = #effects:GetChildren()
		metrics.armourParts = ports.inspect().armourParts
		metrics.trail.afterMotionTrails, metrics.trail.afterMotionNodes = trailResources()
		metrics.autoRotateAfter = humanoid.AutoRotate
		print("WarriorSwordTrail", game:GetService("HttpService"):JSONEncode(metrics.trail))
        local compact = table.clone(metrics); compact.swordGeometry = nil; compact.trail = nil
		print("WarriorMotion", game:GetService("HttpService"):JSONEncode(compact))
		assert(metrics.autoRotateAfterDry == originalAutoRotate and metrics.autoRotateAfter == originalAutoRotate, "Swing facing did not restore Humanoid.AutoRotate")
		assert(#contact > 0, "No actual sword geometry samples were captured near contact")
        local aligned = false
        for _, sample in contact do
            if sample.bladeAimDot > 0.5 and sample.tipForward > 1 then aligned = true end
        end
        assert(aligned and minTipY > 0, "Sword blade did not pass in front of the actor above the ground at contact")
		assert(metrics.trail.insideEnabled > 0 and metrics.trail.outsideEnabled == 0, "Sword trail did not follow the stroke window")
		assert(metrics.trail.afterDryTrails == 0 and metrics.trail.afterDryNodes == 0
			and metrics.trail.afterMotionTrails == 0 and metrics.trail.afterMotionNodes == 0, "Sword-owned trail resources leaked")
		assert(maxHandDistance >= 0.5 and maximumGripError <= 0.2, "Sword did not follow actual hand motion without frame lag")
		assert(metrics.pose.maxAngle >= math.rad(17), "Real swing did not move the live shoulder beyond idle motion")
		assert(metrics.pose.returnedAngle <= math.rad(12), "Swing shoulder failed to return to its idle range")
		assert(metrics.pose.restUnchanged, "Swing changed the rig's rest joint C0")
		assert(metrics.accepted == 3, "Moving LMB did not produce three accepted swings")
		assert(metrics.samples >= 30 and baselineTime >= 0.2, "Insufficient actual root-motion samples")
		assert(metrics.baselineSpeed >= 14, "Baseline W movement did not reach normal running speed")
		assert(metrics.negativeSteps == 0 and metrics.negativeDistance <= 0.25, "Running swings caused backward root corrections")
		assert(metrics.maxExcessStep <= 0.75, "Running swing caused an unexplained root jump")
		assert(metrics.maxYawExcess <= 0.25, "Running swing caused an abrupt root-yaw correction")
		assert(metrics.attackSpeed >= 14 and metrics.attackSpeed >= metrics.baselineSpeed * 0.9, "Swinging materially reduced running speed")
		assert(metrics.distance >= 52 and metrics.lateralDistance <= 1, "Running swings lost lane distance or changed movement direction")
		assert(metrics.vfxPartSamples > 0 and metrics.vfxPhysicsViolations == 0, "Live swing VFX were missing or entered physics")
		assert(metrics.effectChildren == 0 and metrics.armourParts > 10, "Moving swing cleanup/appearance failed")
	end, debug.traceback)
	virtual:SendKey(false, Enum.KeyCode.W, false)
	if movement then movement:Disconnect() end
	if poseSample then poseSample:Disconnect() end
	if geometrySample then geometrySample:Disconnect() end
	if aim then aim:Disconnect(); aim = nil end
	camera.CameraType, camera.CFrame = previousCameraType, previousCameraFrame
	assert(ok, tostring(problem) .. "\n" .. game:GetService("HttpService"):JSONEncode(metrics))
	return metrics
end

return Probe
