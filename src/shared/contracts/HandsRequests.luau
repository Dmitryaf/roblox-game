--!strict
local Requests = {}
local function integer(value: any): boolean
    return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end
function Requests.valid(value: any): boolean
    if type(value) ~= "table" then return false end
    local count = 0
    for key in value do
        count += 1
        if count > 4 or (key ~= "action" and key ~= "requestId" and key ~= "life" and key ~= "position") then return false end
    end
    if not integer(value.life) or not integer(value.requestId) then return false end
    if value.action == "sync" then return value.position == nil end
    if value.action ~= "cast" or typeof(value.position) ~= "Vector3" then return false end
    for _, n in { value.position.X, value.position.Y, value.position.Z } do
        if n ~= n or math.abs(n) > 10000 then return false end
    end
    return true
end
return table.freeze(Requests)
