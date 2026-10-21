--!strict
-- Retimes authored contact to the existing authoritative deadline; prediction cannot release.
local Timing = {}
function Timing.time(now: number, started: number, contact: number, expires: number,
    clipContact: number, clipEnd: number, timeline: any?): number
    if now < contact then
        local progress = if timeline then timeline.progress(now)
            else math.clamp((now - started) / math.max(0.06, contact - started), 0, 1)
        return progress * clipContact
    end
    return clipContact + math.clamp((now - contact) / math.max(0.05, expires - contact), 0, 1) * (clipEnd - clipContact)
end
return Timing
