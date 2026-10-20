--!strict
export type Config = { windup: number, duration: number, cooldown: number, radius: number, range: number,
    slowMultiplier: number, damagePerSecond: number, tickInterval: number }
export type Area = { owner: number, life: number, areaId: number, position: Vector3, radius: number,
    startedAt: number, launchAt: number, expiresAt: number, nextTick: number, kind: string }
export type State = { life: number, alive: boolean, readyAt: number, area: Area? }
local HandArea = {}
function HandArea.new(life: number): State return { life = life, alive = true, readyAt = 0 } end
function HandArea.reason(state: State?, life: number, now: number): string?
    if not state then return "not_ready" end
    if state.life ~= life then return "stale_life" end
    if not state.alive then return "dead" end
    if state.area then return "busy" end
    if now < state.readyAt then return "cooldown" end
    return nil
end
function HandArea.begin(state: State, owner: number, id: number, position: Vector3, now: number, config: Config): Area
    local area: Area = { owner = owner, life = state.life, areaId = id, position = position, radius = config.radius,
        startedAt = now, launchAt = now + config.windup, expiresAt = now + config.windup + config.duration,
        nextTick = now + config.windup + config.tickInterval, kind = "preparing" }
    state.area, state.readyAt = area, now + config.cooldown
    return area
end
-- Sample current occupants once. Missing frames never invent historical occupancy.
function HandArea.tick(area: Area, now: number, interval: number): boolean
    if now < area.nextTick or now > area.expiresAt then return false end
    local completed = math.floor((now - area.launchAt) / interval + 0.000001)
    area.nextTick = area.launchAt + (completed + 1) * interval
    return true
end
return table.freeze(HandArea)
