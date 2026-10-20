--!strict
export type Config = { distance: number, duration: number, cooldown: number }
export type Ports = {
    alive: (number) -> boolean,
    start: (number, Vector3, number, number, number?) -> (Vector3?, number?, string?),
    stop: (number, string) -> (), emit: (any) -> (),
}
type State = { life: number, alive: boolean, readyAt: number, dash: any? }
local DashService = {}
function DashService.new(ports: Ports, config: Config)
    local states: { [number]: State } = {}
    local paused: { [number]: number } = {}
    local sequence = 0
    local service = {}
    local function event(dash: any, kind: string, reason: string?): any
        local result = table.clone(dash)
        result.kind, result.reason = kind, reason
        return result
    end
    local function finish(owner: number, reason: string)
        local state = states[owner]
        if not state or not state.dash then return end
        local dash = state.dash
        state.dash = nil -- Clear before world/emission callbacks can re-enter.
        ports.stop(owner, reason)
        ports.emit(event(dash, "ended", reason))
    end
    function service.join(owner: number, life: number)
        finish(owner, "reset")
        states[owner], paused[owner] = { life = life, alive = true, readyAt = 0, dash = nil }, nil
    end
    function service.leave(owner: number)
        finish(owner, "left"); states[owner], paused[owner] = nil, nil
    end
    function service.die(owner: number)
        finish(owner, "dead")
        if states[owner] then states[owner].alive = false end
    end
    function service.pause(owner: number, now: number)
        if paused[owner] ~= nil then return end
        paused[owner] = now; finish(owner, "paused")
    end
    function service.resume(owner: number, now: number)
        local at, state = paused[owner], states[owner]
        if at == nil then return end
        if state then state.readyAt += math.max(0, now - at) end
        paused[owner] = nil
    end
    function service.step(now: number)
        for owner, state in states do
            if not state.dash then continue end
            if not ports.alive(owner) then service.die(owner)
            elseif now >= state.dash.expiresAt then finish(owner, "expired") end
        end
    end
    function service.cast(owner: number, life: number, direction: Vector3, now: number, requestId: number?): (boolean, string?)
        service.step(now)
        local state = states[owner]
        if not state then return false, "not_ready" end
        if state.life ~= life then return false, "stale_life" end
        if not state.alive or not ports.alive(owner) then service.die(owner); return false, "dead" end
        if paused[owner] ~= nil then return false, "paused" end
        if state.dash then return false, "busy" end
        if now < state.readyAt then return false, "cooldown" end
        local flat = direction * Vector3.new(1, 0, 1)
        if flat.Magnitude ~= flat.Magnitude or flat.Magnitude < 0.1 or flat.Magnitude == math.huge then return false, "invalid_aim" end
        local position, distance, reason = ports.start(owner, flat.Unit, config.distance, config.duration, requestId)
        if not position or not distance then return false, reason or "blocked" end
        sequence += 1
        state.readyAt = now + config.cooldown
        local duration = config.duration * distance / config.distance
        local dash = { owner = owner, life = life, dashId = sequence, requestId = requestId, direction = flat.Unit,
            position = position, distance = distance, duration = duration, speed = config.distance / config.duration,
            startedAt = now, expiresAt = now + duration, readyAt = state.readyAt }
        state.dash = dash
        ports.emit(event(dash, "started", nil))
        return true, nil
    end
    function service.snapshot(owner: number): any
        local state = states[owner]
        local active = {}
        for _, source in states do
            if source.dash then table.insert(active, event(source.dash, "started", nil)) end
        end
        return { life = if state then state.life else 0, alive = state ~= nil and state.alive,
            suspended = paused[owner] ~= nil, readyAt = if state then state.readyAt else 0, active = active }
    end
    function service.destroy() for owner in states do service.leave(owner) end end
    return service
end
return DashService
