--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Rupture = require(script.Parent.DashRupture)
local Pose = require(script.Parent.MeleePose)
local DashEffects = {}
local SILVER = Color3.fromRGB(208, 226, 237)
type Entry = { event: any, character: Model, humanoid: Humanoid, root: BasePart, nodes: { Attachment },
	trails: { Trail }, sound: Sound?, light: PointLight, peak: number, received: number, emitUntil: number, removeAt: number }
type Ground = { effect: any, event: any, character: Model, humanoid: Humanoid, root: BasePart, started: number }

function DashEffects.new(sharedPose: any?)
	local pose = sharedPose or Pose.new()
	local ownsPose = sharedPose == nil
	local entries: { [number]: Entry } = {}
	local grounds: { [number]: Ground } = {}
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "LocalDashEffects", workspace
	local retired: { [number]: number } = {}
	local stopped, lastStep = false, 0
	local previewId: number? = nil
	local effects = {}
	function effects.preview(requestId: number, life: number, direction: Vector3): boolean
		if stopped then return false end
		local owner = Players.LocalPlayer.UserId
		if not pose.previewDash(owner, requestId, life, direction) then return false end
		previewId = requestId
		return true
	end
	function effects.cancelPreview(requestId: number?)
		pose.cancelPreview(Players.LocalPlayer.UserId, "dash", requestId)
		if requestId == nil or previewId == requestId then previewId = nil end
	end
	local function clearGround(id: number)
		local ground = grounds[id]
		if ground then ground.effect.destroy(); grounds[id] = nil end
	end
	local function remove(id: number, cancel: boolean?)
		local ground = grounds[id]
		if cancel ~= false then clearGround(id)
		elseif ground then ground.effect.finish(workspace:GetServerTimeNow()) end
		local entry = entries[id]
		if not entry then return end
		if cancel ~= false then pose.stop(entry.event.owner, "dash", id) end
		for _, trail in entry.trails do trail:Destroy() end
		for _, node in entry.nodes do node:Destroy() end
		if entry.sound then entry.sound:Destroy() end
		entry.light:Destroy()
		entries[id] = nil
		retired[id] = workspace:GetServerTimeNow() + 10
	end
	function effects.event(event: any, quiet: boolean?)
		if stopped then return end
		local id: number = event.dashId
		local now = workspace:GetServerTimeNow()
		if event.kind == "ended" then
			local entry = entries[id]
			if event.reason ~= "expired" and event.reason ~= "finished" then remove(id)
			elseif entry then
				entry.emitUntil = math.min(entry.emitUntil, now)
				entry.removeAt = math.min(entry.removeAt, now + 0.18)
				if grounds[id] then grounds[id].effect.finish(now) end
			end
			retired[id] = now + 10
			return
		end
		if event.kind ~= "started" or retired[id] or entries[id] then return end
		-- Restoring a snapshot never replays a completed dash or its launch sound.
		local matchingPreview = previewId ~= nil and event.requestId == previewId and event.owner == Players.LocalPlayer.UserId
		if quiet and now >= event.expiresAt and not matchingPreview then return end
		if not quiet and now - event.expiresAt > 0.35 then return end
		local player = Players:GetPlayerByUserId(event.owner)
		local character = if player then player.Character else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
		if character:GetAttribute("CombatClass") ~= "warrior" or character:GetAttribute("CombatLife") ~= event.life then return end
		for oldId, old in entries do
			if old.event.owner == event.owner then remove(oldId) end
		end
		local count, oldestId, oldestAt = 0, nil, math.huge
		for oldId, old in grounds do
			if old.event.owner == event.owner then clearGround(oldId)
			else
				count += 1
				if old.started < oldestAt then oldestId, oldestAt = oldId, old.started end
			end
		end
		if count >= 6 and oldestId then clearGround(oldestId) end
		grounds[id] = { effect = Rupture.new(folder, character, root, event.direction, id, quiet), event = event,
			character = character, humanoid = humanoid, root = root, started = now }
		if not quiet or matchingPreview then pose.beginDash(event.owner, event.duration or 0.28, event.direction, id, event.requestId) end
		if matchingPreview then previewId = nil end
		-- Native trails follow replicated movement rather than the server's old start position.
		local nodes: { Attachment }, trails: { Trail } = {}, {}
		for _, side in { -1, 1 } do
			local low, high = Instance.new("Attachment"), Instance.new("Attachment")
			low.Name, low.Position, low.Parent = "DashTrailLow", Vector3.new(side * 1.0, -0.6, 0.3), root
			high.Name, high.Position, high.Parent = "DashTrailHigh", Vector3.new(side * 1.0, 1.0, 0.3), root
			local trail = Instance.new("Trail")
			trail.Name, trail.Attachment0, trail.Attachment1 = "WarriorDashTrail", low, high
			trail.Color, trail.Lifetime, trail.MinLength = ColorSequence.new(SILVER), 0.17, 0.08
			trail.Transparency = NumberSequence.new(0.24, 1)
			trail.WidthScale = NumberSequence.new(0.65, 0)
			trail.LightEmission, trail.FaceCamera, trail.Parent = 0.35, true, root
			table.insert(nodes, low); table.insert(nodes, high); table.insert(trails, trail)
		end
		local light = Instance.new("PointLight")
		light.Name, light.Color, light.Range, light.Brightness, light.Parent = "DashLaunchGlint", SILVER, 7, if quiet then 0 else 0.8, root
		local sound: Sound? = nil
		if not quiet then
			local whoosh = Instance.new("Sound")
			whoosh.Name, whoosh.SoundId, whoosh.Volume, whoosh.PlaybackSpeed = "WarriorDashWhoosh", "rbxasset://sounds/warrior-v1/rupture.wav", 0.36, 1
			whoosh.RollOffMinDistance, whoosh.RollOffMaxDistance, whoosh.Parent = 8, 65, root
			whoosh:Play(); sound = whoosh
		end
		-- With latency the live movement can arrive after the absolute server expiry.
		-- A short minimum emission window avoids clipping it; no movement is predicted here.
		local emitUntil = if quiet then event.expiresAt else math.max(event.expiresAt, now + math.clamp(event.duration or 0.28, 0.18, 0.28))
		entries[id] = { event = event, character = character, humanoid = humanoid, root = root, nodes = nodes,
			trails = trails, sound = sound, light = light, peak = if quiet then 0 else 0.8,
			received = now, emitUntil = emitUntil, removeAt = emitUntil + 0.18 }
	end
	function effects.sync(events: { any })
		if stopped then return end
		local keep: { [number]: boolean } = {}
		for _, event in events do keep[event.dashId] = true; effects.event(event, true) end
		for id, entry in entries do
			if not keep[id] then
				-- A normal expiry may already be in flight. Let its native trail fade briefly.
				local now = workspace:GetServerTimeNow()
				if now >= entry.event.expiresAt then
					entry.emitUntil, entry.removeAt = math.min(entry.emitUntil, now), math.min(entry.removeAt, now + 0.18)
				else remove(id) end
			end
		end
	end
	function effects.step(now: number)
		if stopped then return end
		lastStep = now
		pose.step(now)
		for id, expires in retired do if now >= expires then retired[id] = nil end end
		for id, entry in entries do
			local player = Players:GetPlayerByUserId(entry.event.owner)
			local invalid = not player or player.Character ~= entry.character or not entry.root.Parent or entry.humanoid.Health <= 0
				or entry.character:GetAttribute("CombatClass") ~= "warrior" or entry.character:GetAttribute("CombatLife") ~= entry.event.life or entry.root.Anchored
			if invalid then remove(id); continue end
			if now >= entry.removeAt then remove(id, false); continue end
			for _, trail in entry.trails do trail.Enabled = now < entry.emitUntil end
			entry.light.Brightness = math.max(0, entry.peak * (1 - (now - entry.received) / 0.1))
		end
		for id, ground in grounds do
			local player = Players:GetPlayerByUserId(ground.event.owner)
			if not player or player.Character ~= ground.character or not ground.root.Parent or ground.humanoid.Health <= 0
				or ground.character:GetAttribute("CombatClass") ~= "warrior" or ground.character:GetAttribute("CombatLife") ~= ground.event.life or ground.root.Anchored then
				clearGround(id); continue
			end
			local entry = entries[id]
			if not ground.effect.step(now, entry ~= nil and now < entry.emitUntil) then grounds[id] = nil end
		end
	end
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now - lastStep >= 0.05 then effects.step(now) end
	end)
	function effects.destroy()
		if stopped then return end
		effects.cancelPreview()
		stopped = true
		heartbeat:Disconnect()
		for id in entries do remove(id) end
		for id in grounds do clearGround(id) end
		folder:Destroy()
		if ownsPose then pose.destroy() end
	end
	return effects
end
return DashEffects
