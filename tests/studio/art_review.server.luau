--!strict
-- Local review fixture only: production rules, real projectiles, no synthetic VFX.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local token = ReplicatedStorage:WaitForChild("StudioTestToken", 10) :: StringValue?
assert(RunService:IsStudio() and token and token.Value == "art-review-local", "Art review is local Studio only")
local control = ReplicatedStorage:WaitForChild("ArtReviewControl", 10) :: RemoteEvent
local bridge = ServerStorage:WaitForChild("MatchTestBridge", 20) :: BindableFunction?
assert(bridge, "Production private match bridge did not initialize")
local prepared: { [Player]: boolean } = {}
local owner: Player? = nil
local connections: { RBXScriptConnection } = {}

local function place(player: Player, point: Vector3)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return end
	(bridge :: BindableFunction):Invoke("place", player.UserId, point)
	local face = CFrame.lookAt(point, Vector3.new(230, point.Y, -38))
	character:PivotTo(face * root.CFrame:Inverse() * character:GetPivot())
	root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
end
local function arrange()
	if not owner then return end
	local observer = 0
	for player in prepared do
		if player.Parent ~= Players then continue end
		local shooter = player == owner
		if not shooter then observer += 1 end
		place(player, if shooter then Vector3.new(230, 3.2, -8) else Vector3.new(246, 3.2, -18 + (observer - 1) * 6))
		control:FireClient(player, "placed", { owner = (owner :: Player).UserId, shooter = shooter })
	end
end
table.insert(connections, control.OnServerEvent:Connect(function(player, action)
	if action ~= "ready" then return end
	local character = player.Character
	if not character or type(character:GetAttribute("CombatLife")) ~= "number" then return end
	if prepared[player] then
		control:FireClient(player, "placed", { owner = if owner then owner.UserId else player.UserId, shooter = player == owner })
		return
	end
	prepared[player] = true
	if not owner then owner = player end
	arrange()
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	prepared[player] = nil
	if owner == player then
		owner = nil
		for visitor in prepared do if visitor.Parent == Players then owner = visitor; break end end
		arrange()
	end
end))
script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	table.clear(prepared)
end)
