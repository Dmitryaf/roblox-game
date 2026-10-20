--!strict
-- Owns only the heavy-hit timed contribution. The world port composes it with other slow sources.
export type Ports = {
    alive: (number) -> boolean, token: (any) -> any?, owner: (any) -> number?, apply: (any, number) -> (),
}
type Lease = { multiplier: number, expiresAt: number }
type Target = { token: any, leases: { [number]: Lease }, applied: number }
local TimedSlowService = {}
local function finite(value: number): boolean return value == value and math.abs(value) < math.huge end
function TimedSlowService.new(ports: Ports)
    local targets: { [any]: Target } = {}
    local stopped = false
    local service = {}
    local function current(target: any, state: Target): boolean
        local token = ports.token(target)
        return token ~= nil and token == state.token
    end
    local function remove(target: any, state: Target, restore: boolean)
        targets[target] = nil -- Release references before the world callback.
        if restore and state.applied ~= 1 and current(target, state) then ports.apply(target, 1) end
    end
    local function refresh(target: any, state: Target)
        local strongest = 1
        for _, lease in state.leases do strongest = math.min(strongest, lease.multiplier) end
        if strongest == 1 then remove(target, state, true)
        elseif strongest ~= state.applied then
            state.applied = strongest
            ports.apply(target, strongest)
        end
    end
    function service.step(now: number)
        if stopped or not finite(now) then return end
        for target, state in targets do
            if not current(target, state) then remove(target, state, false); continue end
            for owner, lease in state.leases do
                if now >= lease.expiresAt or not ports.alive(owner) then state.leases[owner] = nil end
            end
            refresh(target, state)
        end
    end
    function service.hit(owner: number, target: any, multiplier: number, duration: number, now: number): boolean
        if stopped or target == nil or not finite(multiplier) or multiplier <= 0 or multiplier >= 1
            or not finite(duration) or duration <= 0 or not finite(now) or not finite(now + duration) then return false end
        service.step(now)
        if not ports.alive(owner) then return false end
        local token = ports.token(target)
        if token == nil then return false end
        local state = targets[target]
        if not state then
            state = { token = token, leases = {}, applied = 1 }
            targets[target] = state
        end
        local previous = state.leases[owner]
        state.leases[owner] = {
            multiplier = if previous then math.min(previous.multiplier, multiplier) else multiplier,
            expiresAt = now + duration,
        }
        refresh(target, state)
        return true
    end
    function service.reset(owner: number)
        if stopped then return end
        for target, state in targets do
            if not current(target, state) then remove(target, state, false)
            elseif ports.owner(target) == owner then remove(target, state, true)
            else state.leases[owner] = nil; refresh(target, state) end
        end
    end
    function service.destroy()
        if stopped then return end
        stopped = true
        for target, state in targets do remove(target, state, true) end
    end
    return service
end
return TimedSlowService
