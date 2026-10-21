--!strict
local Sector = require(script.Parent.Parent.Parent.domain.combat.ArrowInterception)
local ArrowInterceptService = {}
function ArrowInterceptService.new(ports: any, config: any)
    return function(caster: number, position: Vector3, delta: Vector3, from: number, untilAt: number): any
        local first: any = nil
        for _, swing in ports.swings() do
            if swing.owner == caster or not ports.allowed(caster, swing.owner) or not ports.alive(swing.owner) then continue end
            local origin = ports.origin(swing.owner)
            if not origin then continue end
            local fraction = Sector.fraction(position, delta, from, untilAt, origin - Vector3.yAxis,
                swing.direction, swing.hitAt, config.window, config.range, config.arcDegrees)
            if fraction and ports.visible(swing.owner, position + delta * fraction) and (not first or fraction < first.fraction
                or (fraction == first.fraction and swing.owner < first.owner)) then
                first = { owner = swing.owner, life = swing.life, direction = swing.direction,
                    swingId = swing.swingId, fraction = fraction }
            end
        end
        return first
    end
end
return ArrowInterceptService
