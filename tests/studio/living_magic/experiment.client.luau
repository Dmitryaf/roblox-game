--!strict
local RS = game:GetService("ReplicatedStorage")
local control = RS:WaitForChild("MixedTestControl", 20) :: RemoteEvent
local loadModule = require :: any
local Driver = loadModule(RS:WaitForChild("MixedTestDriver", 20))
local driver = Driver.new(game:GetService("Players").LocalPlayer)
local redirect: any = nil
local redirectCount, goldFrames = 0, 0
local events = (RS:WaitForChild("ArrowRemote", 20) :: RemoteEvent).OnClientEvent:Connect(function(event: any)
    if event.kind == "redirected" then redirect, redirectCount = event, redirectCount + 1 end
end)
local render = game:GetService("RunService").RenderStepped:Connect(function()
    local folder = workspace:FindFirstChild("LocalArrowEffects")
    local arrow = if folder then folder:FindFirstChild("DemonicArrow") else nil
    local core = if arrow then arrow:FindFirstChild("UnstableCore") else nil
    if core and core:IsA("BasePart") and core.Color == Color3.fromRGB(255, 218, 140) then goldFrames += 1 end
end)
local connection = control.OnClientEvent:Connect(function(id, action, data)
    local ok, result = xpcall(function()
        if action == "livingInspect" then return {redirect = redirect, count = redirectCount, goldFrames = goldFrames} end
        return driver.run(action, data)
    end, debug.traceback)
    control:FireServer("report", id, {ok = ok, data = if ok then result else nil, error = if ok then nil else tostring(result)})
end)
local ok, problem = xpcall(driver.ready, debug.traceback)
if ok then control:FireServer("ready") else control:FireServer("failure", tostring(problem)) end
script.Destroying:Connect(function() connection:Disconnect(); render:Disconnect(); events:Disconnect(); driver.destroy() end)
