--!strict
-- One frame owner restores overlays backwards, then applies them above the Animator.
local RunService = game:GetService("RunService")
local Layers = {}
function Layers.new(layers: { any })
	local stopped = false
	local function restore()
		for index = #layers, 1, -1 do layers[index].beforePose() end
	end
	local animation = RunService.PreAnimation:Connect(restore)
	local simulation = RunService.PreSimulation:Connect(function(delta: number)
		if stopped then return end
		restore()
		local now = workspace:GetServerTimeNow()
		for _, layer in layers do layer.afterPose(now, delta) end
	end)
	return { destroy = function()
		if stopped then return end
		stopped = true; animation:Disconnect(); simulation:Disconnect(); restore()
	end }
end
return Layers
