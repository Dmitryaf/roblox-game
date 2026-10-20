--!strict
-- A prediction can gather, but can never release before an authoritative deadline.
local Timeline = {}
function Timeline.new(started: number)
	local confirmedAt: number? = nil
	local releaseAt, releaseFrom = math.huge, 0
	local timeline = {}
	function timeline.progress(now: number): number
		if confirmedAt == nil then
			return 0.32 * (1 - math.exp(-math.max(0, now - started) / 0.065))
		end
		local t = math.clamp((now - confirmedAt) / math.max(0.055, releaseAt - confirmedAt), 0, 1)
		return releaseFrom + (1 - releaseFrom) * (t * t * (3 - 2 * t))
	end
	function timeline.confirm(now: number, deadline: number)
		if confirmedAt ~= nil then return end
		releaseFrom = timeline.progress(now)
		confirmedAt, releaseAt = now, deadline
	end
	function timeline.confirmed(): boolean return confirmedAt ~= nil end
	return timeline
end
return Timeline
