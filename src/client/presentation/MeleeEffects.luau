--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Pose = require(script.Parent.MeleePose)
local Impact = require(script.Parent.MeleeImpact)
local MeleeEffects = {}
local SILVER, RED = Color3.fromRGB(218, 228, 231), Color3.fromRGB(157, 49, 47)
type Swing = { event: any, root: BasePart?, beams: { Beam }, struck: boolean, played: boolean, scheduled: boolean, trail: Trail?, nodes: { Attachment }, brace: Sound?, glint: Beam? }

function MeleeEffects.new(sharedPose: any?, style: string?)
	local heavy = style == "heavy"
	local kind = if heavy then "heavy" else "melee"
	local strokeDuration = if heavy then 0.34 else 0.25
	local trailLead, trailTail = if heavy then 0.11 else 0.08, if heavy then 0.13 else 0.1
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = if heavy then "LocalHeavyEffects" else "LocalMeleeEffects", workspace
	local swings: { [number]: Swing } = {}
	local retired: { [number]: number } = {}
	local pose = sharedPose or Pose.new()
	local ownsPose = sharedPose == nil
	local impact = Impact.new(folder, style)
	local stopped, lastStep = false, 0
	local effects = {}
	local function body(owner: number): BasePart?
		local player = Players:GetPlayerByUserId(owner)
		local root = if player and player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
		return if root and root:IsA("BasePart") then root else nil
	end
	local function rootPart(frame: CFrame): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = if heavy then "WarriorHeavySwing" else "WarriorSwing", Vector3.one * 0.1, frame
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
			local radius = 7
			node.Position, node.Parent = Vector3.new(math.sin(angle) * radius, math.sin(angle) * (if heavy then 0.9 else 0.55), -math.cos(angle) * radius), root
			if previous then
				local beam = Instance.new("Beam")
				beam.Name, beam.Attachment0, beam.Attachment1 = if heavy then "HeavySwordCrescent" else "SwordCrescent", previous, node
				beam.Color = ColorSequence.new(SILVER, if heavy then Color3.fromRGB(235, 176, 104) else RED)
				beam.Width0, beam.Width1 = if heavy then 0.9 else 0.45, if heavy then 0.32 else 0.18
				beam.FaceCamera, beam.Segments, beam.LightEmission = true, 2, 0.35
				beam.Transparency, beam.Parent = NumberSequence.new(0.18, 0.65), root
				table.insert(entry.beams, beam)
			end
			previous = node
		end
		if not quiet then
			local sound = Instance.new("Sound")
			sound.Name, sound.SoundId = if heavy then "HeavySwordWhoosh" else "SwordWhoosh", "rbxasset://sounds/warrior-v1/slash.wav"
			sound.Volume, sound.PlaybackSpeed = if heavy then 0.55 else 0.45, if heavy then 0.78 else 1
			sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.Parent = 8, 75, root
			sound:Play()
		end
		local flash = Instance.new("Part")
		flash.Name = if heavy then "HeavySwordEdgeGlint" else "SwordEdgeGlint"
		flash.Size, flash.CFrame = if heavy then Vector3.new(0.18, 0.18, 2) else Vector3.new(0.12, 0.12, 1.25), frame * CFrame.new(0, 0, if heavy then -5.6 else -5)
		flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch, flash.CastShadow = true, false, false, false, false
		flash.Material, flash.Color, flash.Parent = Enum.Material.Neon, SILVER, root
		Debris:AddItem(flash, 0.12)
	end
	local function attachTrail(entry: Swing)
        local player = Players:GetPlayerByUserId(entry.event.owner)
        local character = if player then player.Character else nil
        local armour = if character then character:FindFirstChild("WarriorArmour") else nil
        local blade = if armour then armour:FindFirstChild("WarriorSwordBlade") else nil
        if not blade or not blade:IsA("BasePart") then return end
        local low, high = Instance.new("Attachment"), Instance.new("Attachment")
        low.Name, low.Position, low.Parent = if heavy then "HeavyTrailHeel" else "SwordTrailHeel", Vector3.new(0, -1.25, 0), blade
        high.Name, high.Position, high.Parent = if heavy then "HeavyTrailTip" else "SwordTrailTip", Vector3.new(0, 1.45, 0), blade
        local trail = Instance.new("Trail")
        trail.Name, trail.Attachment0, trail.Attachment1 = if heavy then "HeavySwordEdge" else "MovingSwordEdge", low, high
        trail.Color, trail.Lifetime, trail.MinLength = ColorSequence.new(SILVER, RED), if heavy then 0.2 else 0.13, 0.03
        trail.Transparency = NumberSequence.new(0.3, 1)
        trail.WidthScale = NumberSequence.new(if heavy then 1 else 0.65, 0)
        trail.LightEmission, trail.FaceCamera, trail.Enabled, trail.Parent = 0.35, true, false, blade
        entry.trail, entry.nodes = trail, {low, high}
        if heavy then
            local glint = Instance.new("Beam")
            glint.Name, glint.Attachment0, glint.Attachment1 = "HeavyBladePreparation", low, high
            glint.Color, glint.Width0, glint.Width1 = ColorSequence.new(SILVER), 0.1, 0.035
            glint.Transparency, glint.LightEmission, glint.FaceCamera, glint.Parent = NumberSequence.new(0.7), 0.65, true, blade
            entry.glint = glint
        end
    end
    function effects.preview(requestId: number, life: number, direction: Vector3): boolean
        return pose.preview(Players.LocalPlayer.UserId, kind, requestId, life, direction)
    end
    function effects.cancelPreview(requestId: number?) pose.cancelPreview(Players.LocalPlayer.UserId, kind, requestId) end
    local function remove(id: number, cancel: boolean)
		local entry = swings[id]
		if not entry then return end
		if cancel then pose.stop(entry.event.owner, kind, entry.event.swingId); impact.cancel(entry.event.owner, id) end
		if entry.root then entry.root:Destroy() end
        if entry.trail then entry.trail:Destroy() end
        if entry.brace then entry.brace:Destroy() end
        if entry.glint then entry.glint:Destroy() end
        for _, node in entry.nodes do node:Destroy() end
		retired[id] = entry.event.expiresAt
		swings[id] = nil
	end
	function effects.event(event: any, quiet: boolean?)
		if stopped then return end
		if (heavy and event.style ~= "heavy") or (not heavy and event.style == "heavy") then return end
		local id: number = event.swingId
		if event.kind == "contact" then
			local current = swings[id]
			if current and current.event.owner == event.owner and current.event.life == event.life then impact.hit(event) end
			return
		end
		if event.kind == "ended" then
			local cancelled = event.reason ~= "expired" and event.reason ~= "finished"
			if swings[id] and swings[id].event.owner == event.owner and swings[id].event.life == event.life then remove(id, cancelled)
			elseif not swings[id] then retired[id] = event.expiresAt or workspace:GetServerTimeNow() + 1 end
			return
		end
		if event.kind ~= "preparing" and event.kind ~= "struck" then return end
		local now = workspace:GetServerTimeNow()
		if now >= event.expiresAt or retired[id] then return end
		local previous = swings[id]
		local scheduled = event.kind == "preparing" and not quiet
		if previous and previous.struck and event.kind == "preparing" then return end
		local entry: Swing = previous or {event = event, root = nil, beams = {}, struck = false, played = false,
            scheduled = scheduled, trail = nil, nodes = {}, brace = nil, glint = nil}
		if not previous then
			swings[id] = entry
			if heavy then pose.beginHeavy(event.owner, event.hitAt, event.startedAt, event.expiresAt, event.direction, event.swingId, event.requestId)
			else pose.begin(event.owner, event.hitAt, event.startedAt, event.expiresAt, event.direction, event.swingId, event.requestId) end
			if scheduled then
				local root = body(event.owner)
				if root then
					local brace = Instance.new("Sound")
					brace.Name, brace.SoundId, brace.Volume, brace.Parent = if heavy then "WarriorHeavyBrace" else "WarriorSwordBrace", "rbxasset://sounds/warrior-v1/brace.wav", if heavy then 0.36 else 0.3, root
					brace.PlaybackSpeed = if heavy then 0.7 else 1
					brace.RollOffMinDistance, brace.RollOffMaxDistance = 6, 45
					entry.brace = brace
					brace:Play(); Debris:AddItem(brace, if heavy then 0.8 else 0.4)
				end
			end
		end
		entry.event = event
		if event.kind == "struck" and not entry.struck then
			entry.struck = true
			-- A restored snapshot can recover the body pose, but never replays an old strike burst.
			if not quiet and not entry.played then
                entry.played = true
                if now - event.hitAt < 0.25 then strike(entry, false) end
            end
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
		impact.step(now)
		for id, expires in retired do if now >= expires then retired[id] = nil end end
		for id, entry in swings do
			if heavy then
				local player = Players:GetPlayerByUserId(entry.event.owner)
				local character = if player then player.Character else nil
				local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
				local root = body(entry.event.owner)
				if not character or character:GetAttribute("CombatLife") ~= entry.event.life or character:GetAttribute("CombatClass") ~= "warrior"
					or not humanoid or humanoid.Health <= 0 or not root or root.Anchored then remove(id, true); continue end
			end
			if now >= entry.event.expiresAt then remove(id, false); continue end
			local age = now - entry.event.hitAt
            if not entry.played and entry.scheduled and age >= 0 then
                entry.played = true
                if age < 0.16 then strike(entry, false) end
            end
            if not entry.trail and age <= trailTail then attachTrail(entry) end
            if entry.trail then entry.trail.Enabled = age >= -trailLead and age <= trailTail end
            if entry.glint then
                entry.glint.Enabled = age < 0
                entry.glint.Transparency = NumberSequence.new(0.8 - math.clamp(1 + age / 0.65, 0, 1) * 0.5)
            end
			if entry.root then
				if age >= strokeDuration then entry.root:Destroy(); entry.root = nil; table.clear(entry.beams)
				else
					for index, beam in entry.beams do
						local reveal = age >= (index - 1) * 0.009
						beam.Enabled = reveal
						beam.Transparency = NumberSequence.new(math.clamp(0.15 + age / strokeDuration, 0, 1), math.clamp(0.55 + age / strokeDuration, 0, 1))
					end
				end
			end
		end
	end
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		-- Stroke emission follows simulation time even when an inactive viewport renders slowly.
		for _, entry in swings do
			if entry.trail then
				local age = now - entry.event.hitAt
				entry.trail.Enabled = age >= -trailLead and age <= trailTail
			end
		end
		if now - lastStep >= 0.1 then effects.step(now) end
	end)
	function effects.destroy()
		if stopped then return end
		stopped = true
		heartbeat:Disconnect()
		for id in swings do remove(id, true) end
		impact.destroy()
		if ownsPose then pose.destroy() end
		folder:Destroy()
	end
	return effects
end
return MeleeEffects
