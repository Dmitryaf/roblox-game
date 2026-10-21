--!strict
-- Confirmed interaction presentation only; the server still owns all cover/arrow rules.
type Handle = { step: (number) -> (), destroy: () -> () }
type Ports = { now: () -> number, valid: (number, number) -> boolean,
    create: (string, any, number) -> Handle }
type Entry = { handle: Handle, key: string, kind: string, owner: number, life: number,
    other: number?, otherLife: number?, expires: number }
local Feedback = {}
local cancelled: { [string]: boolean } = {
    dead = true, left = true, reset = true, paused = true, invalid_position = true,
    interceptor_reset = true, occupied = true,
}
function Feedback.new(ports: Ports)
    local entries: { Entry } = {}
    local seen: { [string]: number } = {}
    local stopped = false
    local feedback = {}
    local function remember(marker: string)
        seen[marker] = ports.now() + 12
        local count, first, oldest = 0, nil, math.huge
        for id, expires in seen do
            count += 1
            if expires < oldest then first, oldest = id, expires end
        end
        if count > 96 and first then seen[first] = nil end
    end
    local function clear(key: string, sustainedOnly: boolean?)
        for i = #entries, 1, -1 do
            if entries[i].key == key and (not sustainedOnly or entries[i].kind == "gather") then
                entries[i].handle.destroy(); table.remove(entries, i)
            end
        end
    end
    local function present(kind: string, event: any, key: string, duration: number)
        local now = ports.now()
        local marker = key .. ":" .. kind
        if stopped or seen[marker] or duration <= 0 or not event.position or not ports.valid(event.owner, event.life) then return end
        if event.damageOwner and event.damageLife and not ports.valid(event.damageOwner, event.damageLife) then return end
        remember(marker)
        while #entries >= 12 do entries[1].handle.destroy(); table.remove(entries, 1) end
        table.insert(entries, { handle = ports.create(kind, event, now + duration), key = key, kind = kind,
            owner = event.owner, life = event.life, other = event.damageOwner, otherLife = event.damageLife, expires = now + duration })
    end
    function feedback.arrow(event: any)
        if stopped or type(event) ~= "table" then return end
        if event.kind == "snapshot" or event.kind == "reply" then
            -- Redirect is a completed contact cue, not a persistent projectile visual.
            -- Empty snapshots must not cut its short sound/flash; valid() still guards life/freeze.
            return -- A snapshot never replays a past success sound/flash.
        end
        if type(event.castId) ~= "number" then return end
        local key = "arrow:" .. tostring(event.castId)
        if event.kind == "ended" then
            clear(key, not cancelled[event.reason])
            remember(key .. ":ended")
        elseif event.kind == "redirected" and type(event.expiresAt) == "number" and event.expiresAt > ports.now()
            and not seen[key .. ":ended"] and type(event.sampledAt) == "number" and ports.now() - event.sampledAt < 0.65 then
            present("redirect", event, key, 0.42)
        end
    end
    function feedback.cover(event: any, quiet: boolean?)
        if stopped or type(event) ~= "table" or type(event.areaId) ~= "number" then return end
        local key = "cover:" .. tostring(event.areaId)
        if event.kind == "ended" then
            if cancelled[event.reason] then clear(key) end
            if seen[key .. ":ended"] then return end
            clear(key, true)
            remember(key .. ":ended")
            if not quiet and event.reason == "shattered" and event.expiresAt > ports.now() then present("shatter", event, key, 0.7) end
        elseif event.kind == "active" then
            if seen[key .. ":ended"] or seen[key .. ":raise"] then return end
            clear(key, true)
            if not quiet and event.expiresAt > ports.now() and ports.now() - event.launchAt < 0.65 then present("raise", event, key, 0.55) end
        elseif event.kind == "preparing" and not quiet and not seen[key .. ":ended"] and not seen[key .. ":raise"] and event.launchAt > ports.now() then
            present("gather", event, key, math.min(1, event.launchAt - ports.now()))
        end
    end
    function feedback.syncCover(events: { any })
        local keep = {}
        for _, event in events do keep["cover:" .. tostring(event.areaId)] = true end
        for i = #entries, 1, -1 do
            local e = entries[i]
            if string.sub(e.key, 1, 6) == "cover:" and e.kind == "gather" and not keep[e.key] then
                e.handle.destroy(); table.remove(entries, i)
            end
        end
        -- Geometry already replicates from the server; sync only reconciles resources.
    end
    function feedback.step(now: number)
        if stopped then return end
        for i = #entries, 1, -1 do
            local e = entries[i]
            if now >= e.expires or not ports.valid(e.owner, e.life)
                or (e.other and e.otherLife and not ports.valid(e.other, e.otherLife)) then
                e.handle.destroy(); table.remove(entries, i)
            else e.handle.step(now) end
        end
        for key, expiry in seen do if now >= expiry then seen[key] = nil end end
    end
    function feedback.destroy()
        if stopped then return end
        stopped = true
        for _, entry in entries do entry.handle.destroy() end
        table.clear(entries); table.clear(seen)
    end
    function feedback.inspect(): any return { live = #entries } end
    return feedback
end
return Feedback
