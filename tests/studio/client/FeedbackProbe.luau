--!strict
-- Read-only observer. Joint/speed onsets are threshold candidates, never artistic PASS criteria.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Probe = {}
local remotes: { [string]: string } = { ArrowRemote = "arrow", HandsRemote = "hands", MeleeRemote = "melee", HeavyRemote = "heavy", DashRemote = "dash" }
local function xyz(v: Vector3): { number } return { v.X, v.Y, v.Z } end
local function plain(value: any, depth: number?): any
	local level = depth or 0
	if level > 4 then return "<depth>" end
	if typeof(value) == "Vector3" then return xyz(value) end
	if typeof(value) == "CFrame" then return { value:GetComponents() } end
	if type(value) == "table" then
		local result = {}; local count = 0
		for key, item in value do
			count += 1; if count > 80 then break end
			if type(key) == "string" or type(key) == "number" then result[key] = plain(item, level + 1) end
		end
		return result
	end
	if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then return value end
	return nil
end
function Probe.new(player: Player, options: any?): any
	local config = options or {}
	local capacity = math.clamp(config.capacity or 1800, 120, 6000)
	local events: { any }, samples: { any }, windows: { any } = {}, {}, {}
	local serial, sampleSerial, inputSerial, renderFrames, simulationFrames = 0, 0, 0, 0, 0
	local connections: { RBXScriptConnection } = {}
	local bodyConnections: { RBXScriptConnection } = {}
	local watched: { [Instance]: boolean } = {}
	local character: Model? = nil
	local root: BasePart? = nil
	local humanoid: Humanoid? = nil
	local joints: { any } = {}
	local previousJoints: { [Instance]: CFrame } = {}
	local lastPoint: Vector3? = nil
	local lastVelocity = Vector3.zero
	local lastAt = os.clock()
	local idleJointStep = 0
	local stopped = false
	local function snapshot(): any
		return { life = if character then character:GetAttribute("CombatLife") else nil,
			classId = if character then character:GetAttribute("CombatClass") else nil,
			position = if root then xyz(root.Position) else nil,
			velocity = if root then xyz(root.AssemblyLinearVelocity) else nil,
			speed = if humanoid then humanoid.WalkSpeed else nil,
			health = if humanoid then humanoid.Health else nil,
			corrections = if character then character:GetAttribute("CombatMovementCorrections") else nil,
			renderFrames = renderFrames, simulationFrames = simulationFrames }
	end
	local function mark(label: string, data: any?): any
		serial += 1
		local event = { sequence = serial, label = label, at = workspace:GetServerTimeNow(), localAt = os.clock(), data = plain(data), snapshot = snapshot() }
		events[(serial - 1) % capacity + 1] = event
		return event
	end
	local function transform(joint: any): CFrame? local ok, value = pcall(function() return joint.Transform end); return if ok then value else nil end
	local function watchMover(child: Instance)
		if watched[child] or not child:IsA("LinearVelocity") or child.Name ~= "WarriorDashVelocity" then return end
		watched[child] = true
		local function state(): any
			return { enabled = child.Enabled, direction = child:GetAttribute("DashDirection"), origin = child:GetAttribute("DashOrigin"),
				distance = child:GetAttribute("DashDistance"), limit = child:GetAttribute("DashLimit"), speed = child:GetAttribute("DashSpeed") }
		end
		mark("mover_added", state())
		table.insert(bodyConnections, child:GetPropertyChangedSignal("Enabled"):Connect(function() mark("mover_enabled", state()) end))
	end
	local function bind(value: Model)
		for _, connection in bodyConnections do connection:Disconnect() end
		table.clear(bodyConnections); table.clear(watched); table.clear(previousJoints); table.clear(joints)
		character, root, humanoid = value, nil, nil
		lastPoint, lastVelocity, lastAt, idleJointStep = nil, Vector3.zero, os.clock(), 0
		local function discover()
			local nextRoot = value:FindFirstChild("HumanoidRootPart")
			humanoid = value:FindFirstChildOfClass("Humanoid")
			if not nextRoot or not nextRoot:IsA("BasePart") or nextRoot == root then return end
			root = nextRoot
			table.insert(bodyConnections, nextRoot.ChildAdded:Connect(watchMover))
			table.insert(bodyConnections, nextRoot.ChildRemoved:Connect(function(child)
				if watched[child] then watched[child] = nil; mark("mover_removed", { name = child.Name }) end
			end))
			for _, child in nextRoot:GetChildren() do watchMover(child) end
		end
		local function jointAdded(item: Instance)
			if not item:IsA("Motor6D") and not item:IsA("AnimationConstraint") then return end
			if #joints < 32 then table.insert(joints, item) end
		end
		for _, item in value:GetDescendants() do jointAdded(item) end
		table.insert(bodyConnections, value.DescendantAdded:Connect(jointAdded))
		table.insert(bodyConnections, value.ChildAdded:Connect(discover))
		for _, attribute in { "CombatLife", "CombatClass", "CombatMovementCorrections" } do
			table.insert(bodyConnections, value:GetAttributeChangedSignal(attribute):Connect(function() mark("attribute", { name = attribute, value = value:GetAttribute(attribute) }) end))
		end
		discover(); mark("character_bound")
	end
	table.insert(connections, player.CharacterAdded:Connect(bind))
	table.insert(connections, player.CharacterRemoving:Connect(function(value)
		if character == value then mark("character_removing"); root, humanoid = nil, nil end
	end))
	if player.Character then bind(player.Character) end
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		local code = if input.UserInputType == Enum.UserInputType.MouseButton1 then "LMB" else input.KeyCode.Name
		if code ~= "LMB" and code ~= "Q" and code ~= "E" and code ~= "W" then return end
		inputSerial += 1
		local focused: any = UserInputService:GetFocusedTextBox()
		local event = mark("input", { inputId = inputSerial, code = code, processed = processed, focused = focused ~= nil })
		local baseline = {}; for _, joint in joints do if joint.Parent then baseline[joint] = transform(joint) end end
		local flat = if root then root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) else Vector3.zero
		table.insert(windows, { inputId = inputSerial, code = code, processed = processed, focused = focused ~= nil, at = event.at, localAt = event.localAt,
			life = event.snapshot.life, baselineSpeed = flat.Magnitude, baselineJointStep = idleJointStep,
			jointThreshold = math.max(0.035, idleJointStep * 3), baseline = baseline })
		if #windows > 80 then table.remove(windows, 1) end
	end))
	for name, ability in remotes do
		local remote = ReplicatedStorage:FindFirstChild(name)
		if not remote or not remote:IsA("RemoteEvent") then mark("remote_absent", { name = name }); continue end
		table.insert(connections, remote.OnClientEvent:Connect(function(event: any)
			if type(event) ~= "table" then return end
			mark("remote_" .. tostring(event.kind), { ability = ability, owner = event.owner, life = event.life, requestId = event.requestId,
				dashId = event.dashId, swingId = event.swingId, castId = event.castId, contactId = event.contactId, ok = event.ok, reason = event.reason,
				startedAt = event.startedAt, hitAt = event.hitAt, launchAt = event.launchAt, contactAt = event.contactAt,
				targetLife = event.targetLife, damageApplied = event.damageApplied, style = event.style,
				expiresAt = event.expiresAt, position = event.position,
				active = if type(event.state) == "table" then event.state.active else nil })
		end))
	end
	table.insert(connections, RunService.PreSimulation:Connect(function() simulationFrames += 1 end))
	local function observeJoints(field: string, label: string, rendered: boolean)
		local step = 0
		for _, joint in joints do
			if not joint.Parent then continue end
			local current = transform(joint)
			if current then
				local previous = previousJoints[joint]
				if previous then local _, angle = previous:ToObjectSpace(current):ToAxisAngle(); step = math.max(step, math.abs(angle)) end
				if rendered then previousJoints[joint] = current end
				for _, window in windows do
					if os.clock() - window.localAt > 1.6 or not window.baseline[joint] then continue end
					if not character or window.life ~= character:GetAttribute("CombatLife") then continue end
					local delta = window.baseline[joint]:ToObjectSpace(current)
					local _, angle = delta:ToAxisAngle()
					window.maxRelativeToBaseline = math.max(window.maxRelativeToBaseline or 0, math.abs(angle))
					window.maxTranslationToBaseline = math.max(window.maxTranslationToBaseline or 0, delta.Position.Magnitude)
					if not window[field] and (math.abs(angle) > window.jointThreshold or delta.Position.Magnitude > 0.025) then
						window[field] = mark(label, { inputId = window.inputId, joint = joint.Name,
							angle = math.abs(angle), translation = delta.Position.Magnitude, elapsed = os.clock() - window.localAt }).at
					end
				end
			end
		end
		-- Retain the observed natural frame-to-frame motion floor; not an attribution to an attack.
		if rendered then idleJointStep = math.max(step, idleJointStep * 0.96) end
	end
	table.insert(connections, RunService.RenderStepped:Connect(function()
		renderFrames += 1; observeJoints("firstJointChange", "joint_change_candidate", true)
	end))
	table.insert(connections, RunService.PostSimulation:Connect(function()
		observeJoints("firstJointChangeSimulation", "joint_simulation_candidate", false)
	end))
	table.insert(connections, RunService.Heartbeat:Connect(function()
		if not root or not humanoid or not root.Parent then return end
		local at, point = os.clock(), root.Position
		local flat = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		local dt = at - lastAt
		local acceleration = if dt > 0 then (flat - lastVelocity).Magnitude / dt else 0
		sampleSerial += 1
		samples[(sampleSerial - 1) % capacity + 1] = { sequence = sampleSerial, at = workspace:GetServerTimeNow(), localAt = at,
			position = xyz(point), velocity = xyz(flat), speed = flat.Magnitude, acceleration = acceleration, dt = dt,
			displacement = if lastPoint then (point - lastPoint).Magnitude else 0, renderFrames = renderFrames, simulationFrames = simulationFrames }
		for _, window in windows do
			if at - window.localAt > 1.6 or not character or window.life ~= character:GetAttribute("CombatLife") then continue end
			if not window.firstRootAcceleration and flat.Magnitude > window.baselineSpeed + 3 and acceleration > 30 then
				window.firstRootAcceleration = mark("root_acceleration_candidate", { inputId = window.inputId, speed = flat.Magnitude, acceleration = acceleration, elapsed = at - window.localAt }).at
			end
			if not window.firstSpeedAboveWalk and flat.Magnitude > humanoid.WalkSpeed + 4 then
				window.firstSpeedAboveWalk = mark("speed_above_walk", { inputId = window.inputId, speed = flat.Magnitude, walkSpeed = humanoid.WalkSpeed, elapsed = at - window.localAt }).at
			end
		end
		lastPoint, lastVelocity, lastAt = point, flat, at
	end))
	local function ordered(items: { any }): { any }
		local result = table.clone(items); table.sort(result, function(a, b) return a.sequence < b.sequence end); return result
	end
	return {
		mark = mark,
		inspect = function(): any
			local inputs = {}
			for _, window in windows do local copy = table.clone(window); copy.baseline = nil; table.insert(inputs, copy) end
			return { events = ordered(events), samples = ordered(samples), inputs = inputs, snapshot = snapshot(),
				droppedEvents = math.max(0, serial - capacity), droppedSamples = math.max(0, sampleSerial - capacity), stopped = stopped }
		end,
		destroy = function()
			if stopped then return end
			mark("destroy"); stopped = true
			for _, connection in connections do connection:Disconnect() end
			for _, connection in bodyConnections do connection:Disconnect() end
			table.clear(connections); table.clear(bodyConnections); table.clear(joints); table.clear(previousJoints); table.clear(watched)
			for _, window in windows do window.baseline = nil end
		end,
	}
end
return Probe
