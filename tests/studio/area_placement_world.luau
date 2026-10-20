--!strict
-- Actual spatial queries; catches support rays that start inside a tall wall.
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local AreaWorld = require(modules.adapters.world.AreaWorld)
local folder = Instance.new("Folder")
folder.Name, folder.Parent = "AreaFootprintFixture", workspace
local center = Vector3.new(1000, 200, 1000)
local function part(size: Vector3, at: Vector3, parent: Instance?): Part
	local value = Instance.new("Part")
	value.Size, value.Position, value.Anchored, value.CanCollide = size, at, true, true
	value.Parent = parent or folder
	return value
end
part(Vector3.new(80, 2, 80), center - Vector3.yAxis)
local area = AreaWorld.new({ origin = function() return center + Vector3.yAxis * 4 end }, {
	contains = function() return true end, allowed = function() return true end,
	barrier = function() return nil end,
})
local ok, problem = xpcall(function()
	local clear = area.placement(1, center, 30, 8)
	assert(clear ~= nil and (clear - center).Magnitude < 0.01, "Clear supported circle refused")
	local wall = part(Vector3.new(2, 9, 30), center + Vector3.new(8, 4.5, 0))
	local denied, reason = area.placement(1, center, 30, 8)
	assert(denied == nil and reason == "invalid_target", "Tall wall inside footprint was hidden by inside-origin support rays")
	wall:Destroy()
	local outside = part(Vector3.new(0.5, 4, 0.5), center + Vector3.new(7, 2, 7))
	assert(area.placement(1, center, 30, 8) ~= nil, "A square-query corner outside the circle caused a false wall refusal")
	outside:Destroy()
	local npc = Instance.new("Model"); npc.Parent = folder
	part(Vector3.new(2, 4, 2), center + Vector3.new(2, 2, 0), npc)
	local humanoid = Instance.new("Humanoid"); humanoid.Parent = npc
	assert(area.placement(1, center, 30, 8) ~= nil, "A target body was mistaken for static terrain")
	print("PASS Area footprint: clear support, tall occupied wall rejection, outside-circle negative control, live-target exclusion")
end, debug.traceback)
folder:Destroy()
assert(ok, tostring(problem))
return true
