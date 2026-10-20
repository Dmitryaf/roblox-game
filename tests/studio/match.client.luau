--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local control = ReplicatedStorage:WaitForChild("MatchTestControl") :: RemoteEvent
local matchRemote = ReplicatedStorage:WaitForChild("MatchRemote", 20) :: RemoteEvent
local arrowRemote = ReplicatedStorage:WaitForChild("ArrowRemote", 20) :: RemoteEvent
local latest: any = nil
local arrowLife = 0
local castSequence = 50000
local arrowReplies: { [number]: any } = {}
local snapshotCount = 0
local ownPreparing = 0
local connections: { RBXScriptConnection } = {}
local renderErrors = {}
local presentationFrames = 0
local simulationFrames, heartbeatFrames = 0, 0
table.insert(connections, game:GetService("RunService").RenderStepped:Connect(function() presentationFrames += 1 end))
table.insert(connections, game:GetService("RunService").PreSimulation:Connect(function() simulationFrames += 1 end))
table.insert(connections, game:GetService("RunService").Heartbeat:Connect(function() heartbeatFrames += 1 end))
table.insert(connections, game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(renderErrors, message)
		if #renderErrors > 4 then table.remove(renderErrors, 1) end
	end
end))

local function currentLife(): number
	local character = player.Character
	local attribute = if character then character:GetAttribute("CombatLife") else nil
	return if type(attribute) == "number" then attribute else arrowLife
end

local function initializationFlags(): string
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local bodyParts = {}
	if character then
		for _, item in character:GetChildren() do if item:IsA("BasePart") then table.insert(bodyParts, item.Name) end end
	end
	return game:GetService("HttpService"):JSONEncode({
		owner = player.UserId, character = character ~= nil,
		root = character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil,
		hud = player.PlayerGui:FindFirstChild("MatchHud") ~= nil,
		latest = latest ~= nil, snapshots = snapshotCount, life = currentLife(), arrowLife = arrowLife,
		renderErrors = renderErrors,
		presentationFrames = presentationFrames,
		simulationFrames = simulationFrames, heartbeatFrames = heartbeatFrames,
		health = if humanoid then humanoid.Health else nil, bodyParts = bodyParts,
	})
end

local function untilTrue(predicate: () -> boolean, seconds: number, reason: string)
	local deadline = os.clock() + seconds
	repeat
		if predicate() then return end
		task.wait(0.03)
	until os.clock() >= deadline
	error(reason)
end

table.insert(connections, matchRemote.OnClientEvent:Connect(function(event)
	if event.kind == "snapshot" then
		latest = event.state
		snapshotCount += 1
	end
end))
table.insert(connections, arrowRemote.OnClientEvent:Connect(function(event)
	if event.kind == "snapshot" then arrowLife = event.state.life end
	if event.kind == "preparing" and event.owner == player.UserId then
		arrowLife = event.life
		ownPreparing += 1
	end
	if event.kind == "reply" then arrowReplies[event.requestId] = event end
end))

local function press(key: Enum.KeyCode)
	local virtual = UserInputService:CreateVirtualInput()
	assert(virtual, "VirtualInput unavailable")
	virtual:SendKey(true, key, false)
	task.wait(0.08)
	virtual:SendKey(false, key, false)
end

local function inspectHud()
	local hud = player.PlayerGui:FindFirstChild("MatchHud")
	assert(hud and hud:IsA("ScreenGui"), "Production MatchHud absent")
	local ready = hud:FindFirstChild("ReadyButton", true)
	local exit = hud:FindFirstChild("ExitButton", true)
	assert(ready and ready:IsA("GuiButton"), "ReadyButton absent")
	assert(exit and exit:IsA("GuiButton"), "ExitButton absent")
	local score = hud:FindFirstChild("ScorePanel") :: GuiObject?
	local actions = hud:FindFirstChild("ActionPanel") :: GuiObject?
	local arrowHud = player.PlayerGui:FindFirstChild("ArrowHud")
	local ability = if arrowHud then arrowHud:FindFirstChild("Ability") :: GuiObject? else nil
	assert(score and actions and ability, "HUD layout panels absent")
	assert(arrowHud and arrowHud:IsA("ScreenGui"), "ArrowHud canvas absent")
	untilTrue(function()
		if hud.AbsoluteSize.X <= 100 or hud.AbsoluteSize.Y <= 100
			or arrowHud.AbsoluteSize.X <= 100 or arrowHud.AbsoluteSize.Y <= 100 then return false end
		for _, name in { "Goal", "Score" } do
			local text = (score :: GuiObject):FindFirstChild(name)
			if not text or not text:IsA("TextLabel") or text.TextBounds.X <= 0 or text.TextBounds.Y <= 0 then return false end
		end
		return true
	end, 5, "GUI canvases or header text metrics did not initialize")
	-- A hidden Studio test camera can retain ViewportSize=(1,1), while the GUI
	-- canvas is already laid out. Compare each panel with its actual GUI root.
	local panels = { score :: GuiObject, actions :: GuiObject, ability :: GuiObject }
	for index, panel in panels do
		local p, size = panel.AbsolutePosition, panel.AbsoluteSize
		local canvas = if panel == ability then arrowHud else hud
		local origin, viewport = canvas.AbsolutePosition, canvas.AbsoluteSize
		local relative = p - origin
		assert(panel.Visible and size.X > 0 and size.Y > 0, "HUD panel hidden or empty: " .. panel.Name)
		assert(relative.X >= -1 and relative.Y >= -1 and relative.X + size.X <= viewport.X + 1 and relative.Y + size.Y <= viewport.Y + 1,
			"HUD panel outside GUI canvas: " .. panel.Name .. " at " .. tostring(relative) .. " size " .. tostring(size) .. " canvas " .. tostring(viewport))
		for otherIndex = index + 1, #panels do
			local other = panels[otherIndex]
			local q, extent = other.AbsolutePosition, other.AbsoluteSize
			local overlap = p.X < q.X + extent.X - 1 and p.X + size.X > q.X + 1
				and p.Y < q.Y + extent.Y - 1 and p.Y + size.Y > q.Y + 1
			assert(not overlap, "HUD panels overlap: " .. panel.Name .. "/" .. other.Name)
		end
	end
	for _, name in { "Goal", "Score" } do
		local text = (score :: GuiObject):FindFirstChild(name)
		assert(text and text:IsA("TextLabel"), "Header label absent: " .. name)
		assert(text.TextBounds.Y <= text.AbsoluteSize.Y + 1, "Header label clips vertically: " .. name)
	end
	return { readyVisible = ready.Visible, exitVisible = exit.Visible,
		viewport = tostring(hud.AbsoluteSize), arrowViewport = tostring(arrowHud.AbsoluteSize), layoutVerified = true }
end

local function readyClick(): any
	local hud = player.PlayerGui:FindFirstChild("MatchHud") :: ScreenGui
	local button = hud:FindFirstChild("ReadyButton", true) :: GuiButton
	untilTrue(function() return button.Visible and button.Active end, 3, "Ready button is not available for clicking")
	assert(latest and not latest.ready and latest.mode == "training", "Click fixture needs an unready training player")
	local center = button.AbsolutePosition + button.AbsoluteSize / 2
	local inset = GuiService:GetGuiInset()
	local picked = false
	for _, object in player.PlayerGui:GetGuiObjectsAtPosition(center.X, center.Y) do
		if object == button then picked = true; break end
	end
	assert(picked, "Ready button could not be picked at its observed GUI center")
	-- GUI hit testing uses inset-relative coordinates; VirtualInput takes screen coordinates.
	local point = center + (if hud.IgnoreGuiInset then Vector2.zero else inset)
	local virtual = UserInputService:CreateVirtualInput()
	assert(virtual, "VirtualInput unavailable")
	local before = ownPreparing
	virtual:SendMousePosition(point)
	task.wait(0.1)
	virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
	task.wait(0.08)
	virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
	untilTrue(function() return latest ~= nil and latest.ready == true end, 4, "Ready button click received no authoritative readiness")
	task.wait(0.35)
	assert(ownPreparing == before, "Clicking Ready also started an arrow cast")
	return { state = latest, snapshots = snapshotCount, preparingBefore = before,
		preparingAfter = ownPreparing, clickPoint = tostring(point), hud = inspectHud() }
end

table.insert(connections, control.OnClientEvent:Connect(function(command, sequence, data)
	local ok, result = xpcall(function(): any
		if command == "ready" then
			press(Enum.KeyCode.R)
		elseif command == "readyClick" then
			return readyClick()
		elseif command == "exit" then
			press(Enum.KeyCode.B)
		elseif command == "cast" then
			-- Fault probes use the public endpoint; ordinary match actions use real input.
			castSequence += 1
			local id = castSequence
			assert(currentLife() > 0, "Cast probe has no current life token")
			arrowRemote:FireServer({ action = "cast", requestId = id, life = currentLife(),
				direction = data or Vector3.new(0, 0, -1) })
			untilTrue(function() return arrowReplies[id] ~= nil end, 4, "Cast probe received no reply")
			return arrowReplies[id]
		elseif command == "inspect" then
			local hud = inspectHud()
			return { state = latest, snapshots = snapshotCount, hud = hud }
		elseif command == "finish" then
			for _, connection in connections do connection:Disconnect() end
		else
			error("Unknown match test command: " .. tostring(command))
		end
		return { state = latest, snapshots = snapshotCount }
	end, debug.traceback)
	control:FireServer("report", sequence, { ok = ok, data = if ok then result else nil,
		error = if ok then nil else tostring(result) })
end))

local ok, err = xpcall(function()
	untilTrue(function()
		return player.Character ~= nil and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
			and player.PlayerGui:FindFirstChild("MatchHud") ~= nil and latest ~= nil and currentLife() > 0
	end, 60, "Production character, MatchHud or initial snapshot absent")
	inspectHud()
	local loadArt = require :: any
	local artTests = loadArt(ReplicatedStorage:WaitForChild("WarlockArtTests") :: ModuleScript)
	print("PASS Warlock art contracts " .. game:GetService("HttpService"):JSONEncode(artTests.run()))
	print("MatchTest client ready " .. initializationFlags())
	control:FireServer("ready")
end, debug.traceback)
if not ok then
	local diagnostic = tostring(err) .. "\n" .. initializationFlags()
	warn("MatchTest client initialization failed " .. diagnostic)
	control:FireServer("initialFailure", 0, { ok = false, error = diagnostic })
end
