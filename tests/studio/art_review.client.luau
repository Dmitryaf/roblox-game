--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local control = ReplicatedStorage:WaitForChild("ArtReviewControl", 20) :: RemoteEvent?
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 20) :: RemoteEvent?
assert(control and remote, "Art review endpoints did not initialize")
local ability = ReplicatedStorage:WaitForChild("ArtReviewAbility") :: StringValue
local handsMode = ability.Value == "hands"
local castRemote = if handsMode then ReplicatedStorage:WaitForChild("HandsRemote", 15) else remote
assert(castRemote and castRemote:IsA("RemoteEvent"), "Art review ability remote absent")
local arrowRemote = castRemote :: RemoteEvent
local stopped, placed, shooter = false, false, false
local requestId, view = 100000, 1
local connections: { RBXScriptConnection } = {}
local hidden: { [ScreenGui]: boolean } = {}
local views = {
	CFrame.lookAt(Vector3.new(244, 9, 8), Vector3.new(230, 3, -24)),
	CFrame.lookAt(Vector3.new(238, 5, -18), Vector3.new(230, 3, -8)),
	CFrame.lookAt(Vector3.new(258, 10, -22), Vector3.new(230, 3, -22)),
}
if handsMode then views[2] = CFrame.lookAt(Vector3.new(242, 8, -18), Vector3.new(230, 1, -34)) end
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ArtReviewLabel", false, 20
local label = Instance.new("TextLabel")
label.Size, label.Position = UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 8)
label.BackgroundTransparency, label.TextColor3 = 0.4, Color3.fromRGB(237, 232, 243)
label.BackgroundColor3, label.TextSize = Color3.fromRGB(22, 18, 31), 14
label.TextWrapped, label.Font = true, Enum.Font.GothamMedium
label.Text = "РҐСѓРґРѕР¶РµСЃС‚РІРµРЅРЅС‹Р№ РїСЂРѕСЃРјРѕС‚СЂ В· 1/2/3 вЂ” СЂР°РєСѓСЂСЃ В· Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРёР№ РІС‹СЃС‚СЂРµР»"
label.Parent, gui.Parent = gui, player:WaitForChild("PlayerGui")
local function hide(item: Instance)
	if item:IsA("ScreenGui") and (item.Name == "MatchHud" or item.Name == "ArrowHud" or item.Name == "HandsHud" or item.Name == "ClassHud" or item.Name == "MeleeHud") then
		if hidden[item] == nil then hidden[item] = item.Enabled end
		item.Enabled = false
	end
end
for _, item in player.PlayerGui:GetChildren() do hide(item) end
table.insert(connections, player.PlayerGui.ChildAdded:Connect(hide))
table.insert(connections, (control :: RemoteEvent).OnClientEvent:Connect(function(action, data)
	if action == "placed" then placed, shooter = true, data.shooter == true end
end))
table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.One then view = 1
	elseif input.KeyCode == Enum.KeyCode.Two then view = 2
	elseif input.KeyCode == Enum.KeyCode.Three then view = 3 end
end))
table.insert(connections, RunService.RenderStepped:Connect(function()
	for item in hidden do if item.Parent then item.Enabled = false end end
	local camera = workspace.CurrentCamera
	if not camera then return end
	camera.CameraType, camera.CFrame, camera.Focus = Enum.CameraType.Scriptable, views[view], CFrame.new(230, 3, -22)
end))
script.Destroying:Connect(function()
	stopped = true
	for _, connection in connections do connection:Disconnect() end
	for item, enabled in hidden do if item.Parent then item.Enabled = enabled end end
	gui:Destroy()
end)
task.spawn(function()
	local deadline = os.clock() + 45
	local ready = false
	repeat
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local costume = if character then character:FindFirstChild("WarlockCostume") else nil
		local count = 0
		if costume then
			for _, part in costume:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "BriefFelFootprint" then count += 1 end
			end
		end
		ready = root ~= nil and humanoid ~= nil and humanoid.Health > 0 and count == 43
			and character ~= nil and type(character:GetAttribute("CombatLife")) == "number"
		if not ready then task.wait(0.1) end
	until ready or stopped or os.clock() >= deadline
	if not ready then label.Text = "РџСЂРѕСЃРјРѕС‚СЂ РЅРµ Р·Р°РїСѓС‰РµРЅ: РїРµСЂСЃРѕРЅР°Р¶ РёР»Рё РїРѕР»РЅС‹Р№ РѕР±Р»РёРє РЅРµ Р·Р°РіСЂСѓР·РёР»СЃСЏ."; return end
	deadline = os.clock() + 15
	repeat (control :: RemoteEvent):FireServer("ready"); task.wait(0.5) until placed or stopped or os.clock() >= deadline
	if not placed then label.Text = "РџСЂРѕСЃРјРѕС‚СЂ РЅРµ Р·Р°РїСѓС‰РµРЅ: СЃРµСЂРІРµСЂ РЅРµ РїРѕРґС‚РІРµСЂРґРёР» СЂР°Р·РјРµС‰РµРЅРёРµ."; return end
	task.wait(1)
	while not stopped do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local life = if character then character:GetAttribute("CombatLife") else nil
		if shooter and root and root:IsA("BasePart") and type(life) == "number" then
			requestId += 1
			local direction = Vector3.new(230, 3.5, -38) - (root.Position + Vector3.yAxis)
			if handsMode then
                arrowRemote:FireServer({ action = "cast", requestId = requestId, life = life, position = Vector3.new(230, 0, -34) })
            elseif direction.Magnitude > 0.1 then
				arrowRemote:FireServer({ action = "cast", requestId = requestId, life = life, direction = direction.Unit })
			end
		end
		task.wait(if handsMode then 10 else 5)
	end
end)
