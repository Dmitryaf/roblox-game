--!strict
local Players = game:GetService("Players")
local Costume = require(script.Parent.WarlockCostume)
local Presence = require(script.Parent.WarlockPresence)
local WarlockAppearance = {}
type Visitor = { player: Player, character: Model?, costume: any, presence: any, dead: boolean, release: number?, started: number?,
	added: RBXScriptConnection?, removing: RBXScriptConnection?, died: RBXScriptConnection? }

function WarlockAppearance.new()
	local visitors: { [number]: Visitor } = {}
	local function clear(entry: Visitor)
		if entry.died then entry.died:Disconnect(); entry.died = nil end
		if entry.presence then entry.presence.destroy(); entry.presence = nil end
		if entry.costume then entry.costume.destroy(); entry.costume = nil end
		entry.release, entry.started = nil, nil
	end
	local function watch(player: Player)
		if visitors[player.UserId] then return end
		local entry: Visitor = { player = player, character = player.Character, dead = false }
		visitors[player.UserId] = entry
		entry.added = player.CharacterAdded:Connect(function(character)
			clear(entry); entry.character, entry.dead = character, false
		end)
		entry.removing = player.CharacterRemoving:Connect(function(character)
			if entry.character ~= character then return end
			clear(entry); entry.character = nil
		end)
	end
	local function forget(player: Player)
		local entry = visitors[player.UserId]
		if not entry then return end
		clear(entry)
		if entry.added then entry.added:Disconnect() end
		if entry.removing then entry.removing:Disconnect() end
		visitors[player.UserId] = nil
	end
	local added, removing = Players.PlayerAdded:Connect(watch), Players.PlayerRemoving:Connect(forget)
	for _, player in Players:GetPlayers() do watch(player) end
	local appearance = {}
	function appearance.cast(owner: number, launchAt: number, startedAt: number?)
		local entry = visitors[owner]
		if entry and not entry.dead then
			entry.release, entry.started = launchAt, startedAt or workspace:GetServerTimeNow()
		end
	end
	function appearance.stop(owner: number)
		local entry = visitors[owner]
		if entry then entry.release, entry.started = nil, nil end
	end
	function appearance.step(now: number)
		for _, entry in visitors do
			if entry.player.Character ~= entry.character then
				clear(entry)
				entry.character, entry.dead = entry.player.Character, false
			end
			local character = entry.character
			if not character or not character.Parent or entry.dead then continue end
			if entry.costume and entry.costume.folder.Parent ~= character then clear(entry) end
			if not entry.costume then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid then continue end
				-- Initial character replication can expose a zero-health Humanoid before spawn finishes.
				-- Only Died on a live, initialized presentation latches this character as dead.
				if humanoid.Health <= 0 then continue end
				entry.costume = Costume.new(character)
				if not entry.costume then continue end
				entry.presence = Presence.new(character, entry.costume.folder)
				entry.died = humanoid.Died:Connect(function() entry.dead = true; clear(entry) end)
			end
			local release = entry.release
			local weight = 0
			if release then
				weight = if now < release then math.clamp((now - (entry.started or now)) / math.max(0.06, release - (entry.started or now)) / 0.6, 0, 1)
					else math.clamp(1 - (now - release) / 0.45, 0, 1)
			end
			if release and now > release + 0.45 then entry.release, entry.started = nil, nil end
			entry.costume.step(now, weight)
			if entry.presence then entry.presence.step(now, weight) end
		end
	end
	function appearance.destroy()
		added:Disconnect(); removing:Disconnect()
		for _, entry in visitors do forget(entry.player) end
	end
	return appearance
end
return WarlockAppearance
