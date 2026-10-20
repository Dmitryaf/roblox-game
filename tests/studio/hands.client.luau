--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local control = ReplicatedStorage:WaitForChild("HandsTestControl") :: RemoteEvent
local remote = ReplicatedStorage:WaitForChild("HandsRemote") :: RemoteEvent
local matchRemote = ReplicatedStorage:WaitForChild("MatchRemote") :: RemoteEvent
local state: any = nil
local matchState: any = nil
local preparing, active, ended, replyCount, observed = 0, 0, 0, 0, false
local lastReply: any = nil
local aimConnection: RBXScriptConnection? = nil
local matchRequest = 100000
local keyEvents = 0
game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Q then keyEvents += 1 end
end)
local function waitFor(predicate: () -> boolean, seconds: number, message: string)
    local deadline = os.clock() + seconds
    repeat if predicate() then return end; task.wait(0.03) until os.clock() >= deadline
    error(message)
end
remote.OnClientEvent:Connect(function(event)
    if event.kind == "snapshot" or event.kind == "reply" then state = event.state end
    if event.kind == "reply" then replyCount += 1; lastReply = event end
    if event.kind == "preparing" then
        if event.owner == player.UserId then preparing += 1 end
    elseif event.kind == "active" then
        if event.owner == player.UserId then active += 1 end
        task.delay(0.15, function()
            local folder = workspace:FindFirstChild("LocalHandsEffects")
            if folder and folder:FindFirstChild("DemonicHandsArea") then observed = true end
        end)
    elseif event.kind == "ended" then ended += 1 end
end)
matchRemote.OnClientEvent:Connect(function(event)
    if event.kind == "snapshot" or event.kind == "reply" then matchState = event.state end
end)
control.OnClientEvent:Connect(function(id, action, data)
    local result: any = nil
    local ok, problem = xpcall(function()
        if action == "ready" or action == "exit" then
            matchRequest += 1
            matchRemote:FireServer({ action = action, requestId = matchRequest, matchId = if matchState then matchState.matchId else 0 })
        elseif action == "cast" then
            waitFor(function() return state ~= nil and state.alive and not state.suspended end, 4, "Hands client still suspended")
            local virtual = game:GetService("UserInputService"):CreateVirtualInput()
            assert(virtual, "Virtual keyboard unavailable")
            local point: Vector3 = data.point
            local camera = workspace.CurrentCamera :: Camera
            camera.CameraType = Enum.CameraType.Scriptable
            local aimedAt = CFrame.lookAt(point + Vector3.new(14, 19, 18), point)
            camera.CFrame = aimedAt
            if aimConnection then aimConnection:Disconnect() end
            aimConnection = game:GetService("RunService").RenderStepped:Connect(function()
                camera.CameraType, camera.CFrame = Enum.CameraType.Scriptable, aimedAt
            end)
            local projected = camera:WorldToViewportPoint(point)
            local mouse = Vector2.new(projected.X, projected.Y)
            virtual:SendMousePosition(mouse)
            -- Give the play viewport keyboard focus without firing the LMB ability.
            virtual:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, true)
            virtual:SendMouseButton(mouse, Enum.UserInputType.MouseButton2, false)
            task.wait(0.15)
            local before = replyCount
            virtual:SendKey(true, Enum.KeyCode.Q, false)
            virtual:SendKey(false, Enum.KeyCode.Q, false)
            local delivered = pcall(function() waitFor(function() return replyCount > before end, 5, "No Q reply") end)
            if not delivered then
                local location = game:GetService("UserInputService"):GetMouseLocation()
                print("HandsInputDiag", keyEvents, location, camera.CFrame.Position, point)
                local ray = camera:ViewportPointToRay(location.X, location.Y)
                local parameters = RaycastParams.new()
                parameters.FilterType, parameters.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { player.Character :: Model }
                local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, parameters)
                local hud = player.PlayerGui:FindFirstChild("HandsHud")
                local label = if hud then hud:FindFirstChild("Ability") else nil
                local buttons = {}
                local atGui = location - game:GetService("GuiService"):GetGuiInset()
                for _, item in player.PlayerGui:GetGuiObjectsAtPosition(atGui.X, atGui.Y) do
                    if item:IsA("GuiButton") then table.insert(buttons, item:GetFullName()) end
                end
                error(game:GetService("HttpService"):JSONEncode({ keys = keyEvents, state = state, viewport = tostring(camera.ViewportSize),
                    hud = if label and label:IsA("TextLabel") then label.Text else "absent", mouse = tostring(location),
                    hit = if hit then hit.Instance:GetFullName() .. " " .. tostring(hit.Position) .. " normal=" .. tostring(hit.Normal) else "none",
                    buttons = buttons, bound = game:GetService("ContextActionService"):GetBoundActionInfo("CastHands").priorityLevel }))
            end
            assert(lastReply.ok == data.ok, "Unexpected hands result: " .. tostring(lastReply.reason))
            if data.reason then assert(lastReply.reason == data.reason, "Unexpected rejection reason") end
            result = { state = state, reply = lastReply, preparing = preparing }
        elseif action == "inspect" then
            local folder = workspace:FindFirstChild("LocalHandsEffects")
            assert(folder, "Hands presentation folder absent")
            local count = 0
            for _, item in folder:GetDescendants() do
                if item:IsA("BasePart") then
                    count += 1
                    assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch,
                        "Hands visuals entered physics: " .. item.Name)
                end
            end
            local query = OverlapParams.new()
            query.FilterType, query.FilterDescendantsInstances = Enum.RaycastFilterType.Include, { folder }
            query.RespectCanCollide = false
            assert(#workspace:GetPartBoundsInBox(CFrame.new(2, 2, -30), Vector3.one * 40, query) == 0, "Hands appeared in overlap query")
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            result = { position = if root and root:IsA("BasePart") then root.Position else nil,
                observed = observed, count = count, children = #folder:GetChildren(), state = state,
                preparing = preparing, active = active, ended = ended, hud = player.PlayerGui:FindFirstChild("HandsHud") ~= nil }
        else error("Unknown fixture action") end
    end, debug.traceback)
    if aimConnection then aimConnection:Disconnect(); aimConnection = nil end
    control:FireServer("report", id, { ok = ok, error = if ok then nil else tostring(problem), data = result })
end)
local ok, problem = xpcall(function()
    waitFor(function()
        return state ~= nil and state.life > 0 and matchState ~= nil and player.Character ~= nil
            and player.PlayerGui:FindFirstChild("HandsHud") ~= nil
    end, 40, "Production hands controller/HUD did not initialize")
    control:FireServer("ready")
end, debug.traceback)
if not ok then control:FireServer("failure", tostring(problem)) end
