--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shape = require(script.Parent.WarriorShape)
local WarriorAppearance = {}
type Visitor = { player: Player, character: Model?, shape: any, dead: boolean, connections: { RBXScriptConnection }, died: RBXScriptConnection?, classChanged: RBXScriptConnection? }

function WarriorAppearance.new()
	local visitors: { [number]: Visitor } = {}
	local stopped, lastStep = false, 0
	local function clear(entry: Visitor)
		if entry.died then entry.died:Disconnect(); entry.died = nil end
		if entry.shape then entry.shape.destroy(); entry.shape = nil end
	end
	local function attach(entry: Visitor, character: Model?)
		clear(entry)
		if entry.classChanged then entry.classChanged:Disconnect(); entry.classChanged = nil end
		entry.character, entry.dead = character, false
		if character then entry.classChanged = character:GetAttributeChangedSignal("CombatClass"):Connect(function() clear(entry) end) end
	end
	local function watch(player: Player)
		if visitors[player.UserId] then return end
		local entry: Visitor = {player = player, character = player.Character, dead = false, connections = {}}
		visitors[player.UserId] = entry
		table.insert(entry.connections, player.CharacterAdded:Connect(function(character)
			attach(entry, character)
		end))
		table.insert(entry.connections, player.CharacterRemoving:Connect(function(character)
			if entry.character == character then attach(entry, nil) end
		end))
		attach(entry, player.Character)
	end
	local function forget(player: Player)
		local entry = visitors[player.UserId]
		if not entry then return end
		clear(entry)
		if entry.classChanged then entry.classChanged:Disconnect() end
		for _, connection in entry.connections do connection:Disconnect() end
		visitors[player.UserId] = nil
	end
	local added, removing = Players.PlayerAdded:Connect(watch), Players.PlayerRemoving:Connect(forget)
	for _, player in Players:GetPlayers() do watch(player) end
	local appearance = {}
	function appearance.step(now: number)
		if stopped then return end
		lastStep = now
		for _, entry in visitors do
			if entry.player.Character ~= entry.character then
				attach(entry, entry.player.Character)
			end
			local character = entry.character
			if not character or not character.Parent or entry.dead then continue end
			if character:GetAttribute("CombatClass") ~= "warrior" then clear(entry); continue end
			-- Warlock owns its visibility overrides. Let its old presentation restore first.
			if character:FindFirstChild("WarlockCostume") then clear(entry); continue end
			if entry.shape and entry.shape.folder.Parent ~= character then clear(entry) end
			if not entry.shape then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 then continue end
				entry.shape = Shape.new(character)
				if not entry.shape then continue end
				entry.died = humanoid.Died:Connect(function() entry.dead = true; clear(entry) end)
			end
			entry.shape.step(now)
		end
	end
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now - lastStep >= 0.1 then appearance.step(now) end
	end)
	function appearance.destroy()
		if stopped then return end
		stopped = true
		heartbeat:Disconnect(); added:Disconnect(); removing:Disconnect()
		for _, entry in visitors do forget(entry.player) end
	end
	return appearance
end
return WarriorAppearance
