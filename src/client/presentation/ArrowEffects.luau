--!strict
local Players = game:GetService("Players")
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local CastPose = require(script.Parent.CastPose)
local ArrowEffects = {}

function ArrowEffects.new()
	local folder = Instance.new("Folder")
	folder.Name = "LocalArrowEffects"
	folder.Parent = workspace
	local active: { [number]: any } = {}
	local bursts: { any } = {}
	local sounds: { any } = {}
	local pose = CastPose.new()
	local effects = {}
	local function part(size: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Size, p.Color = size, color
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Parent = folder
		return p
	end
	local function cue(kind: string, position: Vector3)
		local id = (Style.sounds :: { [string]: string })[kind]
		if not id or id == "" then return end
		local anchor = part(Vector3.one * 0.1, Style.color)
		anchor.Transparency, anchor.Position = 1, position
		local sound = Instance.new("Sound")
		sound.SoundId, sound.Volume = id, 0.45
		sound.RollOffMaxDistance = 100
		sound.Parent = anchor
		sound:Play()
		table.insert(sounds, { part = anchor, expires = workspace:GetServerTimeNow() + 3 })
	end
	local function remove(id: number)
		local entry = active[id]
		if entry then entry.part:Destroy(); active[id] = nil end
	end
	function effects.event(event: any, quiet: boolean?)
		local id = event.castId
		if event.kind == "ended" then
			remove(id)
			if event.reason == "dead" or event.reason == "left" or event.reason == "reset" or event.reason == "invalid_position" or event.reason == "paused" then
				pose.stop(event.owner)
			end -- A nearby hit must not snap the arm out of its release/recovery blend.
			if event.position and (event.reason == "hit" or event.reason == "teleported") and not quiet then
				local ring = part(Vector3.one, Style.color)
				ring.Shape = Enum.PartType.Ball
				ring.Position = event.position
				table.insert(bursts, { part = ring, at = workspace:GetServerTimeNow(), teleport = event.reason == "teleported" })
				cue(event.reason, event.position)
			end
			return
		end
		local flying = event.kind == "launched" or event.kind == "flying"
		local old = active[id]
		if old and old.flying == flying then return end
		remove(id)
		local p = part(if flying then Vector3.new(0.65, 0.65, 6) else Vector3.one, Style.core)
		p.Name = if flying then "DemonicArrow" else "ArrowCharge"
		if not flying then p.Shape = Enum.PartType.Ball end
		local light = Instance.new("PointLight")
		light.Color, light.Brightness, light.Range = Style.color, 1.5, 13
		light.Parent = p
		if flying then
			local a, b = Instance.new("Attachment"), Instance.new("Attachment")
			a.Position, b.Position = Vector3.new(-0.55, 0, 2.5), Vector3.new(0.55, 0, 2.5)
			a.Parent, b.Parent = p, p
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a, b
			trail.Color = ColorSequence.new(Style.color)
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Lifetime, trail.FaceCamera = 0.18, true
			trail.Parent = p
		end
		active[id] = { part = p, event = event, flying = flying }
		if not quiet then
			if not flying then pose.begin(event.owner, event.launchAt) end
			local soundPosition = event.position
			if not soundPosition then
				local owner = Players:GetPlayerByUserId(event.owner)
				local root = if owner and owner.Character then owner.Character:FindFirstChild("HumanoidRootPart") else nil
				if root and root:IsA("BasePart") then soundPosition = root.Position end
			end
			if soundPosition then cue(event.kind, soundPosition) end
		end
	end
	function effects.sync(events: { any })
		local keep = {}
		for _, event in events do keep[event.castId] = true; effects.event(event, true) end
		for id, entry in active do
			if not keep[id] then pose.stop(entry.event.owner); remove(id) end
		end
	end
	function effects.step(now: number)
		pose.step(now)
		for id, entry in active do
			local e = entry.event
			if now >= e.expiresAt then pose.stop(e.owner); remove(id); continue end
			if entry.flying then
				local baseTime = e.sampledAt or e.launchAt
				local p = e.position + e.direction * e.speed * math.max(0, now - baseTime)
				entry.part.CFrame = CFrame.lookAt(p, p + e.direction)
			else
				local player = Players:GetPlayerByUserId(e.owner)
				local character = if player then player.Character else nil
				local hand = if character then character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") else nil
				if hand and hand:IsA("BasePart") then
					entry.part.Position = hand.Position
					entry.part.Size = Vector3.one * (0.6 + 0.5 * math.clamp(1 - (e.launchAt - now) / 0.32, 0, 1))
				else entry.part.Transparency = 1 end
			end
		end
		for i = #bursts, 1, -1 do
			local burst = bursts[i]
			local age = (now - burst.at) / 0.3
			if age >= 1 then burst.part:Destroy(); table.remove(bursts, i)
			else burst.part.Size = Vector3.one * (1 + age * (if burst.teleport then 7 else 4)); burst.part.Transparency = age end
		end
		for i = #sounds, 1, -1 do
			if now >= sounds[i].expires then sounds[i].part:Destroy(); table.remove(sounds, i) end
		end
	end
	function effects.destroy()
		pose.destroy()
		table.clear(active); table.clear(bursts); table.clear(sounds)
		folder:Destroy()
	end
	return effects
end
return ArrowEffects
