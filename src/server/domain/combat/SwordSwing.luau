--!strict
export type Config = { windup: number, recovery: number, cooldown: number, range: number, arcDegrees: number, damage: number }
export type Swing = { owner: number, life: number, swingId: number, direction: Vector3, startedAt: number,
    hitAt: number, expiresAt: number, kind: string }
export type State = { life: number, alive: boolean, readyAt: number, swing: Swing? }
local SwordSwing = {}
function SwordSwing.new(life: number): State return { life = life, alive = true, readyAt = 0 } end
function SwordSwing.reason(state: State?, life: number, now: number): string?
    if not state then return "not_ready" end
    if state.life ~= life then return "stale_life" end
    if not state.alive then return "dead" end
    if state.swing then return "busy" end
    if now < state.readyAt then return "cooldown" end
    return nil
end
function SwordSwing.begin(state: State, owner: number, id: number, direction: Vector3, now: number, config: Config): Swing
    local swing = { owner = owner, life = state.life, swingId = id, direction = direction,
        startedAt = now, hitAt = now + config.windup, expiresAt = now + config.windup + config.recovery, kind = "preparing" }
    state.swing, state.readyAt = swing, now + config.cooldown
    return swing
end
return table.freeze(SwordSwing)
