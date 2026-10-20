--!strict
export type Request = { action: string, requestId: number, life: number, castId: number?, direction: Vector3? }
local Requests = {}

local function integer(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end

function Requests.valid(value: any): boolean
	if type(value) ~= "table" then return false end
	local count = 0
	for key in value do
		count += 1
		if count > 5 or (key ~= "action" and key ~= "requestId" and key ~= "life" and key ~= "castId" and key ~= "direction") then
			return false
		end
	end
	if not integer(value.requestId) or not integer(value.life) then return false end
	if value.action == "sync" then return value.direction == nil and value.castId == nil end
	if value.action == "teleport" or value.action == "transfer" then return integer(value.castId) and value.direction == nil end
	if value.action ~= "cast" or value.castId ~= nil or typeof(value.direction) ~= "Vector3" then return false end
	local v = value.direction
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or math.abs(n) > 1.01 then return false end
	end
	return v.Magnitude > 0.99 and v.Magnitude < 1.01
end

return table.freeze(Requests)
