--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
local control = ReplicatedStorage:WaitForChild("LivingReviewControl") :: RemoteEvent
local loadModule = require :: any
local driver = loadModule(ReplicatedStorage:WaitForChild("MixedTestDriver") :: ModuleScript).new(player)
local reviewLabel = if ReplicatedStorage:GetAttribute("LivingMagicExperiment") == true then "NATIVE DRAFT" else "BASELINE"
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "LivingBaseline", false, 110
local title = Instance.new("TextButton")
title.Size, title.Position = UDim2.new(1, -24, 0, 44), UDim2.fromOffset(12, 110)
title.TextWrapped, title.TextSize, title.TextColor3 = true, 16, Color3.new(1, 1, 1)
title.BackgroundColor3, title.Text, title.Parent = Color3.fromRGB(28, 31, 37), "Two real clients initializing…", gui
gui.Parent = player:WaitForChild("PlayerGui")
local scene: any = nil
local side, effects = false, true
local hidden: { [Instance]: any } = {}
local folders = { LocalArrowEffects = true, LocalMeleeEffects = true, LocalHeavyEffects = true, LocalHandsEffects = true, LocalDashEffects = true, LocalLivingInteractions = true }
local connections: { RBXScriptConnection } = {}
local function camera()
    if not scene then return end
    local actor = Players:GetPlayerByUserId(scene.attacker)
    local root = if actor and actor.Character then actor.Character:FindFirstChild("HumanoidRootPart") else nil
    if not root or not root:IsA("BasePart") then return end
    local value = workspace.CurrentCamera :: Camera
    local at = root.Position + Vector3.new(0, 1, -4)
    value.CameraType, value.CFrame = Enum.CameraType.Scriptable, CFrame.lookAt(
        root.Position + (if side then Vector3.new(16, 4, -4) else Vector3.new(7, 6, 15)), at)
end
local function hide(item: Instance)
    if effects then return end
    local property = if item:IsA("BasePart") or item:IsA("Trail") or item:IsA("Beam") then "LocalTransparencyModifier"
        elseif item:IsA("ParticleEmitter") or item:IsA("Light") then "Enabled" else nil
    if not property then return end
    if not hidden[item] then
        local ok, value = pcall(function() return (item :: any)[property] end)
        if not ok then return end
        hidden[item] = { property = property, value = value }
    end
    (item :: any)[property] = if property == "Enabled" then false else 1
end
local function scan()
    if effects then return end
    for _, item in workspace:GetChildren() do
        if folders[item.Name] then for _, child in item:GetDescendants() do hide(child) end end
    end
    for _, other in Players:GetPlayers() do
        if not other.Character then continue end
        for _, item in other.Character:GetDescendants() do
            if item:IsA("Trail") or item:IsA("Beam") or item:IsA("ParticleEmitter") or item:IsA("Light") then hide(item) end
        end
    end
    for item in hidden do if not item.Parent then hidden[item] = nil end end
end
local renderName = "LivingBaselineVfx" .. player.UserId
RunService:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value + 100, scan)
table.insert(connections, workspace.DescendantAdded:Connect(function(item: Instance)
    local parent: Instance? = item.Parent
    while parent and parent ~= workspace do
        if folders[parent.Name] then hide(item); return end
        parent = parent.Parent
    end
end))
local function nextScene() control:FireServer("next") end
table.insert(connections, title.Activated:Connect(nextScene))
table.insert(connections, Input.InputBegan:Connect(function(input, processed)
    if processed or Input:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.N then nextScene()
    elseif input.KeyCode == Enum.KeyCode.F4 then side = not side; camera()
    elseif input.KeyCode == Enum.KeyCode.F6 then
        effects = not effects
        if effects then for item, old in hidden do if item.Parent then (item :: any)[old.property] = old.value end end; table.clear(hidden) end
    end
end))
table.insert(connections, control.OnClientEvent:Connect(function(id, action, data)
    if action == "failure" then
        title.Text = reviewLabel .. " STOPPED · " .. data.label .. " · details in Studio Output"
        title.Active = false
        return
    end
    if action == "scene" then
        scene = data
        if data.effects ~= nil then
            effects, side = data.effects, not data.effects
            if effects then for item, old in hidden do if item.Parent then (item :: any)[old.property] = old.value end end; table.clear(hidden) end
        end
        camera()
        title.Text = string.format("%s · %s · %s · observer %s · N/клик: пуск · F4: ракурс · F6: VFX", reviewLabel, data.label, if effects then "VFX ON" else "VFX OFF", player.Name)
        return
    end
    local ok, result = xpcall(function() return driver.run(action, data) end, debug.traceback)
    control:FireServer("report", id, { ok = ok, data = if ok then result else nil, error = if ok then nil else tostring(result) })
end))
driver.ready(); control:FireServer("ready")
script.Destroying:Connect(function()
    RunService:UnbindFromRenderStep(renderName)
    for _, c in connections do c:Disconnect() end
    for item, old in hidden do if item.Parent then (item :: any)[old.property] = old.value end end
    driver.destroy(); gui:Destroy()
end)
