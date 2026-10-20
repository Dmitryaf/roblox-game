--!strict
local ArrowRequests = require(script.Parent.Requests)
local MeleeRequests = {}
function MeleeRequests.valid(value: any): boolean
    return ArrowRequests.valid(value) and (value.action == "cast" or value.action == "sync")
end
return table.freeze(MeleeRequests)
