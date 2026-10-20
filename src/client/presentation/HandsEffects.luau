--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local Shape = require(script.Parent.HandsShape)
local HandsEffects = {}
export type Casting = { begin: (number, number, Vector3?, number?) -> (), stop: (number) -> () }
type Entry = { event: any, root: BasePart, boundary: { BasePart }, cracks: { BasePart }, hands: { any },
	fires: { ParticleEmitter }, mist: ParticleEmitter, ground: BasePart, active: boolean }

local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, frame, color
	p.Anchored, p.Massless, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, true, false, false, false, false
	p.Material, p.Transparency, p.Parent = if neon then Enum.Material.Neon else Enum.Material.Slate, 1, parent
	return p
end
local function emitter(parent: Instance, smoke: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name, e.Texture = if smoke then "CurseGroundVapour" else "CurseFelFlame", if smoke then Style.textures.smoke else Style.textures.flame
	e.Color = ColorSequence.new(if smoke then Style.color else Style.flame)
	e.Rate, e.Speed, e.Lifetime = 0, NumberRange.new(0.2, 0.6), NumberRange.new(0.3, if smoke then 0.75 else 0.55)
	e.Size = if smoke then NumberSequence.new(1.6, 2.7) else NumberSequence.new(0.6, 0)
	e.Transparency = if smoke then NumberSequence.new(0.88, 1) else NumberSequence.new(0.35, 1)
	e.LightEmission, e.LightInfluence = if smoke then 0.1 else 0.6, if smoke then 0.7 else 0.1
	e.Acceleration, e.SpreadAngle = Vector3.new(0, if smoke then 0.5 else 1.8, 0), Vector2.new(35, 35)
	e.Parent = parent
	return e
end
local function cue(entry: Entry, kind: string)
    local sound = Instance.new("Sound")
    sound.Name, sound.SoundId = "HandsSound", if kind == "preparing" then Style.sounds.preparing else Style.sounds.hit
    sound.Volume, sound.RollOffMinDistance, sound.RollOffMaxDistance = if kind == "preparing" then 0.3 else 0.5, 8, 75
    sound.Parent = entry.root
    Debris:AddItem(sound, 2)
    sound:Play()
end
local function create(folder: Folder, event: any): Entry
	local radius: number = event.radius
	local position: Vector3 = event.position
	local root = part(folder, "DemonicHandsArea", Vector3.one * 0.1, CFrame.new(position), Style.shadow)
	Debris:AddItem(root, math.max(0.05, event.expiresAt - workspace:GetServerTimeNow()))
	local ground = part(root, "CursedGround", Vector3.new(0.025, radius * 2, radius * 2),
		CFrame.new(position + Vector3.new(0, 0.035, 0)) * CFrame.Angles(0, 0, math.pi / 2), Style.color)
	ground.Shape = Enum.PartType.Cylinder
	local boundary: { BasePart } = {}
	for index = 1, 28 do
		local angle = (index - 0.5) * math.pi * 2 / 28
		local offset = Vector3.new(math.sin(angle) * radius, 0.075, math.cos(angle) * radius)
		table.insert(boundary, part(root, "HandsDangerBoundary", Vector3.new(0.18, 0.035, radius * 2 * math.tan(math.pi / 28) + 0.02),
			CFrame.new(position + offset) * CFrame.Angles(0, angle + math.pi / 2, 0), Style.color, true))
	end
	local hands: { any } = {}
	local fires: { ParticleEmitter } = {}
	local cracks: { BasePart } = {}
	for index = 1, 4 do
		local angle = index * math.pi / 2 + 0.3
		local offset = Vector3.new(math.sin(angle), 0, math.cos(angle)) * radius * 0.55
		local center = position + offset
		local frame = CFrame.lookAt(center, position)
		table.insert(hands, Shape.new(root, frame, 0.95 + index * 0.08, index))
		local anchor = Instance.new("Attachment")
		anchor.Position, anchor.Parent = offset + Vector3.new(0, 0.1, 0), root
		table.insert(fires, emitter(anchor, false))
	end
	for index = 1, 8 do
		local angle = index * math.pi / 4 + event.areaId * 0.3
		local distance = radius * (if index % 2 == 0 then 0.38 else 0.65)
		local frame = CFrame.new(position + Vector3.new(math.sin(angle) * distance, 0.065, math.cos(angle) * distance)) * CFrame.Angles(0, angle + 0.3, 0)
		table.insert(cracks, part(root, "CurseGroundFracture", Vector3.new(0.1, 0.02, radius * 0.36), frame, Style.flame, true))
	end
	return {event = event, root = root, boundary = boundary, cracks = cracks, hands = hands, fires = fires,
		mist = emitter(root, true), ground = ground, active = false}
end

function HandsEffects.new(casting: Casting)
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "LocalHandsEffects", workspace
	local areas: { [number]: Entry } = {}
	local retired: { [number]: number } = {}
	local lastStep, stopped = 0, false
	local effects = {}
	local function remove(id: number, stopPose: boolean)
		local entry = areas[id]
		if not entry then return end
		if stopPose then casting.stop(entry.event.owner) end
		retired[id] = entry.event.expiresAt
		entry.root:Destroy()
		areas[id] = nil
	end
	local function update(entry: Entry, now: number)
		local event = entry.event
		local started = event.startedAt or event.launchAt - 0.8
		local progress = math.clamp((now - started) / math.max(0.01, event.launchAt - started), 0, 1)
		local age = math.max(0, now - event.launchAt)
		local fading = if entry.active then math.clamp((now - event.expiresAt + 0.35) / 0.35, 0, 1) else 0
		local pulse = 0.5 + math.sin(now * (if entry.active then 6 else 11)) * 0.5
		for _, edge in entry.boundary do
			edge.Color = if entry.active then Style.flame else Style.color
			edge.Transparency = (if entry.active then 0.24 else 0.12 + pulse * 0.2) + fading * 0.55
		end
		entry.ground.Transparency = (if entry.active then 0.89 else 0.95 - progress * 0.07) + fading * 0.1
		for index, crack in entry.cracks do
			crack.Color = if entry.active then Style.flame else Style.color
			crack.Transparency = (if entry.active then 0.37 + math.sin(now * 5 + index) * 0.08 else 0.8 - progress * 0.45) + fading * 0.5
		end
		for index, hand in entry.hands do
			local rise = if entry.active then math.clamp((age - (index - 1) * 0.035) / 0.24, 0, 1) else 0
			hand.step(now, rise * (1 - fading), if entry.active then fading else 1)
			entry.fires[index].Rate = if entry.active then 4 * (1 - fading) else 0
		end
		entry.mist.Rate = if entry.active then 2 * (1 - fading) else 0
	end
	function effects.event(event: any, quiet: boolean?)
		if stopped then return end
		local id: number = event.areaId
		if event.kind == "ended" then
			local entry = areas[id]
			retired[id] = event.expiresAt or (if entry then entry.event.expiresAt else workspace:GetServerTimeNow() + 5)
			local cancelled = event.reason == "dead" or event.reason == "left" or event.reason == "reset"
				or event.reason == "paused" or event.reason == "cancelled" or event.reason == "invalid_position"
			if entry then remove(id, not entry.active or cancelled) end
			return
		end
		if event.kind ~= "preparing" and event.kind ~= "active" then return end
		local now = workspace:GetServerTimeNow()
		if now >= event.expiresAt or retired[id] then return end
		local preparing = event.kind == "preparing"
		local previous = areas[id]
		if previous and previous.active and preparing then return end
		local beginPose = preparing and previous == nil
		local entry: Entry = previous or create(folder, event)
		areas[id] = entry
		local activated = event.kind == "active" and not entry.active
		-- Each authoritative phase replaces the timestamps used for interpolation.
		entry.event, entry.active = event, event.kind == "active"
		update(entry, now)
		if beginPose then
            if not quiet then cue(entry, "preparing") end
			local player = Players:GetPlayerByUserId(event.owner)
			local root = if player and player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
			local direction: Vector3? = nil
			if root and root:IsA("BasePart") then
				local delta = event.position - root.Position
				if delta.Magnitude > 0.01 then direction = delta.Unit end
			end
			casting.begin(event.owner, event.launchAt, direction, event.startedAt)
		end
		if activated and not quiet then
            cue(entry, "active")
            for _, fire in entry.fires do fire:Emit(4) end
        end
	end
	function effects.sync(events: { any })
		if stopped then return end
		local keep: { [number]: boolean } = {}
		for _, event in events do keep[event.areaId] = true; effects.event(event, true) end
		for id, entry in areas do if not keep[id] then remove(id, not entry.active) end end
	end
	function effects.step(now: number)
		if stopped then return end
		lastStep = now
		for id, expires in retired do if now >= expires then retired[id] = nil end end
		for id, entry in areas do
			if now >= entry.event.expiresAt then remove(id, not entry.active) else update(entry, now) end
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
		for id in areas do remove(id, true) end
		folder:Destroy()
	end
	return effects
end
return HandsEffects
