--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local CastPose = require(script.Parent.CastPose)
local WarlockAppearance = require(script.Parent.WarlockAppearance)
local ChaosArrow = require(script.Parent.ChaosArrow)
local ChaosImpact = require(script.Parent.ChaosImpact)
local Matter = require(script.Parent.ChaosMatter)
local ArrowEffects = {}

function ArrowEffects.new(sharedPose: any?)
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "LocalArrowEffects", workspace
	local active: { [number]: any } = {}
	local pending: { [number]: any } = {}
	local ownerLives: { [number]: number } = {}
	local retired: { [number]: number } = {}
	local casts: { [number]: any } = {}
	local bursts: { any } = {}
	local sounds: { any } = {}
	local pose, appearance = sharedPose or CastPose.new(), WarlockAppearance.new()
	local lastStep = 0
	local stopped = false
	local effects = {}
	local function cue(kind: string, position: Vector3, owner: number)
		local id = (Style.sounds :: { [string]: string })[kind]
		if not id or id == "" then return end
		local anchor = Matter.part(folder, "ArrowSound", Vector3.one * 0.1, Style.color)
		anchor.Transparency, anchor.Position = 1, position
		game:GetService("Debris"):AddItem(anchor, 3)
		local sound = Instance.new("Sound")
		sound.SoundId, sound.Volume = id, if kind == "hit" then 0.7 elseif kind == "preparing" then 0.38 else 0.5
		sound.RollOffMinDistance, sound.RollOffMaxDistance = 8, 100
		sound.Parent = anchor
		sound:Play()
		table.insert(sounds, {part = anchor, owner = owner, kind = kind, expires = workspace:GetServerTimeNow() + 3})
	end
	local function stop(owner: number, expectedLife: number?, expectedId: number?, requestId: number?)
		local current = casts[owner]
		if expectedLife ~= nil and (not current or current.life ~= expectedLife
			or (current.castId ~= expectedId and not (current.preview and requestId ~= nil and current.requestId == requestId))) then return end
		pose.stop(owner)
		appearance.stop(owner)
		casts[owner] = nil
		for i = #sounds, 1, -1 do
			if sounds[i].owner == owner and sounds[i].kind == "preparing" then
				sounds[i].part:Destroy(); table.remove(sounds, i)
			end
		end
	end
	local function remove(id: number)
		local entry = active[id]
		if entry then entry.visual.destroy(); active[id] = nil end
	end
	-- Do not attach a future-life event to the previous rig. Its visuals wait for
	-- matching replicated life, body and class, bounded by both time and count.
	local function body(event: any): (Model?, string)
		local player = Players:GetPlayerByUserId(event.owner)
		local character = if player then player.Character else nil
		local life = if character then character:GetAttribute("CombatLife") else nil
		if event.life < (ownerLives[event.owner] or 0) or (type(life) == "number" and event.life < life) then return nil, "stale" end
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local human = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not character or not character.Parent or life ~= event.life or character:GetAttribute("CombatClass") ~= "warlock"
			or not root or not root:IsA("BasePart") or not human or human.Health <= 0 or root.Anchored then return nil, "waiting" end
		return character, "ready"
	end
	local function deferVisual(event: any, quiet: boolean?)
		local now = workspace:GetServerTimeNow()
		local old = pending[event.castId]
		if old and old.event.redirected and not event.redirected then return end
		if old and (old.event.kind == "launched" or old.event.kind == "flying" or old.event.kind == "redirected") and event.kind == "preparing" then return end
		local count, oldestId, oldestAt = 0, nil, math.huge
		for id, entry in pending do count += 1; if entry.at < oldestAt then oldestId, oldestAt = id, entry.at end end
		if not old and count >= 24 and oldestId then pending[oldestId] = nil end
		pending[event.castId] = { event = event, quiet = quiet, at = if old then old.at else now,
			untilAt = math.min(event.expiresAt, if old then old.untilAt else now + 2) }
	end
    function effects.prepare(owner: number, launchAt: number, direction: Vector3?, startedAt: number?, requestId: number?, life: number?, castId: number?)
		if stopped then return end
		local player = Players:GetPlayerByUserId(owner)
		local character = if player then player.Character else nil
        casts[owner] = { life = life or (if character then character:GetAttribute("CombatLife") else nil), castId = castId,
			requestId = requestId, character = character, preview = false }
        pose.begin(owner, launchAt, direction, startedAt, requestId)
        appearance.cast(owner, launchAt, startedAt)
    end
    function effects.stopCast(owner: number) stop(owner) end
    function effects.preview(requestId: number, life: number, direction: Vector3): boolean
        if stopped or not pose.preview(Players.LocalPlayer.UserId, requestId, life, direction) then return false end
		casts[Players.LocalPlayer.UserId] = { life = life, requestId = requestId, preview = true, character = Players.LocalPlayer.Character }
		return true
    end
    function effects.cancelPreview(requestId: number?)
		pose.cancelPreview(Players.LocalPlayer.UserId, requestId)
		local current = casts[Players.LocalPlayer.UserId]
		if current and current.preview and (requestId == nil or current.requestId == requestId) then casts[Players.LocalPlayer.UserId] = nil end
	end
	function effects.event(event: any, quiet: boolean?)
		if stopped then return end
		local id = event.castId
		local now = workspace:GetServerTimeNow()
		ownerLives[event.owner] = math.max(ownerLives[event.owner] or 0, event.life)
		if event.kind == "ended" then
			pending[id], retired[id] = nil, now + 10
			remove(id)
			if event.reason == "dead" or event.reason == "left" or event.reason == "reset" or event.reason == "invalid_position" or event.reason == "paused" then
				stop(event.owner, event.life, id, event.requestId)
			end
			local _, status = body(event)
			if status ~= "stale" and event.position and (event.reason == "hit" or event.reason == "teleported") and not quiet then
				table.insert(bursts, ChaosImpact.new(folder, event.position, event.reason == "teleported", id, workspace:GetServerTimeNow()))
				cue(event.reason, event.position, event.owner)
			end
			return
		end
		if retired[id] or now >= event.expiresAt then return end
		local character, status = body(event)
		if status == "stale" then pending[id] = nil; return end
		if not character then deferVisual(event, quiet); return end
		pending[id] = nil
		local flying = event.kind == "launched" or event.kind == "flying" or event.kind == "redirected"
		local old = active[id]
		if old and old.flying and not flying then return end
		if old and old.event.redirected and not event.redirected then return end
		if old and old.flying == flying and old.event.redirected == event.redirected then return end
		remove(id)
		local visual = ChaosArrow.new(folder, event, flying)
		active[id] = {visual = visual, event = event, flying = flying, character = character}
		visual.step(workspace:GetServerTimeNow())
		if not flying then
			effects.prepare(event.owner, event.launchAt, event.direction, event.startedAt, event.requestId, event.life, id)
		end
		if not quiet then
			local position = event.position
			if not position then
				local player = Players:GetPlayerByUserId(event.owner)
				local root = if player and player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
				if root and root:IsA("BasePart") then position = root.Position end
			end
			if position then cue(event.kind, position, event.owner) end
		end
	end
	function effects.sync(events: { any })
		if stopped then return end
		local keep = {}
		for _, event in events do keep[event.castId] = true; effects.event(event, true) end
		for id in pending do if not keep[id] then pending[id] = nil end end
		for id, entry in active do if not keep[id] then stop(entry.event.owner, entry.event.life, id, entry.event.requestId); remove(id) end end
	end
	function effects.step(now: number)
		if stopped then return end
		lastStep = now
		pose.step(now)
		appearance.step(now)
		for id, entry in pending do
			local character, status = body(entry.event)
			if now >= entry.untilAt or status == "stale" then pending[id] = nil
			elseif character then pending[id] = nil; effects.event(entry.event, entry.quiet) end
		end
		for id, expires in retired do if now >= expires then retired[id] = nil end end
		for id, entry in active do
			local character = body(entry.event)
			if character ~= entry.character or now >= entry.event.expiresAt then stop(entry.event.owner, entry.event.life, id, entry.event.requestId); remove(id)
			else entry.visual.step(now) end
		end
		for i = #bursts, 1, -1 do if not bursts[i].step(now) then table.remove(bursts, i) end end
		for i = #sounds, 1, -1 do
			if now >= sounds[i].expires then sounds[i].part:Destroy(); table.remove(sounds, i) end
		end
	end
	-- Occluded/minimized clients can stop rendering. Character identity and expiry still advance.
	local background = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now - lastStep >= 0.1 then effects.step(now) end
	end)
	function effects.destroy()
		if stopped then return end
		for owner, current in casts do if current.castId or current.preview then stop(owner, current.life, current.castId, current.requestId) end end
		stopped = true
		background:Disconnect()
		if not sharedPose then pose.destroy() end
		appearance.destroy()
		for id in active do remove(id) end
		table.clear(pending); table.clear(ownerLives); table.clear(retired); table.clear(casts); table.clear(bursts); table.clear(sounds)
		folder:Destroy()
	end
	return effects
end
return ArrowEffects
