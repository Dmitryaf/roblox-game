--!strict
-- The example driver presses genuine controls. Free play uses the normal camera/input.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local control = RS:WaitForChild("LivingEpisodeControl") :: RemoteEvent
local loadModule = require :: any
local driver = loadModule(RS:WaitForChild("MixedTestDriver") :: ModuleScript).new(player)
local gui = Instance.new("ScreenGui")
gui.Name, gui.DisplayOrder, gui.ResetOnSpawn = "LivingEpisode", 110, false
local title = Instance.new("TextButton")
title.Size, title.Position = UDim2.new(1, -40, 0, 58), UDim2.fromOffset(20, 8)
title.BackgroundColor3, title.BackgroundTransparency = Color3.fromRGB(20, 28, 28), 0.12
title.TextColor3, title.TextSize, title.TextWrapped = Color3.fromRGB(234, 239, 221), 17, true
title.Font, title.Text = Enum.Font.GothamMedium, "Стрела у разрушенной арки · ожидаем второго участника"
title.Parent, gui.Parent = gui, player:WaitForChild("PlayerGui")
local connections: { RBXScriptConnection } = {}
local frameTimes: { number } = {}
local rendered, elapsed, worst, total = 0, 0, 0, 0
local sampling = false
local showcasing = false
local hiddenHud: {[ScreenGui]: {parent: Instance?, enabled: boolean}} = {}
local ordinaryHud = {MatchHud = true, ClassHud = true, ArrowHud = true, HandsHud = true,
    MeleeHud = true, HeavyHud = true, DashHud = true}
local function showcase(value: boolean)
    showcasing = value
    if value then
        for _, item in (gui.Parent :: Instance):GetChildren() do
            if item:IsA("ScreenGui") and ordinaryHud[item.Name] then
                if hiddenHud[item] == nil then hiddenHud[item] = {parent = item.Parent, enabled = item.Enabled} end
                item.Enabled = false
                -- Controllers may enable their cards after RenderStepped. Detach
                -- only this fixture's HUDs during the example; preserve instances.
                item.Parent = nil
            end
        end
    else
        for item, previous in hiddenHud do
            item.Enabled = previous.enabled
            item.Parent = previous.parent
        end
        table.clear(hiddenHud)
    end
end
table.insert(connections, (gui.Parent :: Instance).ChildAdded:Connect(function()
    if showcasing then showcase(true) end
end))
local function resetCamera()
    local camera = workspace.CurrentCamera
    local humanoid = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        if humanoid then camera.CameraSubject = humanoid end
    end
end
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
    if not sampling then return end
    rendered += 1; elapsed += dt; total += dt; worst = math.max(worst, dt)
    -- Bounded reservoir of this short demonstration; no persistent telemetry.
    if #frameTimes < 12000 then table.insert(frameTimes, dt) end
end))
local function requestExamples() control:FireServer("next") end
table.insert(connections, title.Activated:Connect(requestExamples))
table.insert(connections, Input.InputBegan:Connect(function(input, processed)
    if not processed and not Input:GetFocusedTextBox() and input.KeyCode == Enum.KeyCode.N then requestExamples() end
end))
table.insert(connections, control.OnClientEvent:Connect(function(id, action, data)
    if action == "caption" then
        title.Text, title.Active = data.text, data.active == true
        if data.free then showcase(false); resetCamera() end
        if data.sample ~= nil then sampling = data.sample; showcase(data.sample) end
        return
    end
    local ok, result = xpcall(function(): any
        if action == "reviewUi" then
            local hud = (gui.Parent :: Instance):FindFirstChild("MatchHud")
            local kept = 0
            for _ in hiddenHud do kept += 1 end
            return {showcasing = showcasing, hidden = kept,
                matchHudEnabled = hud ~= nil and hud:IsA("ScreenGui") and hud.Enabled,
                customCamera = (workspace.CurrentCamera :: Camera).CameraType == Enum.CameraType.Custom}
        end
        if action == "metrics" then
            table.sort(frameTimes)
            return { frames = rendered, seconds = elapsed, meanMs = if rendered > 0 then total / rendered * 1000 else 0,
                p95Ms = if #frameTimes > 0 then frameTimes[math.max(1, math.ceil(#frameTimes * 0.95))] * 1000 else 0,
                worstMs = worst * 1000, inspect = driver.run("inspect") }
        end
        return driver.run(action, data)
    end, debug.traceback)
    control:FireServer("report", id, { ok = ok, data = if ok then result else nil, error = if ok then nil else tostring(result) })
end))
driver.ready(); control:FireServer("ready")
script.Destroying:Connect(function()
    for _, connection in connections do connection:Disconnect() end
    driver.destroy(); showcase(false); gui:Destroy(); resetCamera()
end)
