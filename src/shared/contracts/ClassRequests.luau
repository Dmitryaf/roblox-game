--!strict
local ClassRequests = {}
local function integer(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end
function ClassRequests.valid(value: any): boolean
	if type(value) ~= "table" then return false end
	local count = 0
	for key in value do
		count += 1
		if count > 4 or (key ~= "action" and key ~= "requestId" and key ~= "life" and key ~= "classId") then return false end
	end
	if not integer(value.requestId) or not integer(value.life) then return false end
	if value.action == "sync" then return value.classId == nil end
	return value.action == "select" and (value.classId == "warlock" or value.classId == "warrior")
end
return table.freeze(ClassRequests)
