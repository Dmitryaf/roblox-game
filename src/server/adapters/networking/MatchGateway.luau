--!strict
local Requests = require(game:GetService("ReplicatedStorage").Shared.contracts.MatchRequests)
local MatchGateway = {}
type Limit = { tokens: number, at: number, last: number }
function MatchGateway.new(remote: RemoteEvent, matches: any, now: () -> number, tick: () -> (), available: (number) -> boolean)
	local limits: { [number]: Limit } = {}
	local connection: RBXScriptConnection? = nil
	local gateway = {}
	function gateway.forget(owner: number) limits[owner] = nil end
	function gateway.sync(player: Player)
		remote:FireClient(player, { kind = "snapshot", state = matches.snapshot(player.UserId, now()) })
	end
	function gateway.start()
		connection = remote.OnServerEvent:Connect(function(player: Player, request: any)
			local owner, time = player.UserId, now()
			local limit: Limit = limits[owner] or { tokens = 10, at = time, last = -1 }
			limits[owner] = limit
			limit.tokens = math.min(10, limit.tokens + math.max(0, time - limit.at) * 5)
			limit.at = time
			if limit.tokens < 1 then return end
			limit.tokens -= 1
			if not Requests.valid(request) or request.requestId <= limit.last then return end
			limit.last = request.requestId
			tick()
			if request.action == "sync" then
				remote:FireClient(player, { kind = "reply", requestId = request.requestId, ok = true, state = matches.snapshot(owner, time) })
				return
			end
			local current = matches.snapshot(owner, time)
			local ok: boolean, reason: string? = false, "stale_match"
			if request.matchId == current.matchId then
				if request.action == "ready" and not available(owner) then reason = "not_ready"
				elseif request.action == "exit" then ok, reason = matches.exit(owner, time)
				else ok, reason = matches.ready(owner, request.action == "ready", time) end
			end
			remote:FireClient(player, { kind = "reply", requestId = request.requestId, ok = ok, reason = reason,
				state = matches.snapshot(owner, time) })
		end)
	end
	function gateway.destroy()
		if connection then connection:Disconnect(); connection = nil end
		table.clear(limits)
	end
	return gateway
end
return MatchGateway
