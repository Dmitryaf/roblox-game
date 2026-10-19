--!strict
local Requests = require("../../build/test-source/shared/contracts/MatchRequests")
for _, action in { "sync", "ready", "cancel", "exit" } do
	assert(Requests.valid({ action = action, requestId = 0, matchId = 2147483647 }))
end
for _, value in { -1, 0.5, math.huge, -math.huge, 0 / 0, 2147483648, "1" } do
	assert(not Requests.valid({ action = "ready", requestId = value, matchId = 1 }))
	assert(not Requests.valid({ action = "ready", requestId = 1, matchId = value }))
end
assert(not Requests.valid(nil))
assert(not Requests.valid({ action = "win", requestId = 1, matchId = 1 }))
assert(not Requests.valid({ action = "ready", requestId = 1 }))
assert(not Requests.valid({ action = "ready", requestId = 1, matchId = 1, team = 1 }))
assert(not Requests.valid({ action = "ready", requestId = 1, matchId = 1, [1] = "extra" }))
print("PASS match request schema: 4 actions, integer bounds, missing/unknown/forged fields")
