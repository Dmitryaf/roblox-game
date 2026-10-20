--!strict
local SwordSwing = require(script.Parent.Parent.Parent.domain.combat.SwordSwing)
type State = SwordSwing.State
type Swing = SwordSwing.Swing
export type Ports = { alive: (number) -> boolean, origin: (number) -> Vector3?, face: (number, Vector3) -> boolean,
    targets: (number, Vector3, number, number) -> { any }, damage: (number, any, number) -> boolean?,
    impact: ((any) -> Vector3?)?, reaction: ((any) -> any)?, onHit: ((number, any, number) -> ())?, emit: (any) -> () }
local MeleeService = {}
function MeleeService.new(ports: Ports, config: SwordSwing.Config, style: string?)
    local states: { [number]: State } = {}
    local paused: { [number]: number } = {}
    local sequence = 0
    local service = {}
    local function event(swing: Swing, kind: string, position: Vector3?, reason: string?): any
        local state = states[swing.owner]
        return { kind = kind, style = style, reason = reason, owner = swing.owner, life = swing.life, swingId = swing.swingId,
            requestId = swing.requestId, direction = swing.direction, position = position, startedAt = swing.startedAt, hitAt = swing.hitAt,
            expiresAt = swing.expiresAt, readyAt = if state then state.readyAt else 0 }
    end
    local function finish(owner: number, reason: string)
        local state = states[owner]
        if not state or not state.swing then return end
        local swing = state.swing; state.swing = nil
        ports.emit(event(swing, "ended", nil, reason))
    end
    function service.join(owner: number, life: number)
        finish(owner, "reset"); states[owner], paused[owner] = SwordSwing.new(life), nil
    end
    function service.leave(owner: number) finish(owner, "left"); states[owner], paused[owner] = nil, nil end
    function service.die(owner: number)
        finish(owner, "dead"); if states[owner] then states[owner].alive = false end
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
            local swing = state.swing
            if not swing then continue end
            if not ports.alive(owner) then service.die(owner); continue end
            if now >= swing.expiresAt then finish(owner, "expired"); continue end
            if swing.kind == "preparing" and now >= swing.hitAt then
                local origin = ports.origin(owner)
                if not origin then finish(owner, "invalid_position"); continue end
                swing.kind = "struck" -- Commit before damage callbacks can re-enter the service.
                ports.emit(event(swing, "struck", origin, nil))
                local seen: { [any]: boolean } = {}
                local contacts = 0
                for _, target in ports.targets(owner, swing.direction, config.range, config.arcDegrees) do
                    if seen[target] or state.swing ~= swing or not state.alive then continue end
                    seen[target] = true
                    local damaged = ports.damage(owner, target, config.damage)
                    if damaged == true and state.swing == swing and state.alive and ports.onHit then ports.onHit(owner, target, now) end
                    local point = if damaged == true and ports.impact then ports.impact(target) else nil
                    if point and state.swing == swing and state.alive then
                        contacts += 1
                        local contact = event(swing, "contact", point, nil)
                        contact.contactId = contacts
                        contact.contactAt, contact.sourcePosition, contact.damageApplied = now, origin, true
                        if ports.reaction then
                            local targetInfo = ports.reaction(target)
                            if targetInfo then contact.targetModel, contact.targetLife = targetInfo.targetModel, targetInfo.targetLife end
                        end
                        ports.emit(contact)
                    end
                end
            end
        end
    end
    function service.cast(owner: number, life: number, direction: Vector3, now: number, requestId: number?): (boolean, string?)
        if paused[owner] ~= nil then return false, "paused" end
        service.step(now)
        local state = states[owner]
        local reason = SwordSwing.reason(state, life, now)
        if reason then return false, reason end
        if not ports.alive(owner) then service.die(owner); return false, "dead" end
        local flat = direction * Vector3.new(1, 0, 1)
        if flat.Magnitude < 0.1 then return false, "invalid_aim" end
        local origin = ports.origin(owner)
        if not origin or not ports.face(owner, flat.Unit) then return false, "invalid_position" end
        sequence += 1
        local accepted = state :: State
        local swing = SwordSwing.begin(accepted, owner, sequence, flat.Unit, now, config)
        swing.requestId = requestId
        ports.emit(event(swing, "preparing", origin, nil))
        return true, nil
    end
    function service.snapshot(owner: number): any
        local state = states[owner]
        local active = {}
        for _, source in states do
            if source.swing then table.insert(active, event(source.swing, source.swing.kind, nil, nil)) end
        end
        return { life = if state then state.life else 0, alive = state ~= nil and state.alive,
            suspended = paused[owner] ~= nil, readyAt = if state then state.readyAt else 0, active = active }
    end
    function service.destroy() for owner in states do service.leave(owner) end end
    return service
end
return MeleeService
