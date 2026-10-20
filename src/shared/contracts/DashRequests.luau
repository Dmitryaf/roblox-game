--!strict
local Requests = require(script.Parent.Requests)
local DashRequests = {}
function DashRequests.valid(value: any): boolean
    return Requests.valid(value) and (value.action == "cast" or value.action == "sync")
end
return table.freeze(DashRequests)
