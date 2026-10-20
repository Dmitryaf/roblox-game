--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local control = ReplicatedStorage:WaitForChild("ContactTestControl", 20) :: RemoteEvent
local loadModule = require :: any
local Driver: any = loadModule(ReplicatedStorage:WaitForChild("ContactTestDriver", 20) :: ModuleScript)
local driver = Driver.new(game:GetService("Players").LocalPlayer, function(tag: string, ok: boolean, data: any)
	control:FireServer("completed", tag, { ok = ok, data = if ok then data else nil, error = if ok then nil else tostring(data) })
end)
local connection = control.OnClientEvent:Connect(function(id, action, data)
	local ok, result = xpcall(function() return driver.run(action, data) end, debug.traceback)
	control:FireServer("report", id, { ok = ok, data = if ok then result else nil, error = if ok then nil else tostring(result) })
end)
local ok, problem = xpcall(driver.ready, debug.traceback)
if ok then control:FireServer("ready") else control:FireServer("failure", tostring(problem)) end
script.Destroying:Connect(function() connection:Disconnect(); driver.destroy() end)
