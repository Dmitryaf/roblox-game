--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local control = ReplicatedStorage:WaitForChild("SliceTestControl") :: RemoteEvent
local ready: { [Player]: boolean } = {}
local reports: { [Player]: any } = {}
local connection = control.OnServerEvent:Connect(function(player, kind, data)
	if kind == "ready" then ready[player] = true else reports[player] = data end
end)
local function untilTrue(predicate: () -> boolean, seconds: number, reason: string)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.05) until os.clock() >= deadline
	error(reason)
end
local ok, err = xpcall(function()
	untilTrue(function()
		local count = 0
		for _ in ready do count += 1 end
		return count == 2
	end, 40, "Two clients did not become ready")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local shooter = players[1]
	local root = shooter.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local initial = root.Position
	local args = StudioTestService:GetTestArgs()
	control:FireClient(shooter, "exercise", if type(args) == "table" then args.lagMs else 0)
	untilTrue(function() return reports[shooter] ~= nil end, 20, "Shooter did not finish")
	assert(reports[shooter].ok, reports[shooter].error)
	assert((root.Position - initial).Magnitude > 8, "Server did not observe movement")
	control:FireClient(players[2], "report")
	untilTrue(function() return reports[players[2]] ~= nil end, 5, "Observer did not finish")
	assert(reports[players[2]].launched >= 1, "Second client missed projectile launch")
	assert(reports[players[2]].teleported >= 1, "Second client missed teleport")
	assert(reports[players[2]].visualSeen, "Second client did not create a projectile effect")
	assert(reports[players[2]].soundSeen, "Second client did not play launch audio")
	task.wait(3.6)
	local targetRoot = players[2].Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local targetHealth = players[2].Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	control:FireClient(shooter, "attack", targetRoot.Position + Vector3.new(0, 1, 0))
	untilTrue(function() return targetHealth.Health < 100 end, 4, "Projectile did not damage second player")
	assert(targetHealth.Health == 75, "Damage was not applied exactly once")
	task.wait(3.6)
	reports[shooter] = nil
	control:FireClient(shooter, "prepareForDeath")
	untilTrue(function() return reports[shooter] ~= nil and reports[shooter].castForDeath ~= nil end, 4, "Death-test cast did not start")
	local oldLife = reports[shooter].life
	local deadCharacter = shooter.Character :: Model
	(deadCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid).Health = 0
	untilTrue(function()
		return shooter.Character ~= nil and shooter.Character ~= deadCharacter
			and shooter.Character:FindFirstChild("HumanoidRootPart") ~= nil
	end, 12, "Character did not respawn")
	task.wait(1)
	reports[shooter] = nil
	control:FireClient(shooter, "verifyRespawn", oldLife)
	untilTrue(function() return reports[shooter] ~= nil end, 4, "Client did not verify respawn")
	assert(reports[shooter].ok, reports[shooter].error)
	print("PASS multiplayer: WASD/mouse/E, teleport, duplicate rejection, observer projectile/audio, HUD, opponent damage, death cleanup, respawn and stale-life rejection")
end, debug.traceback)
connection:Disconnect()
StudioTestService:EndTest({ ok = ok, error = if ok then nil else err })
