--!strict
export type View = { zone: string, countA: number, countB: number }
local ControlZone = {}
function ControlZone.read(roster: { [number]: number }, occupants: { [number]: boolean }): View
	local a, b = 0, 0
	for owner, team in roster do
		if occupants[owner] then
			if team == 1 then a += 1 else b += 1 end
		end
	end
	return { countA = a, countB = b,
		zone = if a > 0 and b > 0 then "contested" elseif a > 0 then "A" elseif b > 0 then "B" else "neutral" }
end
-- Continuous authoritative occupancy time: allies never multiply the rate.
function ControlZone.advance(scoreA: number, scoreB: number, remaining: number, delta: number,
	zone: string, target: number): (number, number, number, string?, number?)
	local duration = math.min(math.max(delta, 0), remaining)
	local untilTarget = if zone == "A" then target - scoreA elseif zone == "B" then target - scoreB else math.huge
	if untilTarget <= duration then
		duration = math.max(0, untilTarget)
		if zone == "A" then scoreA = target else scoreB = target end
		return scoreA, scoreB, remaining - duration, "score", if zone == "A" then 1 else 2
	end
	if zone == "A" then scoreA += duration elseif zone == "B" then scoreB += duration end
	remaining -= duration
	if remaining <= 0 then
		local visibleA, visibleB = math.floor(scoreA), math.floor(scoreB)
		return scoreA, scoreB, 0, "time", if visibleA > visibleB then 1 elseif visibleB > visibleA then 2 else nil
	end
	return scoreA, scoreB, remaining, nil, nil
end
return ControlZone
