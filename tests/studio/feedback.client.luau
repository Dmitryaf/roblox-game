--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local control = ReplicatedStorage:WaitForChild("FeedbackTestControl", 20) :: RemoteEvent
local loadModule = require :: any
local Driver: any = loadModule(ReplicatedStorage:WaitForChild("FeedbackTestDriver", 20) :: ModuleScript)
local Probe: any = loadModule(ReplicatedStorage:WaitForChild("FeedbackProbe", 20) :: ModuleScript)
local player = Players.LocalPlayer
local driver, probe = Driver.new(player), Probe.new(player)
local seen: { [Instance]: boolean } = {}
local names: { [string]: string } = { WarriorSwing = "melee", WarriorHeavySwing = "heavy", DemonicArrow = "arrow" }
local visual = workspace.DescendantAdded:Connect(function(object: Instance)
	local ability = names[object.Name]
	if ability and object:IsA("BasePart") and not seen[object] then
		seen[object] = true
		probe.mark("visual_release", { ability = ability, name = object.Name })
	end
end)
local connection = control.OnClientEvent:Connect(function(id, action, data)
	local ok, result = xpcall(function()
		if action == "feedbackMark" then return probe.mark(data.label, data.data) end
		if action == "feedbackInspect" then
			local report = probe.inspect()
			if data and data.since then
				for _, field in { "events", "samples", "inputs" } do
					local retained = {}
					for _, item in report[field] do if item.at >= data.since then table.insert(retained, item) end end
					report[field] = retained
				end
			end
			return { probe = report, driver = driver.run("inspect") }
		end
		return driver.run(action, data)
	end, debug.traceback)
	control:FireServer("report", id, { ok = ok, data = if ok then result else nil, error = if ok then nil else tostring(result) })
end)
local ok, problem = xpcall(driver.ready, debug.traceback)
if ok then control:FireServer("ready") else control:FireServer("failure", tostring(problem)) end
script.Destroying:Connect(function() connection:Disconnect(); visual:Disconnect(); driver.destroy(); probe.destroy(); table.clear(seen) end)
