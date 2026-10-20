--!strict
-- Supported server-side join API avoids launching six clients simultaneously.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StudioTestService = game:GetService("StudioTestService")
assert(game:GetService("RunService"):IsStudio() and ServerStorage:GetAttribute("StagedArenaTest") == true)
local control = ReplicatedStorage:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local ready: { [Player]: boolean } = {}
local connection = control.OnServerEvent:Connect(function(player, kind) if kind == "ready" then ready[player] = true end end)
local function awaitReady(count: number)
	local deadline = os.clock() + 25
	repeat
		local current = 0
		for player in ready do if player.Parent == Players then current += 1 end end
		if current >= count and #Players:GetPlayers() >= count then return end
		task.wait(0.05)
	until os.clock() >= deadline
	error("Staged join did not receive actual ready from client " .. count)
end
local ok, problem = xpcall(function()
	awaitReady(2)
	for count = 3, 6 do
		StudioTestService:AddPlayers(1)
		awaitReady(count)
		print("ArenaStagedJoin", "actualPlayers", #Players:GetPlayers(), "ready", count)
	end
end, debug.traceback)
connection:Disconnect()
if not ok then StudioTestService:EndTest({ok = false, error = tostring(problem)}) end
