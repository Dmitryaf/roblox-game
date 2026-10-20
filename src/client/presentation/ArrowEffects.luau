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

function ArrowEffects.new()
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "LocalArrowEffects", workspace
	local active: { [number]: any } = {}
	local bursts: { any } = {}
	local sounds: { any } = {}
	local pose, appearance = CastPose.new(), WarlockAppearance.new()
	local lastStep = 0
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
	local function stop(owner: number)
		pose.stop(owner)
		appearance.stop(owner)
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
    function effects.prepare(owner: number, launchAt: number, direction: Vector3?, startedAt: number?)
        pose.begin(owner, launchAt, direction, startedAt)
        appearance.cast(owner, launchAt, startedAt)
    end
    function effects.stopCast(owner: number) stop(owner) end
	function effects.event(event: any, quiet: boolean?)
		local id = event.castId
		if event.kind == "ended" then
			remove(id)
			if event.reason == "dead" or event.reason == "left" or event.reason == "reset" or event.reason == "invalid_position" or event.reason == "paused" then stop(event.owner) end
			if event.position and (event.reason == "hit" or event.reason == "teleported") and not quiet then
				table.insert(bursts, ChaosImpact.new(folder, event.position, event.reason == "teleported", id, workspace:GetServerTimeNow()))
				cue(event.reason, event.position, event.owner)
			end
			return
		end
		local flying = event.kind == "launched" or event.kind == "flying"
		local old = active[id]
		if old and old.flying == flying then return end
		remove(id)
		local visual = ChaosArrow.new(folder, event, flying)
		active[id] = {visual = visual, event = event, flying = flying}
		visual.step(workspace:GetServerTimeNow())
		if not flying then
			effects.prepare(event.owner, event.launchAt, event.direction, event.startedAt)
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
		local keep = {}
		for _, event in events do keep[event.castId] = true; effects.event(event, true) end
		for id, entry in active do if not keep[id] then stop(entry.event.owner); remove(id) end end
	end
	function effects.step(now: number)
		lastStep = now
		pose.step(now)
		appearance.step(now)
		for id, entry in active do
			if now >= entry.event.expiresAt then stop(entry.event.owner); remove(id)
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
		background:Disconnect()
		pose.destroy()
		appearance.destroy()
		table.clear(active); table.clear(bursts); table.clear(sounds)
		folder:Destroy()
	end
	return effects
end
return ArrowEffects
