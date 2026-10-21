--!strict
-- Solid slabs and their warnings replicate from the server; this owns only the caster pose.
local CoverEffects = {}
function CoverEffects.new(pose: any)
    local active: { [number]: any } = {}
    local effects = {}
    local function stop(owner: number)
        if active[owner] then pose.stop(owner); active[owner] = nil end
    end
    function effects.event(event: any)
        local current = active[event.owner]
        if event.kind == "preparing" then
            if current and (current.life > event.life or current.areaId >= event.areaId) then return end
            active[event.owner] = event
            pose.begin(event.owner, event.launchAt, nil, event.startedAt, nil, event.life)
        elseif current and current.life == event.life and current.areaId == event.areaId then stop(event.owner) end
    end
    function effects.sync(events: { any })
        local keep = {}
        for _, event in events do
            if event.kind == "preparing" then keep[event.owner] = true end
            effects.event(event)
        end
        for owner in active do if not keep[owner] then stop(owner) end end
    end
    function effects.step(now: number)
        for owner, event in active do if now >= event.launchAt then stop(owner) end end
    end
    function effects.destroy() for owner in active do stop(owner) end end
    return effects
end
return CoverEffects
