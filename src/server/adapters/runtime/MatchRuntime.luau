--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MatchRuntime = {}
function MatchRuntime.new(combat: any, world: any, arena: any, now: () -> number, respawn: number, classes: any?)
	local connections: { RBXScriptConnection } = {}
	local owned: { [number]: { RBXScriptConnection } } = {}
	local deaths: { [number]: RBXScriptConnection } = {}
	local players: { [number]: Player } = {}
	local characters: { [number]: Model } = {}
	local generation: { [number]: number } = {}
	local loading: { [number]: boolean } = {}
	local matches: any
	local arrowGateway: any
	local matchGateway: any
    local handsGateway: any
    local classGateway: any
    local meleeGateway: any
    local dashGateway: any
	local lifeSequence, lastPublish = 0, 0
	local stopped = false
	local runtime = {}
	local function sync(owner: number)
		local player = players[owner]
		if player and arrowGateway then arrowGateway.sync(player) end
        if player and handsGateway then handsGateway.sync(player) end
        if player and classGateway then classGateway.sync(player) end
        if player and meleeGateway then meleeGateway.sync(player) end
        if player and dashGateway then dashGateway.sync(player) end
	end
	local function load(owner: number)
		local player = players[owner]
		if not player or stopped or loading[owner] then return end
		generation[owner] = (generation[owner] or 0) + 1
		loading[owner] = true
		task.spawn(function()
			local ok, err = pcall(function() player:LoadCharacterAsync() end)
			loading[owner] = nil
			if not ok and players[owner] and not stopped then
				warn("Character load failed; retrying", owner, err)
				task.delay(3, function() if not stopped and players[owner] and not world.alive(owner) then load(owner) end end)
			end
		end)
	end
	function runtime.reset(owner: number, team: number?, frozen: boolean)
		generation[owner] = (generation[owner] or 0) + 1
		if not world.resetContext(owner, team, frozen) then
			combat.leave(owner)
			load(owner)
			return
		end
		lifeSequence += 1
		local character = characters[owner]
		if character then
			character:SetAttribute("CombatLife", lifeSequence)
            character:SetAttribute("CombatClass", if classes then classes.get(owner) else "warlock")
			character:SetAttribute("MatchTeam", team)
			local previous = character:FindFirstChild("MatchTeamLabel")
			if previous then previous:Destroy() end
			if team then
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local marker = Instance.new("BillboardGui")
					marker.Name, marker.Adornee = "MatchTeamLabel", root
					marker.Size, marker.StudsOffset, marker.MaxDistance = UDim2.fromOffset(80, 28), Vector3.new(0, 4, 0), 170
					local text = Instance.new("TextLabel")
					text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
					text.Text, text.Font, text.TextSize = if team == 1 then "A" else "B", Enum.Font.GothamBold, 22
					text.TextColor3 = if team == 1 then Color3.fromRGB(100, 200, 255) else Color3.fromRGB(255, 182, 100)
					text.TextStrokeTransparency = 0.35
					text.Parent, marker.Parent = marker, character
				end
			end
		end
		combat.join(owner, lifeSequence)
		if frozen then combat.pause(owner, now()) end
		sync(owner)
	end
	function runtime.freeze(owner: number, value: boolean)
		world.freeze(owner, value)
		if value then combat.pause(owner, now()) else combat.resume(owner, now()) end
		sync(owner)
	end
	local function detach(owner: number)
		characters[owner] = nil
		if deaths[owner] then deaths[owner]:Disconnect(); deaths[owner] = nil end
		combat.die(owner)
		world.remove(owner)
	end
	local function addCharacter(player: Player, character: Model)
		local owner = player.UserId
		detach(owner)
		characters[owner] = character
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		-- CharacterAdded precedes parenting to Workspace during LoadCharacterAsync.
		-- The world adapter deliberately rejects an unparented/dead body.
		local deadline = os.clock() + 10
		while not character:IsDescendantOf(workspace) and not stopped and characters[owner] == character and os.clock() < deadline do
			task.wait()
		end
		if stopped or characters[owner] ~= character or player.Character ~= character or not players[owner] then return end
		if not character:IsDescendantOf(workspace) then return end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then return end
		local context = matches.context(owner)
		world.register(owner, character, root, humanoid, arena.spawn(context.team, owner))
		runtime.reset(owner, context.team, context.frozen)
		deaths[owner] = humanoid.Died:Connect(function()
			-- A ready visitor/reserved pair must not enter while its body is unavailable.
			-- Death of an existing roster member remains a five-second respawn, not an exit.
			if matches.snapshot(owner, now()).ready then matches.ready(owner, false, now()) end
			combat.die(owner)
			sync(owner)
			generation[owner] = (generation[owner] or 0) + 1
			local token = generation[owner]
			task.delay(respawn, function()
				if not stopped and players[owner] and generation[owner] == token and characters[owner] == character then load(owner) end
			end)
		end)
	end
	local function addPlayer(player: Player)
		local owner = player.UserId
		if players[owner] then return end
		players[owner] = player
        if classes then classes.join(owner) end
		matches.join(owner, now())
		owned[owner] = {
			player.CharacterAdded:Connect(function(character) addCharacter(player, character) end),
			player.CharacterRemoving:Connect(function(character)
				if characters[owner] == character then
					if matches.snapshot(owner, now()).ready then matches.ready(owner, false, now()) end
					detach(owner)
				end
			end),
		}
		if player.Character then task.spawn(addCharacter, player, player.Character) else load(owner) end
	end
	local function removePlayer(player: Player)
		local owner = player.UserId
		players[owner] = nil
		generation[owner] = nil
		matches.leave(owner, now())
		arena.forget(owner)
		detach(owner)
		combat.leave(owner)
		if owned[owner] then for _, connection in owned[owner] do connection:Disconnect() end end
		owned[owner] = nil
		arrowGateway.forget(owner); matchGateway.forget(owner)
        if handsGateway then handsGateway.forget(owner) end
        if classGateway then classGateway.forget(owner) end
        if meleeGateway then meleeGateway.forget(owner) end
        if dashGateway then dashGateway.forget(owner) end
        if classes then classes.leave(owner) end
	end
	function runtime.tick()
		if stopped then return end
		world.step()
        combat.step(now()) -- Resolve deaths before sampling objective occupants.
		matches.step(now(), world.onZone())
	end
	function runtime.start(matchService: any, arrow: any, match: any, hands: any?, selection: any?, melee: any?, dash: any?)
		matches, arrowGateway, matchGateway, handsGateway = matchService, arrow, match, hands
        classGateway, meleeGateway = selection, melee
        dashGateway = dash
		arrowGateway.start(); matchGateway.start()
        if handsGateway then handsGateway.start() end
        if classGateway then classGateway.start() end
        if meleeGateway then meleeGateway.start() end
        if dashGateway then dashGateway.start() end
		table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
		table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
		table.insert(connections, RunService.Heartbeat:Connect(function()
			runtime.tick()
			if now() - lastPublish >= 0.2 then
				lastPublish = now()
				for _, player in players do
                    matchGateway.sync(player)
                    if classGateway then classGateway.sync(player) end
                end
			end
		end))
		for _, player in Players:GetPlayers() do addPlayer(player) end
	end
	function runtime.destroy()
		if stopped then return end
		stopped = true
		for _, connection in connections do connection:Disconnect() end
		for _, player in table.clone(players) do removePlayer(player) end
		matches.destroy(); combat.destroy()
		arrowGateway.destroy(); matchGateway.destroy()
        if handsGateway then handsGateway.destroy() end
        if classGateway then classGateway.destroy() end
        if meleeGateway then meleeGateway.destroy() end
        if dashGateway then dashGateway.destroy() end
        if classes then classes.destroy() end
	end
	return runtime
end
return MatchRuntime
