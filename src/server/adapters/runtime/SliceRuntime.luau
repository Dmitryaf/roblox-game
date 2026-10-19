--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SliceRuntime = {}
function SliceRuntime.start(service: any, world: any, gateway: any, now: () -> number)
	local connections: { RBXScriptConnection } = {}
	local owners: { [Player]: { RBXScriptConnection } } = {}
	local deaths: { [Player]: RBXScriptConnection } = {}
	local characters: { [Player]: Model } = {}
	local lifeSequence = 0
	local stopped = false
	local function removeCharacter(player: Player)
		characters[player] = nil
		if deaths[player] then deaths[player]:Disconnect(); deaths[player] = nil end
		service.die(player.UserId)
		world.remove(player.UserId)
	end
	local function addCharacter(player: Player, character: Model)
		removeCharacter(player)
		characters[player] = character
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if stopped or characters[player] ~= character or not player.Parent then return end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then return end
		lifeSequence += 1
		world.register(player.UserId, character, root, humanoid)
		service.join(player.UserId, lifeSequence)
		deaths[player] = humanoid.Died:Connect(function()
			service.die(player.UserId)
			gateway.sync(player)
		end)
		gateway.sync(player)
	end
	local function addPlayer(player: Player)
		if owners[player] then return end
		owners[player] = {
			player.CharacterAdded:Connect(function(character) addCharacter(player, character) end),
			player.CharacterRemoving:Connect(function(character)
				if characters[player] == character then removeCharacter(player) end
			end),
		}
		if player.Character then task.spawn(addCharacter, player, player.Character) end
	end
	local function removePlayer(player: Player)
		removeCharacter(player)
		local owned = owners[player]
		if owned then for _, connection in owned do connection:Disconnect() end end
		owners[player] = nil
		gateway.forget(player.UserId)
		service.leave(player.UserId)
	end
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
	table.insert(connections, RunService.Heartbeat:Connect(function()
		world.step()
		service.step(now())
	end))
	gateway.start()
	for _, player in Players:GetPlayers() do addPlayer(player) end
	return function()
		if stopped then return end
		stopped = true
		for _, connection in connections do connection:Disconnect() end
		for player in owners do removePlayer(player) end
		gateway.destroy()
		service.destroy()
	end
end
return SliceRuntime
