--!strict
-- Isolated technical viewer. Real casts use MixedDriver/actual keys. Reaction preview
-- uses a nonphysical cloned rig and a labelled synthetic presentation event only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(RunService:IsStudio(), "Feedback review is local Studio-only")
local token = ReplicatedStorage:WaitForChild("StudioTestToken") :: StringValue
assert(token.Value:match("^feedback%-review%-%x+$"), "Feedback review token missing")
local control = ReplicatedStorage:WaitForChild("FeedbackReviewControl") :: RemoteFunction
local loadModule = require :: any
local Driver: any = loadModule(ReplicatedStorage:WaitForChild("MixedTestDriver") :: ModuleScript)
local Probe: any = loadModule(ReplicatedStorage:WaitForChild("FeedbackProbe") :: ModuleScript)
local driver = Driver.new(player)
local probe: any = nil
local connections: { RBXScriptConnection } = {}
local stopped, busy, vfxEnabled = false, true, true
local hidden: { [Instance]: { name: string, value: any } } = {}
local clone: Model? = nil
local reaction: any = nil
local cloneLayers: any = nil
local reactionId, captureId, capturePending = 0, 0, false
local loopEnabled, loopPaused, viewIndex = false, false, 1
local reviewMode, selectedAbility = "attack", "melee"
local previewCamera: any = nil
local mailbox = Instance.new("Folder")
mailbox.Name, mailbox.Parent = "FeedbackReviewCapture", ReplicatedStorage
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "FeedbackReview", false, 100
gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("Frame")
panel.Size, panel.Position, panel.BackgroundColor3 = UDim2.fromOffset(340, 496), UDim2.new(1, -350, 0, 46), Color3.fromRGB(22, 25, 32)
panel.Parent = gui
local title = Instance.new("TextLabel")
title.Size, title.BackgroundTransparency, title.TextColor3, title.TextSize = UDim2.new(1, -16, 0, 44), 1, Color3.new(1, 1, 1), 17
title.Position, title.Text, title.TextWrapped, title.Parent = UDim2.fromOffset(8, 4), "Технический просмотр · Studio\nХудожественная оценка не выставлена", true, panel
local status = Instance.new("TextLabel")
status.Size, status.Position, status.BackgroundTransparency = UDim2.new(1, -16, 0, 68), UDim2.fromOffset(8, 420), 1
status.TextColor3, status.TextSize, status.TextWrapped, status.Text, status.Parent = Color3.fromRGB(205, 215, 225), 14, true, "Ожидаем реальный клиент…", panel
local function say(message: string)
	status.Text = message
	print(token.Value .. " REVIEW " .. message)
end
local function root(): BasePart
	local character = player.Character
	local value = if character then character:FindFirstChild("HumanoidRootPart") else nil
	assert(value and value:IsA("BasePart"), "Review root absent"); return value
end
local function capture(action: string, label: string): any
	if capturePending then return { ok = false, status = "capture_busy" } end
	if mailbox:GetAttribute("BridgeReady") ~= true then return { ok = false, status = "plugin_bridge_unavailable" } end
	capturePending = true; captureId += 1
	local id = captureId
	mailbox:SetAttribute("Action", action); mailbox:SetAttribute("Label", label); mailbox:SetAttribute("RequestId", id)
	local deadline = os.clock() + (if action == "permission" then 60 else 12)
	while not stopped and mailbox:GetAttribute("DoneId") ~= id and os.clock() < deadline do task.wait(0.03) end
	capturePending = false
	if stopped or mailbox:GetAttribute("DoneId") ~= id then return { ok = false, status = "plugin_response_timeout" } end
	return HttpService:JSONDecode(mailbox:GetAttribute("Response") :: string)
end
local function clearClone()
	if cloneLayers then cloneLayers.destroy(); cloneLayers = nil end
	if reaction then reaction.destroy(); reaction = nil end
	if clone then clone:Destroy(); clone = nil end
	if previewCamera then
		previewCamera.camera.CameraType, previewCamera.camera.CFrame = previewCamera.kind, previewCamera.frame
		previewCamera = nil
	end
end
local function cameraView()
	local camera = workspace.CurrentCamera :: Camera
	local offsets = { Vector3.new(10, 5, 15), Vector3.new(12, 4, 0), Vector3.new(8, 5, -14) }
	camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, CFrame.lookAt(root().Position + offsets[viewIndex], root().Position + Vector3.new(0, 1, -3))
end
local function preview(kind: string)
	clearClone()
	local character = player.Character :: Model
	local original = character.Archivable; character.Archivable = true
	local replica = character:Clone(); character.Archivable = original
	replica.Name = "ReviewReactionPreview"
	replica:SetAttribute("TrainingTarget", true)
	replica:SetAttribute("CombatLife", 9000000 + reactionId)
	for _, item in replica:GetDescendants() do
		if item:IsA("BaseScript") or item:IsA("Sound") or item:IsA("LinearVelocity") then item:Destroy()
		elseif item:IsA("BasePart") then item.CanCollide, item.CanTouch, item.CanQuery = false, false, false end
	end
	local cloneRoot = replica:FindFirstChild("HumanoidRootPart") :: BasePart
	cloneRoot.Anchored = true
	replica:PivotTo(root().CFrame * CFrame.new(-5, 0, 0)); replica.Parent = workspace; clone = replica
	local gameScripts = (player:WaitForChild("PlayerScripts")):WaitForChild("Game")
	local presentation = gameScripts:WaitForChild("presentation")
	local HitReaction: any = loadModule(presentation:WaitForChild("HitReaction") :: ModuleScript)
	local Layers: any = loadModule(presentation:WaitForChild("PoseLayers") :: ModuleScript)
	reaction = HitReaction.new(); cloneLayers = Layers.new({ reaction })
	reactionId += 1
	local event = { kind = if kind == "arrow" then "ended" else "contact", reason = "hit", style = if kind == "heavy" then "heavy" else nil,
		owner = player.UserId, life = character:GetAttribute("CombatLife"), swingId = reactionId, castId = reactionId, contactId = 1,
		targetModel = replica, targetLife = replica:GetAttribute("CombatLife"), contactAt = workspace:GetServerTimeNow(),
		sourcePosition = cloneRoot.Position + cloneRoot.CFrame.LookVector * 6 }
	assert(reaction.hit(event), "Production reaction rejected the labelled preview event")
	probe.mark("reaction_preview", { kind = kind, synthetic = true, physical = false })
	say("Реакция " .. kind .. ": визуальный клон слева; это не попадание и не урон.")
	local camera = workspace.CurrentCamera :: Camera
	previewCamera = { camera = camera, kind = camera.CameraType, frame = camera.CFrame }
	local offsets = { Vector3.new(-10, 6, 14), Vector3.new(-13, 4, 0), Vector3.new(-8, 5, -14) }
	camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, CFrame.lookAt(cloneRoot.Position + offsets[viewIndex], cloneRoot.Position + Vector3.new(0, 1, 0))
	task.delay(0.06, function() if not stopped and clone == replica then capture("capture", "reaction-preview-" .. kind) end end)
	-- Keep the preview in view until another action. Lifecycle cleanup belongs to this viewer.
end
local function visibleEffect(item: Instance)
	if vfxEnabled or hidden[item] then return end
	local property: string? = nil
	if item:IsA("BasePart") or item:IsA("Trail") or item:IsA("Beam") then property = "LocalTransparencyModifier"
	elseif item:IsA("ParticleEmitter") or item:IsA("Light") then property = "Enabled" end
	if not property then return end
	local ok, old = pcall(function() return (item :: any)[property :: string] end)
	if not ok then return end
	hidden[item] = { name = property, value = old }
end
local function setVfx(enabled: boolean)
	vfxEnabled = enabled
	if enabled then
		for item, value in hidden do if item.Parent then pcall(function() (item :: any)[value.name] = value.value end) end end
		table.clear(hidden)
	end
	if probe then probe.mark("vfx_visibility", { enabled = enabled, localOnly = true }) end
end
table.insert(connections, RunService.RenderStepped:Connect(function()
	if vfxEnabled then return end
	for _, name in { "LocalArrowEffects", "LocalHandsEffects", "LocalMeleeEffects", "LocalHeavyEffects", "LocalDashEffects" } do
		local folder = workspace:FindFirstChild(name)
		if folder then for _, item in folder:GetDescendants() do visibleEffect(item) end end
	end
	if player.Character then
		for _, item in player.Character:GetDescendants() do
			-- Only action trails/particles; no mover, rig, armour or ambient class skin changes.
			if item:IsA("Trail") or item:IsA("Beam") or item:IsA("ParticleEmitter") or item:IsA("Light") then visibleEffect(item) end
		end
	end
	for item, value in hidden do
		if not item.Parent then hidden[item] = nil
		else pcall(function() (item :: any)[value.name] = if value.name == "Enabled" then false else 1 end) end
	end
end))
local function place(z: number)
	assert(control:InvokeServer("place", Vector3.new(230, 3, z)), "Review fixture placement failed")
	task.wait(0.3)
end
local function selectClass(classId: string)
	-- The technical panel must not intercept the real production class button.
	local visible = panel.Visible
	panel.Visible = false
	local ok, result = pcall(function() return driver.run("class", classId) end)
	panel.Visible = visible
	assert(ok, tostring(result))
end
local function cast(ability: string)
	clearClone()
	local key = if ability == "teleport" then "arrow" else ability
	local state = driver.run("inspect").states[key]
	if state and state.readyAt > workspace:GetServerTimeNow() then say("Способность восстанавливается. Повторите после cooldown."); return end
	probe.mark("review_cast", { ability = ability })
	task.delay(if ability == "arrow" then 0.18 else 0.08, function() if not stopped then capture("capture", ability .. "-preparation") end end)
	-- Keep the selected inspection angle throughout the actual cast. Reuse the
	-- production input stream, with no successful gameplay RemoteEvent fabricated.
	cameraView(); RunService.RenderStepped:Wait()
	local input = UserInputService:CreateVirtualInput(); assert(input, "Review virtual input unavailable")
	local camera = workspace.CurrentCamera :: Camera
	local screen, visible = camera:WorldToViewportPoint(Vector3.new(230, 2.5, -38))
	local point = if visible then Vector2.new(screen.X, screen.Y) else camera.ViewportSize / 2
	if not visible then probe.mark("review_aim_fallback", { ability = ability, reason = "target_outside_selected_angle", actualHitGuaranteed = false }) end
	input:SendMousePosition(point)
	local panelVisible = panel.Visible
	panel.Visible = false
	-- As in MixedDriver.withView, focus the viewport before the real key. A
	-- technical GUI button can otherwise leave Studio handling the keyboard.
	input:SendMouseButton(point, Enum.UserInputType.MouseButton2, true)
	input:SendMouseButton(point, Enum.UserInputType.MouseButton2, false)
	RunService.RenderStepped:Wait()
	local before = probe.mark("review_key", { ability = ability }).sequence
	if ability == "melee" or ability == "arrow" then
		input:SendMouseButton(point, Enum.UserInputType.MouseButton1, true); input:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
	else
		local keyCode = if ability == "dash" or ability == "teleport" then Enum.KeyCode.E else Enum.KeyCode.Q
		input:SendKey(true, keyCode, false); input:SendKey(false, keyCode, false)
	end
	panel.Visible = panelVisible
	local result: any = nil
	local deadline = os.clock() + 5
	repeat
		for _, event in probe.inspect().events do
			if event.sequence > before and event.label == "remote_reply" and event.data.ability == key then result = event.data; break end
		end
		if result then break end
		task.wait(0.02)
	until stopped or os.clock() >= deadline
	assert(result and result.ok, "Review real key refused or timed out: " .. tostring(if result then result.reason else "timeout"))
	say("Реальная клавиша " .. ability .. ": сервер принял действие. Кадр ещё не оценён.")
	return result
end
local function run(label: string, action: () -> ())
	if busy or stopped then return end
	busy = true
	task.spawn(function()
		local ok, problem = xpcall(function() action(); return true end, debug.traceback)
		if not ok then say(label .. ": " .. tostring(problem)) end
		busy = false
	end)
end
local function button(text: string, index: number, action: () -> (), immediate: boolean?)
	local item = Instance.new("TextButton")
	item.Text, item.TextSize, item.TextColor3 = text, 14, Color3.new(1, 1, 1)
	item.Size, item.Position = UDim2.fromOffset(158, 31), UDim2.fromOffset(8 + (index % 2) * 166, 56 + math.floor(index / 2) * 37)
	item.BackgroundColor3, item.Parent = Color3.fromRGB(52, 61, 76), panel
	table.insert(connections, item.Activated:Connect(function() if immediate then action() else run(text, action) end end))
end
button("Воин", 0, function() clearClone(); selectClass("warrior"); place(-30); selectedAbility, reviewMode = "melee", "attack"; cameraView(); say("Воин · реальные LMB/Q/E, WASD.") end)
button("Чернокнижник", 1, function() clearClone(); selectClass("warlock"); place(-18); selectedAbility, reviewMode = "arrow", "attack"; cameraView(); say("Чернокнижник · реальные LMB/Q/E, WASD.") end)
button("Обычная атака", 2, function() selectedAbility, reviewMode = if driver.run("inspect").classId == "warrior" then "melee" else "arrow", "attack"; cast(selectedAbility) end)
button("Способность Q", 3, function() selectedAbility, reviewMode = if driver.run("inspect").classId == "warrior" then "heavy" else "hands", "attack"; cast(selectedAbility) end)
button("Рывок E", 4, function() if driver.run("inspect").classId ~= "warrior" then say("Для рывка выберите воина."); return end; selectedAbility, reviewMode = "dash", "attack"; place(20); cast("dash") end)
button("W · 1 секунда", 5, function() reviewMode = "move"; clearClone(); place(20); driver.run("move", { direction = Vector3.new(0, 0, -1), duration = 1 }); cameraView(); say("W выполнена реальной клавишей.") end)
button("Реакция: меч", 6, function() reviewMode, selectedAbility = "reaction", "melee"; preview("melee") end)
button("Реакция: тяжёлая", 7, function() reviewMode, selectedAbility = "reaction", "heavy"; preview("heavy") end)
button("VFX вкл / выкл · F6", 8, function() setVfx(not vfxEnabled); say(if vfxEnabled then "VFX видны." else "VFX скрыты локально; позы и правила действуют.") end, true)
button("Снять PNG", 9, function() local result = capture("capture", "manual"); say("PNG: " .. result.status) end)
button("Проверить capture", 10, function() local result = capture("preflight", "capability"); say("Capture: " .. result.status) end)
button("Разрешение PNG…", 11, function() local result = capture("permission", "explicit-user-request"); say("Capture: " .. result.status) end)
button("Реакция: стрела", 12, function() reviewMode, selectedAbility = "reaction", "arrow"; preview("arrow") end)
button("Сводка измерений", 13, function()
	local data = probe.inspect()
	print(token.Value .. " PROBE_SUMMARY " .. HttpService:JSONEncode({ inputs = data.inputs, events = data.events, snapshot = data.snapshot }))
	say("Сводка ввода/суставов/физики сохранена в локальном Output.")
end)
local function toggleLoop()
	if loopEnabled then loopEnabled = false; say("Повтор остановится после текущего действия."); return end
	if busy then return end
	loopEnabled, loopPaused = true, false
	run("Повтор", function()
		while loopEnabled and not stopped do
			if loopPaused then task.wait(0.05); continue end
			if reviewMode == "reaction" then preview(selectedAbility)
			elseif reviewMode == "move" then clearClone(); place(20); driver.run("move", { direction = Vector3.new(0, 0, -1), duration = 1 }); cameraView()
			else
				local state = driver.run("inspect").states[selectedAbility]
				if state and state.readyAt > workspace:GetServerTimeNow() then task.wait(0.05); continue end
				place(if selectedAbility == "dash" then 20 else if driver.run("inspect").classId == "warrior" then -30 else -18)
				cast(selectedAbility)
			end
			local untilAt = os.clock() + 1.3
			while loopEnabled and not stopped and os.clock() < untilAt do task.wait(0.05) end
		end
		loopEnabled = false
	end)
end
local function togglePause() loopPaused = not loopPaused; say(if loopPaused then "Пауза повтора; физика и текущая анимация продолжаются." else "Повтор продолжен.") end
local function angle() viewIndex = viewIndex % 3 + 1; clearClone(); cameraView(); say("Ракурс " .. viewIndex .. " из 3.") end
button("Повтор / стоп · F8", 14, toggleLoop, true)
button("Пауза повтора · F9", 15, togglePause, true)
button("Ракурс · F4", 16, angle, true)
button("Скрыть панель · F3", 17, function() panel.Visible = false end, true)
table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	local focus: any = UserInputService:GetFocusedTextBox()
	if processed or focus or stopped then return end
	if input.KeyCode == Enum.KeyCode.F3 then panel.Visible = not panel.Visible
	elseif input.KeyCode == Enum.KeyCode.F4 then angle()
	elseif input.KeyCode == Enum.KeyCode.F6 then setVfx(not vfxEnabled)
	elseif input.KeyCode == Enum.KeyCode.F7 then run("Реакция", function() reviewMode, selectedAbility = "reaction", "heavy"; preview("heavy") end)
	elseif input.KeyCode == Enum.KeyCode.F8 then toggleLoop()
	elseif input.KeyCode == Enum.KeyCode.F9 then togglePause() end
end))
local function cleanup()
	if stopped then return end
	stopped, loopEnabled = true, false; clearClone(); setVfx(true)
	for _, connection in connections do connection:Disconnect() end
	driver.destroy(); if probe then probe.destroy() end
	mailbox:Destroy(); gui:Destroy()
	local camera = workspace.CurrentCamera
	if camera then camera.CameraType = Enum.CameraType.Custom end
end
script.Destroying:Connect(cleanup)
task.spawn(function()
	local ok, problem = xpcall(function()
		driver.ready(); probe = Probe.new(player)
		local untilAt = os.clock() + 8
		while mailbox:GetAttribute("BridgeReady") ~= true and os.clock() < untilAt do task.wait(0.05) end
		local capability = capture("preflight", "initial")
		say("Готово. Capture: " .. capability.status .. ". Художественная оценка ещё не выполнена.")
		busy = false
		if ReplicatedStorage:GetAttribute("FeedbackReviewAuto") ~= true then return true end
		busy = true
		for _, classId in { "warrior", "warlock" } do
			selectClass(classId); place(if classId == "warrior" then -30 else -18)
			capture("capture", classId .. "-idle")
			cast(if classId == "warrior" then "melee" else "arrow"); task.wait(1.4)
			cast(if classId == "warrior" then "heavy" else "hands"); task.wait(1.4)
			setVfx(false); place(20)
			task.delay(0.4, function() if not stopped then capture("capture", classId .. "-walk-vfx-off") end end)
			driver.run("move", { direction = Vector3.new(0, 0, -1), duration = 1 }); setVfx(true)
			preview("heavy"); task.wait(0.8); clearClone()
		end
		local report = probe.inspect()
		print(token.Value .. " PROBE_SUMMARY " .. HttpService:JSONEncode({ inputs = report.inputs, events = report.events, snapshot = report.snapshot }))
		cleanup()
		control:InvokeServer("finish", nil, { ok = true, technicalSequenceCompleted = true, captureCapability = capability,
			visualVerdict = "unreviewed", inputCount = #report.inputs })
		return true
	end, debug.traceback)
	if not ok then
		say("Просмотр прерван: " .. tostring(problem)); busy = false
		if ReplicatedStorage:GetAttribute("FeedbackReviewAuto") == true then control:InvokeServer("finish", nil, { ok = false, error = tostring(problem), visualVerdict = "unreviewed" }) end
	end
end)
