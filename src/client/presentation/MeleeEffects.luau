--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Pose = require(script.Parent.MeleePose)
local MeleeEffects = {}
local SILVER, RED = Color3.fromRGB(218, 228, 231), Color3.fromRGB(157, 49, 47)
type Swing = { event: any, root: BasePart?, beams: { Beam }, struck: boolean }

function MeleeEffects.new()
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "LocalMeleeEffects", workspace
	local swings: { [number]: Swing } = {}
	local retired: { [number]: number } = {}
	local pose = Pose.new()
	local stopped, lastStep = false, 0
	local effects = {}
	local function body(owner: number): BasePart?
		local player = Players:GetPlayerByUserId(owner)
		local root = if player and player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
		return if root and root:IsA("BasePart") then root else nil
	end
	local function rootPart(frame: CFrame): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = "WarriorSwing", Vector3.one * 0.1, frame
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Transparency = true, false, false, false, false, 1
		p.Parent = folder
		Debris:AddItem(p, 0.5)
		return p
	end
	local function strike(entry: Swing, quiet: boolean?)
		local event = entry.event
		local owner = body(event.owner)
		local position = if owner then owner.Position else event.position
		if not position then return end
		local direction = event.direction * Vector3.new(1, 0, 1)
		if direction.Magnitude < 0.01 then return end
		direction = direction.Unit
		local frame = CFrame.lookAt(position + Vector3.new(0, 0.8, 0), position + Vector3.new(0, 0.8, 0) + direction)
		local root = rootPart(frame)
		entry.root = root
		local previous: Attachment? = nil
		for index = 0, 9 do
			local angle = math.rad(-50 + index * 100 / 9)
			local node = Instance.new("Attachment")
			node.Position, node.Parent = Vector3.new(math.sin(angle) * 5.5, math.sin(angle) * 0.55, -math.cos(angle) * 5.5), root
			if previous then
				local beam = Instance.new("Beam")
				beam.Name, beam.Attachment0, beam.Attachment1 = "SwordCrescent", previous, node
				beam.Color, beam.Width0, beam.Width1 = ColorSequence.new(SILVER, RED), 0.45, 0.18
				beam.FaceCamera, beam.Segments, beam.LightEmission = true, 2, 0.35
				beam.Transparency, beam.Parent = NumberSequence.new(0.18, 0.65), root
				table.insert(entry.beams, beam)
			end
			previous = node
		end
		if not quiet then
			local sound = Instance.new("Sound")
			sound.Name, sound.SoundId, sound.Volume, sound.PlaybackSpeed = "SwordWhoosh", "rbxasset://sounds/warlock-art-v1/launch.wav", 0.34, 0.82
			sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.Parent = 8, 75, root
			sound:Play()
		end
		local flash = Instance.new("Part")
		flash.Name, flash.Size, flash.CFrame = "SwordContactGlint", Vector3.new(0.12, 0.12, 1.25), frame * CFrame.new(0, 0, -5)
		flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch, flash.CastShadow = true, false, false, false, false
		flash.Material, flash.Color, flash.Parent = Enum.Material.Neon, SILVER, root
		Debris:AddItem(flash, 0.12)
	end
	local function remove(id: number, cancel: boolean)
		local entry = swings[id]
		if not entry then return end
		if cancel then pose.stop(entry.event.owner) end
		if entry.root then entry.root:Destroy() end
		retired[id] = entry.event.expiresAt
		swings[id] = nil
	end
	function effects.event(event: any, quiet: boolean?)
		if stopped then return end
		local id: number = event.swingId
		if event.kind == "ended" then
			local cancelled = event.reason ~= "expired" and event.reason ~= "finished"
			if swings[id] then remove(id, cancelled) else retired[id] = event.expiresAt or workspace:GetServerTimeNow() + 1 end
			return
		end
		if event.kind ~= "preparing" and event.kind ~= "struck" then return end
		local now = workspace:GetServerTimeNow()
		if now >= event.expiresAt or retired[id] then return end
		local previous = swings[id]
		if previous and previous.struck and event.kind == "preparing" then return end
		local entry: Swing = previous or {event = event, root = nil, beams = {}, struck = false}
		if not previous then
			swings[id] = entry
			pose.begin(event.owner, event.hitAt, event.startedAt, event.expiresAt)
		end
		entry.event = event
		if event.kind == "struck" and not entry.struck then
			entry.struck = true
			-- A restored snapshot can recover the body pose, but never replays an old strike burst.
			if not quiet then strike(entry, false) end
		end
	end
	function effects.sync(events: { any })
		if stopped then return end
		local keep: { [number]: boolean } = {}
		for _, event in events do keep[event.swingId] = true; effects.event(event, true) end
		for id in swings do if not keep[id] then remove(id, true) end end
	end
	function effects.step(now: number)
		if stopped then return end
		lastStep = now
		pose.step(now)
		for id, expires in retired do if now >= expires then retired[id] = nil end end
		for id, entry in swings do
			if now >= entry.event.expiresAt then remove(id, false); continue end
			local age = now - entry.event.hitAt
			if entry.root then
				if age >= 0.25 then entry.root:Destroy(); entry.root = nil; table.clear(entry.beams)
				else
					for index, beam in entry.beams do
						local reveal = age >= (index - 1) * 0.009
						beam.Enabled = reveal
						beam.Transparency = NumberSequence.new(math.clamp(0.15 + age / 0.25, 0, 1), math.clamp(0.55 + age / 0.25, 0, 1))
					end
				end
			end
		end
	end
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now - lastStep >= 0.1 then effects.step(now) end
	end)
	function effects.destroy()
		if stopped then return end
		stopped = true
		heartbeat:Disconnect()
		for id in swings do remove(id, true) end
		pose.destroy(); folder:Destroy()
	end
	return effects
end
return MeleeEffects
