--!strict
local Arrow = require(script.Parent.Parent.Parent.domain.combat.Arrow)
type State = Arrow.State
type Cast = Arrow.Cast
export type Projectile = { cast: Cast, position: Vector3?, direction: Vector3, sampledAt: number }
export type Ports = {
	origin: (number) -> Vector3?,
	alive: (number) -> boolean,
	sweep: (number, Vector3, Vector3, number) -> (Vector3?, any),
	damage: (number, any, number) -> boolean?,
	impact: ((any) -> any)?,
	landing: (number, Vector3, Vector3) -> Vector3?,
	move: (number, Vector3) -> (),
	emit: (any) -> (),
}
export type Config = { windup: number, lifetime: number, cooldown: number, speed: number, damage: number, radius: number }

local ArrowService = {}
function ArrowService.new(ports: Ports, config: Config)
	local states: { [number]: State } = {}
	local projectiles: { [number]: Projectile } = {}
	local paused: { [number]: number } = {}
	local sequence = 0
	local service = {}

	local function remove(owner: number, reason: string, position: Vector3?): any
		local state = states[owner]
		local cast = if state then state.cast else nil
		if not cast then return end
		projectiles[owner] = nil
		Arrow.cancel(state)
		return { kind = "ended", owner = owner, life = cast.life, castId = cast.id, requestId = cast.requestId,
			reason = reason, position = position }
	end
	local function finish(owner: number, reason: string, position: Vector3?)
		local ended = remove(owner, reason, position)
		if ended then ports.emit(ended) end
	end

	function service.join(owner: number, life: number)
		finish(owner, "reset", nil)
		paused[owner] = nil
		states[owner] = Arrow.new(life)
	end

	function service.leave(owner: number)
		finish(owner, "left", nil)
		states[owner] = nil
		paused[owner] = nil
	end
	function service.pause(owner: number, now: number)
		if paused[owner] then return end
		finish(owner, "paused", nil)
		paused[owner] = now
	end
	function service.resume(owner: number, now: number)
		local at = paused[owner]
		if at == nil then return end
		local state = states[owner]
		if state then state.readyAt += math.max(0, now - at) end
		paused[owner] = nil
	end

	function service.die(owner: number)
		finish(owner, "dead", nil)
		if states[owner] then Arrow.die(states[owner]) end
	end

	function service.step(now: number)
		for owner, projectile in projectiles do
			local cast = projectile.cast
			if not ports.alive(owner) then
				service.die(owner)
				continue
			end
			if now < cast.launchAt then continue end
			if not projectile.position then
				local origin = ports.origin(owner)
				if not origin then finish(owner, "invalid_position", nil); continue end
				projectile.position = origin
				cast.phase = "flying"
				ports.emit({ kind = "launched", owner = owner, life = cast.life, castId = cast.id,
					position = origin, direction = projectile.direction, speed = config.speed,
					launchAt = cast.launchAt, expiresAt = cast.expiresAt })
			end
			local position = projectile.position :: Vector3
			local untilTime = math.min(now, cast.expiresAt)
			local distance = math.max(0, untilTime - projectile.sampledAt) * config.speed
			if distance > 0 then
				local delta = projectile.direction * distance
				local hit, target = ports.sweep(owner, position, delta, config.radius)
				local sampledAt = projectile.sampledAt
				projectile.sampledAt = untilTime
				if hit then
					-- Remove before damage: death callbacks and repeats cannot apply this hit again.
					local ended = remove(owner, "hit", hit)
					if ended then
						ended.sourcePosition = position
						ended.contactAt = sampledAt + math.clamp((hit - position).Magnitude / config.speed, 0, untilTime - sampledAt)
						local damaged = if target then ports.damage(owner, target, config.damage) else nil
						ended.damageApplied = damaged == true
						local impact = if damaged == true and ports.impact then ports.impact(target) else nil
						if impact then ended.targetModel, ended.targetLife = impact.targetModel, impact.targetLife end
						ports.emit(ended)
					end
					continue
				end
				projectile.position = position + delta
			end
			if now >= cast.expiresAt then finish(owner, "expired", projectile.position) end
		end
	end

	function service.cast(owner: number, life: number, direction: Vector3, now: number, requestId: number?): (boolean, string?)
		if paused[owner] ~= nil then return false, "paused" end
		service.step(now)
		local state = states[owner]
		if not state then return false, "not_ready" end
		if not ports.alive(owner) then service.die(owner); return false, "dead" end
		if not ports.origin(owner) then return false, "invalid_position" end
		sequence += 1
		local cast, reason = Arrow.begin(state, owner, life, sequence, now, config.windup, config.lifetime, config.cooldown)
		if not cast then return false, reason end
		cast.requestId = requestId
		projectiles[owner] = { cast = cast, position = nil, direction = direction, sampledAt = cast.launchAt }
		ports.emit({ kind = "preparing", owner = owner, life = life, castId = cast.id,
			requestId = requestId, direction = direction, startedAt = now, launchAt = cast.launchAt, expiresAt = cast.expiresAt, readyAt = state.readyAt })
		return true, nil
	end

	function service.teleport(owner: number, life: number, castId: number, now: number): (boolean, string?)
		if paused[owner] ~= nil then return false, "paused" end
		-- Resolve swept hits/expiry/death up to request time before granting movement.
		service.step(now)
		local state = states[owner]
		if not state then return false, "not_ready" end
		local allowed, reason = Arrow.canTeleport(state, owner, life, castId, now)
		if not allowed then return false, reason end
		local projectile = projectiles[owner]
		if not projectile or not projectile.position then return false, "stale_arrow" end
		local destination = ports.landing(owner, projectile.position, projectile.direction)
		if not destination then return false, "blocked" end
		-- Ports must not yield; validation, consumption and movement form one transaction.
		finish(owner, "teleported", destination)
		ports.move(owner, destination)
		return true, nil
	end

	-- Internal server ports for the explicit hands/arrow combination. Callers must not
	-- yield between planning and consumption, just like the ordinary teleport path.
	function service.flying(owner: number, life: number, castId: number, now: number): (Projectile?, string?)
		if paused[owner] ~= nil then return nil, "paused" end
		service.step(now)
		local state = states[owner]
		if not state then return nil, "not_ready" end
		local allowed, reason = Arrow.canTeleport(state, owner, life, castId, now)
		if not allowed then return nil, reason end
		local projectile = projectiles[owner]
		if not projectile or not projectile.position then return nil, "stale_arrow" end
		return projectile, nil
	end
	function service.consume(owner: number, projectile: Projectile, commit: (() -> ())?): boolean
		if projectiles[owner] ~= projectile then return false end
		local ended = remove(owner, "hands_transferred", projectile.position)
		if commit then commit() end
		if ended then ports.emit(ended) end
		return true
	end

	function service.snapshot(owner: number)
		local state = states[owner]
		local active = {}
		for id, projectile in projectiles do
			local cast = projectile.cast
			table.insert(active, { kind = cast.phase, owner = id, life = cast.life, castId = cast.id, requestId = cast.requestId,
				position = projectile.position, direction = projectile.direction, speed = config.speed,
				startedAt = cast.launchAt - config.windup, launchAt = cast.launchAt, expiresAt = cast.expiresAt, sampledAt = projectile.sampledAt })
		end
		return { life = if state then state.life else 0, alive = state ~= nil and state.alive, suspended = paused[owner] ~= nil,
			readyAt = if state then state.readyAt else 0, active = active }
	end

	function service.destroy()
		for owner in states do service.leave(owner) end
	end
	return service
end

return ArrowService
