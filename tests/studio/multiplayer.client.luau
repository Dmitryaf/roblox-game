--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local control = ReplicatedStorage:WaitForChild("SliceTestControl") :: RemoteEvent
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 15) :: RemoteEvent
local life, castId = 0, 0
local launched, teleported, ended = 0, 0, 0
local visualSeen = false
local soundSeen = false
local launchReceivedAt = 0
local duplicate: any = nil
local replies = {}
local inputCount = 0
local deathCastPending = false
local staleLifeReply: any = nil
local renderErrors = {}
game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(renderErrors, message)
		if #renderErrors > 4 then table.remove(renderErrors, 1) end
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then inputCount += 1 end
end)
remote.OnClientEvent:Connect(function(event)
	if event.kind == "reply" then table.insert(replies, { ok = event.ok, reason = event.reason, life = event.life }) end
	if event.kind == "snapshot" then life = event.state.life end
	if event.kind == "preparing" and event.owner == player.UserId then
		life, castId = event.life, event.castId
		if deathCastPending then
			deathCastPending = false
			control:FireServer("report", { castForDeath = castId, life = life })
		end
	end
	if event.kind == "launched" then
		launched += 1
		launchReceivedAt = os.clock()
		task.delay(0.05, function()
			local effects = workspace:FindFirstChild("LocalArrowEffects")
			if effects and effects:FindFirstChild("DemonicArrow") then visualSeen = true end
			if effects then
				for _, part in effects:GetChildren() do
					local sound = part:FindFirstChildOfClass("Sound")
					if sound and sound.IsPlaying then soundSeen = true end
				end
			end
		end)
	end
	if event.kind == "ended" then
		ended += 1
		if event.reason == "teleported" then teleported += 1 end
	end
	if event.kind == "reply" and event.requestId == 100000 then duplicate = event end
	if event.kind == "reply" and event.requestId == 100003 then staleLifeReply = event end
end)
local function untilTrue(predicate: () -> boolean, seconds: number, reason: string)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.02) until os.clock() >= deadline
	error(reason)
end
control.OnClientEvent:Connect(function(command, data)
	if command == "report" then
		control:FireServer("report", { launched = launched, teleported = teleported, visualSeen = visualSeen, soundSeen = soundSeen })
		return
	end
	if command == "attack" then
		local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		remote:FireServer({ action = "cast", requestId = 100001, life = life,
			direction = (data - root.Position - Vector3.new(0, 1, 0)).Unit })
		return
	end
	if command == "prepareForDeath" then
		deathCastPending = true
		remote:FireServer({ action = "cast", requestId = 100002, life = life, direction = Vector3.new(0, 0, -1) })
		return
	end
	if command == "verifyRespawn" then
		local ok, err = pcall(function()
			assert(life > data, "Life token did not change after respawn")
			local effects = workspace:FindFirstChild("LocalArrowEffects")
			local remaining = {}
			if effects then for _, item in effects:GetChildren() do table.insert(remaining, item.Name) end end
			assert(effects and #effects:GetChildren() == 0, "Old life retained effects: " .. table.concat(remaining, ", ") .. "\n" .. table.concat(renderErrors, "\n"))
			remote:FireServer({ action = "cast", requestId = 100003, life = data, direction = Vector3.xAxis })
			untilTrue(function() return staleLifeReply ~= nil end, 3, "Stale-life request had no reply")
			assert(not staleLifeReply.ok and staleLifeReply.reason == "stale_life", "Old life accepted after respawn")
		end)
		control:FireServer("report", { ok = ok, error = if ok then nil else tostring(err) })
		return
	end
	if command ~= "exercise" then return end
	local ok, err = xpcall(function()
		local style = require(ReplicatedStorage.Shared.presentation.ArrowStyle)
		local audio = {}
		for _, id in (style.sounds :: { [string]: string }) do
			local sound = Instance.new("Sound")
			sound.SoundId = id
			sound.Parent = workspace
			table.insert(audio, sound)
		end
		game:GetService("ContentProvider"):PreloadAsync(audio)
		for _, sound in audio do
			assert(sound.IsLoaded and sound.TimeLength > 0, "Local audio did not load: " .. sound.SoundId)
			sound:Destroy()
		end
		local virtual = UserInputService:CreateVirtualInput()
		assert(virtual, "VirtualInput unavailable")
		local character = player.Character :: Model
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
		local camera = workspace.CurrentCamera :: Camera
		camera.CameraType = Enum.CameraType.Scriptable
		local beforeWalk = root.Position
		virtual:SendKey(true, Enum.KeyCode.W, false)
		task.wait(0.35)
		virtual:SendKey(false, Enum.KeyCode.W, false)
		task.wait(0.3)
		assert((root.Position - beforeWalk).Magnitude > 1, "WASD movement did not move character")
		-- Use the same raw viewport coordinate space as real mouse input.
		local aim = root.Position + Vector3.new(0, 1, -50)
		camera.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 1, 12), aim)
		local projected = camera:WorldToViewportPoint(aim)
		local center = Vector2.new(projected.X, projected.Y)
		virtual:SendMousePosition(center)
		task.wait(0.2)
		local clickedAt = os.clock()
		virtual:SendMouseButton(center, Enum.UserInputType.MouseButton1, true)
		task.wait(0.08)
		virtual:SendMouseButton(center, Enum.UserInputType.MouseButton1, false)
		untilTrue(function() return launched > 0 end, 4, "Mouse input did not launch arrow")
		local elapsed = launchReceivedAt - clickedAt
		print("ArrowInputToLaunchSeconds", elapsed)
		if data and data > 0 then assert(elapsed >= 0.7 + data / 1000, "Requested network delay was not observed") end
		task.wait(0.35)
		virtual:SendKey(true, Enum.KeyCode.E, false)
		virtual:SendKey(false, Enum.KeyCode.E, false)
		untilTrue(function() return teleported > 0 end, 4, "E did not teleport")
		assert(player.PlayerGui:FindFirstChild("ArrowHud"), "HUD absent")
		remote:FireServer({ action = "teleport", requestId = 100000, life = life, castId = castId })
		untilTrue(function() return duplicate ~= nil end, 3, "Duplicate request had no reply")
		assert(not duplicate.ok and duplicate.reason == "stale_arrow", "Duplicate teleport accepted")
		assert(teleported == 1, "More than one teleport effect")
	end, debug.traceback)
	local hud = player.PlayerGui:FindFirstChild("ArrowHud")
	local label = if hud then hud:FindFirstChild("Ability") else nil
	local diagnostics = game:GetService("HttpService"):JSONEncode({ life = life, input = inputCount, replies = replies,
		hud = if label and label:IsA("TextLabel") then label.Text else "absent", viewport = tostring(workspace.CurrentCamera.ViewportSize) })
	control:FireServer("report", { ok = ok, error = if ok then nil else tostring(err) .. "\n" .. diagnostics, launched = launched, teleported = teleported })
end)
local ok, err = pcall(function()
	untilTrue(function()
		return player.Character ~= nil and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
			and player.PlayerGui:FindFirstChild("ArrowHud") ~= nil
	end, 30, "Client bootstrap did not produce character/HUD")
	-- Production controller owns request IDs; use its initial synchronization.
	task.wait(2)
	control:FireServer("ready")
end)
if not ok then control:FireServer("report", { ok = false, error = tostring(err) }) end
