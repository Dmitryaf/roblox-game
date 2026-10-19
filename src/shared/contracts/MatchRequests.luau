--!strict
export type Request = { action: string, requestId: number, matchId: number }
local MatchRequests = {}

local function integer(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end

function MatchRequests.valid(value: any): boolean
	if type(value) ~= "table" then return false end
	local count = 0
	for key in value do
		count += 1
		if count > 3 or (key ~= "action" and key ~= "requestId" and key ~= "matchId") then return false end
	end
	if not integer(value.requestId) or not integer(value.matchId) then return false end
	return value.action == "sync" or value.action == "ready" or value.action == "cancel" or value.action == "exit"
end

return table.freeze(MatchRequests)
