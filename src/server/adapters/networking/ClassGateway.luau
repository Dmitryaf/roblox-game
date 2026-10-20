--!strict
local Requests = require(game:GetService("ReplicatedStorage").Shared.contracts.ClassRequests)
local ClassGateway = {}
type Limit = { tokens: number, at: number, last: number }

function ClassGateway.new(remote: RemoteEvent, service: any, now: () -> number)
	local limits: { [number]: Limit } = {}
	local connection: RBXScriptConnection? = nil
	local gateway = {}
	function gateway.forget(owner: number) limits[owner] = nil end
	function gateway.sync(player: Player)
		remote:FireClient(player, { kind = "snapshot", state = service.snapshot(player.UserId) })
	end
	function gateway.start()
		if connection then return end
		connection = remote.OnServerEvent:Connect(function(player: Player, request: any)
			local owner, time = player.UserId, now()
			local limit: Limit = limits[owner] or { tokens = 12, at = time, last = -1 }
			limits[owner] = limit
			limit.tokens = math.min(12, limit.tokens + math.max(0, time - limit.at) * 8)
			limit.at = time
			if limit.tokens < 1 then return end
			limit.tokens -= 1
			if not Requests.valid(request) or request.requestId <= limit.last then return end
			limit.last = request.requestId
			local ok, reason = true, nil :: string?
			if request.action == "select" then ok, reason = service.select(owner, request.life, request.classId) end
			remote:FireClient(player, { kind = "reply", requestId = request.requestId, ok = ok,
				reason = reason, state = service.snapshot(owner) })
		end)
	end
	function gateway.destroy()
		if connection then connection:Disconnect(); connection = nil end
		table.clear(limits)
	end
	return gateway
end
return ClassGateway
