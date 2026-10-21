--!strict
-- Owns reservations and raised-cover lifetime. Every world port is non-yielding.
export type Area = { owner: number, life: number, areaId: number, slotId: number, kind: string,
    position: Vector3, startedAt: number, launchAt: number, expiresAt: number }
type State = { life: number, alive: boolean, readyAt: number, area: Area? }
export type Ports = {
    alive: (number) -> boolean,
    choose: (number, Vector3) -> (number?, string?), position: (number) -> Vector3,
    clearForRaise: (number) -> boolean, show: (Area, string) -> (), remove: (Area, string) -> (),
    reset: (number) -> (), targetSlot: (any) -> number?,
    strikeTargets: (number, Vector3, number, number) -> { number }, emit: (any) -> (),
}
export type Config = { windup: number, duration: number, cooldown: number,
    strikeRange: number, strikeArcDegrees: number }
local CoverService = {}
function CoverService.new(ports: Ports, config: Config)
    local states: { [number]: State } = {}
    local slots: { [number]: Area } = {}
    local paused: { [number]: number } = {}
    local sequence = 0
    local service = {}
    local function event(area: Area, kind: string, reason: string?): any
        local state = states[area.owner]
        return { kind = kind, reason = reason, owner = area.owner, life = area.life, areaId = area.areaId,
            slotId = area.slotId, position = area.position, startedAt = area.startedAt, launchAt = area.launchAt,
            expiresAt = area.expiresAt, readyAt = if state then state.readyAt else 0 }
    end
    local function finish(owner: number, reason: string)
        local state = states[owner]
        local area = if state then state.area else nil
        if not area then return end
        state.area = nil
        if slots[area.slotId] == area then slots[area.slotId] = nil end
        ports.remove(area, reason)
        ports.emit(event(area, "ended", reason))
    end
    function service.join(owner: number, life: number)
        finish(owner, "reset"); ports.reset(owner)
        states[owner], paused[owner] = { life = life, alive = true, readyAt = 0 }, nil
    end
    function service.leave(owner: number)
        finish(owner, "left"); ports.reset(owner); states[owner], paused[owner] = nil, nil
    end
    function service.die(owner: number)
        finish(owner, "dead"); ports.reset(owner)
        if states[owner] then states[owner].alive = false end
    end
    function service.pause(owner: number, now: number)
        if paused[owner] ~= nil then return end
        paused[owner] = now; finish(owner, "paused"); ports.reset(owner)
    end
    function service.resume(owner: number, now: number)
        local at, state = paused[owner], states[owner]
        if at == nil then return end
        if state then state.readyAt += math.max(0, now - at) end
        paused[owner] = nil
    end
    function service.step(now: number)
        for owner, state in states do
            local area = state.area
            if not area then continue end
            if not state.alive or not ports.alive(owner) then service.die(owner); continue end
            if now >= area.expiresAt then finish(owner, "expired"); continue end
            if area.kind == "preparing" and now >= area.launchAt then
                local clear = ports.clearForRaise(area.slotId)
                if states[owner] ~= state or state.area ~= area or paused[owner] ~= nil then continue end
                if not clear then finish(owner, "occupied"); continue end
                area.kind = "active"
                ports.show(area, "active")
                if state.area == area then ports.emit(event(area, "active", nil)) end
            end
        end
    end
    function service.cast(owner: number, life: number, aim: Vector3, now: number): (boolean, string?)
        if paused[owner] ~= nil then return false, "paused" end
        service.step(now)
        local state = states[owner]
        if not state then return false, "not_ready" end
        if state.life ~= life then return false, "stale_life" end
        if not state.alive or not ports.alive(owner) then service.die(owner); return false, "dead" end
        if state.area then return false, "busy" end
        if now < state.readyAt then return false, "cooldown" end
        local slot, reason = ports.choose(owner, aim)
        if not slot then return false, reason or "invalid_target" end
        if states[owner] ~= state or not state.alive or paused[owner] ~= nil then return false, "stale_life" end
        if slots[slot] then return false, "occupied" end
        if not ports.clearForRaise(slot) then return false, "occupied" end
        if states[owner] ~= state or not state.alive or state.area or paused[owner] ~= nil then return false, "stale_life" end
        sequence += 1
        local area: Area = { owner = owner, life = life, areaId = sequence, slotId = slot, kind = "preparing",
            position = ports.position(slot), startedAt = now, launchAt = now + config.windup,
            expiresAt = now + config.windup + config.duration }
        state.area, state.readyAt, slots[slot] = area, now + config.cooldown, area
        ports.show(area, "preparing")
        if state.area == area then ports.emit(event(area, "preparing", nil)) end
        return true, nil
    end
    function service.hit(target: any, now: number): boolean
        service.step(now)
        local slot = ports.targetSlot(target)
        local area = if slot then slots[slot] else nil
        if not area or area.kind ~= "active" then return false end
        finish(area.owner, "shattered")
        return true
    end
    function service.strike(owner: number, direction: Vector3, now: number): number
        service.step(now)
        local state = states[owner]
        if not state or not state.alive or paused[owner] ~= nil or not ports.alive(owner) then return 0 end
        local count = 0
        for _, slot in ports.strikeTargets(owner, direction, config.strikeRange, config.strikeArcDegrees) do
            if states[owner] ~= state or not state.alive or paused[owner] ~= nil then break end
            local area = slots[slot]
            if area and area.kind == "active" then finish(area.owner, "shattered"); count += 1 end
        end
        return count
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
    function service.destroy() for owner in states do service.leave(owner) end end
    return service
end
return CoverService
