--!strict
-- Clip a swept arrow against a timed, forward sword sector. No frame sampling:
-- a long frame cannot skip the blade or extend its active interval.
local ArrowInterception = {}
function ArrowInterception.fraction(position: Vector3, delta: Vector3, from: number, untilAt: number,
    center: Vector3, aim: Vector3, hitAt: number, window: number, range: number, arc: number): number?
    local duration = untilAt - from
    if duration <= 0 then return nil end
    local low, high = math.max(0, (hitAt - from) / duration), math.min(1, (hitAt + window - from) / duration)
    if low > high then return nil end
    local offset = position - center
    local function plane(value: number, change: number): boolean
        if math.abs(change) < 0.000001 then return value >= 0 end
        local at = -value / change
        if change > 0 then low = math.max(low, at) else high = math.min(high, at) end
        return low <= high
    end
    if not plane(3 - offset.Y, -delta.Y) or not plane(3 + offset.Y, delta.Y) then return nil end
    local side = aim:Cross(Vector3.yAxis)
    local tangent = math.tan(math.rad(arc / 2))
    local forward, across = offset:Dot(aim), offset:Dot(side)
    local df, ds = delta:Dot(aim), delta:Dot(side)
    if not plane(forward * tangent + across, df * tangent + ds)
        or not plane(forward * tangent - across, df * tangent - ds) then return nil end
    local a = delta.X * delta.X + delta.Z * delta.Z
    local b = 2 * (offset.X * delta.X + offset.Z * delta.Z)
    local c = offset.X * offset.X + offset.Z * offset.Z - range * range
    if a < 0.000001 then
        if c > 0 then return nil end
    else
        local discriminant = b * b - 4 * a * c
        if discriminant < 0 then return nil end
        local root = math.sqrt(discriminant)
        low, high = math.max(low, (-b - root) / (2 * a)), math.min(high, (-b + root) / (2 * a))
    end
    return if low <= high and low >= 0 and low <= 1 then low else nil
end
return table.freeze(ArrowInterception)
