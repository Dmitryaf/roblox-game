--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Driver = {}
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.025) until os.clock() >= deadline
	error(message)
end
function Driver.new(player: Player)
	local loadModule = require :: any
	local MotionProbe: any = loadModule(ReplicatedStorage:WaitForChild("WarriorMotionProbe", 20) :: ModuleScript)
	local classRemote = ReplicatedStorage:WaitForChild("ClassRemote", 20) :: RemoteEvent
	local meleeRemote = ReplicatedStorage:WaitForChild("MeleeRemote", 20) :: RemoteEvent
	local arrowRemote = ReplicatedStorage:WaitForChild("ArrowRemote", 20) :: RemoteEvent
	local handsRemote = ReplicatedStorage:WaitForChild("HandsRemote", 20) :: RemoteEvent
	local connections: { RBXScriptConnection } = {}
	local classState: any = nil
	local replies: { [string]: { [number]: any } } = { class = {}, arrow = {}, hands = {} }
	local meleeReply: any = nil
	local meleeReplies, preparing, struck, arrowPreparing = 0, 0, 0, 0
	local replyHistory: { any } = {}
	local visualSeen = false
	local probeId = 500000
	local aim: RBXScriptConnection? = nil
	local function observe(remote: RemoteEvent, key: string)
		table.insert(connections, remote.OnClientEvent:Connect(function(event: any)
			if event.kind == "reply" then replies[key][event.requestId] = event end
			if key == "class" and (event.kind == "snapshot" or event.kind == "reply") then classState = event.state end
			if key == "arrow" and event.kind == "preparing" and event.owner == player.UserId then arrowPreparing += 1 end
		end))
	end
	observe(classRemote, "class"); observe(arrowRemote, "arrow"); observe(handsRemote, "hands")
	table.insert(connections, meleeRemote.OnClientEvent:Connect(function(event: any)
		if event.kind == "reply" then
			meleeReplies += 1; meleeReply = event
			table.insert(replyHistory, { at = os.clock(), event = event })
		end
		if event.kind == "preparing" and event.owner == player.UserId then preparing += 1 end
		if event.kind == "struck" then
			struck += 1
			task.delay(0.03, function()
				local folder = workspace:FindFirstChild("LocalMeleeEffects")
				if folder and folder:FindFirstChild("WarriorSwing") then visualSeen = true end
			end)
		end
	end))
	local function root(): BasePart?
		local character = player.Character
		local part = if character then character:FindFirstChild("HumanoidRootPart") else nil
		return if part and part:IsA("BasePart") then part else nil
	end
	local function life(): number
		local character = player.Character
		local value = if character then character:GetAttribute("CombatLife") else nil
		assert(type(value) == "number", "Current CombatLife absent")
		return value
	end
	local function click(point: Vector2)
		local virtual = UserInputService:CreateVirtualInput()
		assert(virtual, "VirtualInput unavailable")
		virtual:SendMousePosition(point)
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton2, true)
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton2, false)
		task.wait(0.1)
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
		task.wait(0.06)
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
	end
	local function inspect(): any
		local character = player.Character
		local body = root()
		local armour = if character then character:FindFirstChild("WarriorArmour") else nil
		local count = 0
		if armour then
			for _, item in armour:GetDescendants() do
				if item:IsA("BasePart") then
					count += 1
					assert(not item.Anchored and item.Massless and not item.CanCollide and not item.CanQuery and not item.CanTouch,
						"Warrior appearance entered combat physics")
                    local weld = item:FindFirstChild("WarriorVisualWeld")
                    assert(weld and weld:IsA("Weld") and weld.Part1 == item and weld.Part0 ~= nil
                        and weld.Part0.Parent == character, "Warrior appearance is not attached to its live body")
				end
			end
		end
		local effects = workspace:FindFirstChild("LocalMeleeEffects")
		return { position = if body then body.Position else nil, life = life(),
			classId = if character then character:GetAttribute("CombatClass") else nil, state = classState,
			armourParts = count, sword = armour ~= nil and armour:FindFirstChild("WarriorSwordBlade") ~= nil,
			warlock = character ~= nil and character:FindFirstChild("WarlockCostume") ~= nil,
			preparing = preparing, struck = struck, visualSeen = visualSeen,
			effectChildren = if effects then #effects:GetChildren() else -1 }
	end
	local driver = {}
	function driver.ready()
		waitFor(function()
			local character = player.Character
			return character ~= nil and root() ~= nil and type(character:GetAttribute("CombatLife")) == "number"
				and character:GetAttribute("CombatLife") > 0 and classState ~= nil and classState.alive
				and player.PlayerGui:FindFirstChild("ClassHud") ~= nil and player.PlayerGui:FindFirstChild("MeleeHud") ~= nil
				and player.PlayerGui:FindFirstChild("MatchHud") ~= nil
		end, 45, "Production class/melee controllers and character did not initialize")
	end
	function driver.run(action: string, data: any?): any
		if action == "inspect" then return inspect() end
		if action == "runWhileMoving" then
			return MotionProbe.run(player, { root = root, inspect = inspect, click = click, history = replyHistory,
				replyCount = function() return meleeReplies end, reply = function() return meleeReply end })
		end
		if action == "chooseWarrior" then
			local hud = player.PlayerGui:FindFirstChild("ClassHud") :: ScreenGui
			local button = hud:FindFirstChild("WarriorButton", true) :: TextButton
			waitFor(function() return button.Active and button.Visible end, 4, "Warrior button not enabled")
			local before, oldLife = arrowPreparing, life()
			local center = button.AbsolutePosition + button.AbsoluteSize / 2
			local found = false
			for _, object in player.PlayerGui:GetGuiObjectsAtPosition(center.X, center.Y) do if object == button then found = true end end
			assert(found, "Warrior button was not hit-testable")
			click(center + (if hud.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()))
			waitFor(function()
				local character = player.Character
				return character ~= nil and character:GetAttribute("CombatClass") == "warrior" and life() > oldLife
					and character:FindFirstChild("WarriorArmour") ~= nil and character:FindFirstChild("WarlockCostume") == nil
			end, 6, "Real WarriorButton did not change class/life/appearance")
			task.wait(0.35)
			assert(arrowPreparing == before, "GUI class choice accidentally cast magic")
			local info = inspect()
			assert(info.sword and info.armourParts > 10, "Full warrior sword/armour absent")
			return info
		elseif action == "ready" then
			local virtual = UserInputService:CreateVirtualInput()
			assert(virtual, "Virtual keyboard unavailable")
			virtual:SendKey(true, Enum.KeyCode.R, false); virtual:SendKey(false, Enum.KeyCode.R, false)
		elseif action == "classProbe" then
			probeId += 1
			local id = probeId
			classRemote:FireServer({ action = "select", requestId = id, life = life(), classId = data.classId })
			waitFor(function() return replies.class[id] ~= nil end, 4, "Class lock probe received no reply")
			local reply = replies.class[id]
			assert(not reply.ok and reply.reason == data.reason, "Unexpected class lock result: " .. tostring(reply.reason))
			return reply
		elseif action == "wrongMagic" then
			local magicRemotes: { [string]: RemoteEvent } = { arrow = arrowRemote, hands = handsRemote }
			for key, remote in magicRemotes do
				probeId += 1
				local id = probeId
				local request: any = { action = "cast", requestId = id, life = life() }
				if key == "arrow" then request.direction = Vector3.new(0, 0, -1) else request.position = Vector3.new(0, 0, -30) end
				remote:FireServer(request)
				waitFor(function() return replies[key][id] ~= nil end, 4, "Wrong-class magic received no reply")
				assert(not replies[key][id].ok and replies[key][id].reason == "wrong_class", "Warrior could cast " .. key)
			end
		elseif action == "swing" then
			local point = data :: Vector3
			local camera = workspace.CurrentCamera :: Camera
			local aimedAt = CFrame.lookAt(point + Vector3.new(14, 16, 18), point)
			if aim then aim:Disconnect() end
			camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, aimedAt
			aim = RunService.RenderStepped:Connect(function()
				camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, aimedAt
			end)
			task.wait(0.12)
			local projected = camera:WorldToViewportPoint(point)
			local mouse = Vector2.new(projected.X, projected.Y)
			local before = meleeReplies
			click(mouse)
			local accepted, problem = pcall(function()
				waitFor(function() return meleeReplies > before end, 5, "Real LMB produced no melee reply")
				assert(meleeReply.ok, "Real LMB rejected: " .. tostring(meleeReply.reason))
			end)
			if aim then aim:Disconnect(); aim = nil end
			assert(accepted, tostring(problem))
			return { reply = meleeReply, preparing = preparing }
		else error("Unknown warrior fixture command: " .. action) end
		return inspect()
	end
	function driver.destroy()
		if aim then aim:Disconnect(); aim = nil end
		for _, connection in connections do connection:Disconnect() end
	end
	return driver
end
return Driver
