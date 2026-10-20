--!strict
-- Pure lifecycle; no Instances, clocks, networking or spatial authority here.
export type Cast = {
	id: number, owner: number, life: number,
	launchAt: number, expiresAt: number, phase: string, requestId: number?,
}
export type State = {
	life: number, alive: boolean, readyAt: number, cast: Cast?,
}

local Arrow = {}

function Arrow.new(life: number): State
	return { life = life, alive = true, readyAt = 0, cast = nil }
end

function Arrow.begin(state: State, owner: number, life: number, id: number, now: number,
	windup: number, lifetime: number, cooldown: number): (Cast?, string?)
	if life ~= state.life then return nil, "stale_life" end
	if not state.alive then return nil, "dead" end
	if state.cast then return nil, "busy" end
	if now < state.readyAt then return nil, "cooldown" end
	local cast: Cast = {
		id = id, owner = owner, life = life, phase = "preparing",
		launchAt = now + windup, expiresAt = now + windup + lifetime,
	}
	state.cast = cast
	state.readyAt = now + cooldown
	return cast, nil
end

function Arrow.canTeleport(state: State, owner: number, life: number, id: number, now: number): (boolean, string?)
	if life ~= state.life then return false, "stale_life" end
	if not state.alive then return false, "dead" end
	local cast = state.cast
	if not cast or cast.id ~= id or cast.owner ~= owner or cast.life ~= life then
		return false, "stale_arrow"
	end
	if now >= cast.expiresAt then return false, "expired" end
	if cast.phase ~= "flying" then return false, "preparing" end
	return true, nil
end

function Arrow.cancel(state: State)
	state.cast = nil
end

function Arrow.die(state: State)
	state.alive = false
	Arrow.cancel(state)
end

return table.freeze(Arrow)
