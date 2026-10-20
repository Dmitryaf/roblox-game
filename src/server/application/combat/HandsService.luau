--!strict
local HandArea = require(script.Parent.Parent.Parent.domain.combat.HandArea)
type Config = HandArea.Config
type State = HandArea.State
type Area = HandArea.Area
export type Ports = { alive: (number) -> boolean,
    placement: (number, Vector3, number, number) -> (Vector3?, string?),
    targets: (number, Vector3, number) -> { any }, damage: (number, any, number) -> (),
    slow: (any, number) -> (), emit: (any) -> () }
local HandsService = {}
function HandsService.new(ports: Ports, config: Config)
    local states: { [number]: State } = {}
    local paused: { [number]: number } = {}
    local slowed: { [any]: boolean } = {}
    local transfers: { [number]: { area: Area, fromPosition: Vector3, startedAt: number, readyAt: number } } = {}
    local sequence = 0
    local service = {}
    local function event(area: Area, kind: string, reason: string?): any
        local state = states[area.owner]
        local pending = transfers[area.owner]
        local transfer = if pending and pending.area == area then pending else nil
        return { kind = kind, reason = reason, owner = area.owner, life = area.life, areaId = area.areaId,
            position = area.position, radius = area.radius, startedAt = area.startedAt, launchAt = area.launchAt,
            expiresAt = area.expiresAt, readyAt = if state then state.readyAt else 0,
            fromPosition = if transfer then transfer.fromPosition else nil,
            transferStartedAt = if transfer then transfer.startedAt else nil,
            transferReadyAt = if transfer then transfer.readyAt else nil }
    end
    local function finish(owner: number, reason: string)
        local state = states[owner]
        if not state or not state.area then return end
        local area = state.area
        state.area = nil -- Remove before notifications or damage callbacks can re-enter.
        local ended = event(area, "ended", reason)
        transfers[owner] = nil
        ports.emit(ended)
    end
    local function refreshSlow()
        local current: { [any]: boolean } = {}
        for owner, state in states do
            local area = state.area
            if area and area.kind == "active" and state.alive and ports.alive(owner) and paused[owner] == nil then
                for _, target in ports.targets(owner, area.position, area.radius) do current[target] = true end
            end
        end
        for target in slowed do if not current[target] then ports.slow(target, 1) end end
        for target in current do ports.slow(target, config.slowMultiplier) end
        slowed = current
    end
    function service.join(owner: number, life: number)
        finish(owner, "reset")
        paused[owner], states[owner] = nil, HandArea.new(life)
        refreshSlow()
    end
    function service.leave(owner: number)
        finish(owner, "left"); paused[owner], states[owner] = nil, nil
        refreshSlow()
    end
    function service.die(owner: number)
        finish(owner, "dead")
        if states[owner] then states[owner].alive = false end
        refreshSlow()
    end
    function service.pause(owner: number, now: number)
        if paused[owner] ~= nil then return end
        paused[owner] = now; finish(owner, "paused"); refreshSlow()
    end
    function service.resume(owner: number, now: number)
        local at = paused[owner]
        if at == nil then return end
        local state = states[owner]
        if state then state.readyAt += math.max(0, now - at) end
        paused[owner] = nil
    end
    function service.step(now: number)
        for owner, state in states do
            local area = state.area
            if not area then continue end
            if not ports.alive(owner) then service.die(owner); continue end
            -- A normal frame can cross the final tick and expiry together. Resolve at most
            -- that one final sample; a stalled frame beyond an interval cannot invent history.
            local warming = area.kind ~= "active"
            if now > area.expiresAt + config.tickInterval or (now > area.expiresAt and warming) then
                finish(owner, "expired"); continue
            end
            if now >= area.launchAt then
                if area.kind == "preparing" or area.kind == "transferring" then
                    area.kind = "active"; ports.emit(event(area, "active", nil))
                end
                if HandArea.tick(area, math.min(now, area.expiresAt), config.tickInterval) then
                    local seen: { [any]: boolean } = {}
                    for _, target in ports.targets(owner, area.position, area.radius) do
                        if seen[target] or state.area ~= area or not state.alive then continue end
                        seen[target] = true
                        ports.damage(owner, target, config.damagePerSecond * config.tickInterval)
                    end
                end
                if state.area == area and now >= area.expiresAt then finish(owner, "expired") end
            end
        end
        refreshSlow()
    end
    function service.cast(owner: number, life: number, position: Vector3, now: number): (boolean, string?)
        if paused[owner] ~= nil then return false, "paused" end
        service.step(now)
        local state = states[owner]
        local reason = HandArea.reason(state, life, now)
        if reason then return false, reason end
        if not ports.alive(owner) then service.die(owner); return false, "dead" end
        local point, placementReason = ports.placement(owner, position, config.range, config.radius)
        if not point then return false, placementReason or "invalid_target" end
        sequence += 1
        local accepted = state :: State
        local area = HandArea.begin(accepted, owner, sequence, point, now, config)
        ports.emit(event(area, "preparing", nil))
        return true, nil
    end
    function service.snapshot(owner: number): any
        local state = states[owner]
        local active = {}
        for _, source in states do
            if source.area then table.insert(active, event(source.area, source.area.kind, nil)) end
        end
        return { life = if state then state.life else 0, alive = state ~= nil and state.alive,
            suspended = paused[owner] ~= nil, readyAt = if state then state.readyAt else 0, active = active }
    end
    -- Planning does not tick or consume either resource. The combination owner commits
    -- this closure immediately after detaching the arrow, without yielding or emitting.
    function service.planTransfer(owner: number, life: number, position: Vector3, now: number): ((() -> ())?, string?)
        if paused[owner] ~= nil then return nil, "paused" end
        local state = states[owner]
        if not state then return nil, "not_ready" end
        if state.life ~= life then return nil, "stale_life" end
        if not state.alive or not ports.alive(owner) then return nil, "dead" end
        local area = state.area
        if not area then return nil, "no_area" end
        if now >= area.expiresAt then return nil, "expired" end
        if area.kind ~= "active" then return nil, "busy" end
        local readyAt = now + 0.35
        if readyAt >= area.expiresAt then return nil, "expiring_area" end
        local point, reason = ports.placement(owner, position, config.range, config.radius)
        if not point then return nil, reason or "invalid_target" end
        -- Placement ports are non-yielding, but reject a re-entrant lifecycle change.
        if states[owner] ~= state or state.area ~= area or not state.alive or paused[owner] ~= nil then return nil, "stale_area" end
        local function commit()
            transfers[owner] = { area = area, fromPosition = area.position, startedAt = now, readyAt = readyAt }
            area.position, area.kind = point, "transferring"
            area.launchAt, area.nextTick = readyAt, readyAt + config.tickInterval
            -- The same area/source owns both positions. No old slow contribution survives.
            refreshSlow()
            ports.emit(event(area, "transferring", nil))
        end
        return commit, nil
    end
    function service.destroy()
        for owner in states do service.leave(owner) end
        for target in slowed do ports.slow(target, 1) end
        table.clear(slowed)
    end
    return service
end
return HandsService
