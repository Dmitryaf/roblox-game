--!strict
local ReadyQueue = require(script.Parent.Parent.Parent.domain.lobby.ReadyQueue)
local Roster = require(script.Parent.Parent.Parent.domain.match.Roster)
local ControlZone = require(script.Parent.Parent.Parent.domain.objective.ControlZone)
export type Config = { gathering: number, countdown: number, pause: number, duration: number, target: number, noExpansionLast: number }
export type Ports = { reset: (number, number?, boolean) -> (), freeze: (number, boolean) -> () }
export type Result = { matchId: number, reason: string, winner: number?, scoreA: number, scoreB: number }
type Visitor = { result: Result? }
type Pair = { owners: { number }, deadline: number }
local MatchService = {}

-- The adapter ports are synchronous: replacing a life and freezing it must not yield.
function MatchService.new(ports: Ports, config: Config)
	assert(config.gathering > 0 and config.countdown > 0 and config.pause > 0)
	assert(config.duration > 0 and config.target > 0 and config.noExpansionLast >= 0)
	local visitors: { [number]: Visitor } = {}
	local queue = ReadyQueue.new()
	local roster: Roster.State = {}
	local pair: Pair? = nil
	local phase = "idle"
	local deadline: number? = nil
	local matchId, version = 0, 0
	local scoreA, scoreB, remaining = 0, 0, config.duration
	local zone = ControlZone.read({}, {})
	local sampledAt = 0
	local lastOccupants: { [number]: boolean } = {}
	local destroyed = false
	local service = {}
	local function changed() version += 1 end
	local function pairTeam(owner: number): number?
		if pair then
			local index = table.find(pair.owners, owner)
			if index then return index end
		end
		return nil
	end
	local function clearPair()
		local previous = pair
		pair = nil
		if previous then
			for _, owner in previous.owners do
				if visitors[owner] then ports.reset(owner, nil, false) end
			end
			changed()
		end
	end
	local function setPhase(nextPhase: string, nextDeadline: number?)
		phase, deadline = nextPhase, nextDeadline
		zone = ControlZone.read({}, {})
		changed()
	end
	local function gather(now: number)
		if (phase == "idle" or phase == "finished") and #queue.order >= 2 then
			setPhase("gathering", now + config.gathering)
		elseif phase == "gathering" and #queue.order < 2 then
			setPhase("idle", nil)
		end
	end
	local function finish(reason: string, winner: number?, now: number)
		local result: Result = { matchId = matchId, reason = reason, winner = winner,
			scoreA = math.floor(scoreA), scoreB = math.floor(scoreB) }
		clearPair()
		local previous = roster
		roster = {}
		setPhase("finished", nil)
		for owner in previous do
			if visitors[owner] then
				visitors[owner].result = table.clone(result)
				ports.reset(owner, nil, false)
			end
		end
		gather(now)
	end
	local function resetRoster()
		for owner, team in roster do ports.reset(owner, team, true) end
	end
	local function resume(now: number)
		setPhase("resuming", now + config.countdown)
		resetRoster()
	end
	local function fillVacancies(now: number)
		if phase ~= "paused" then return end
		local a, b = Roster.count(roster)
		if a == 0 and b == 0 then finish("interrupted", nil, now); return end
		local added: { number } = {}
		while a ~= b and #queue.order > 0 do
			local owner = queue.order[1]
			ReadyQueue.remove(queue, owner)
			local team = if a < b then 1 else 2
			roster[owner] = team
			visitors[owner].result = nil
			table.insert(added, owner)
			if team == 1 then a += 1 else b += 1 end
			changed()
		end
		if a == b and a > 0 then
			resume(now)
		else
			for _, owner in added do ports.reset(owner, roster[owner], true) end
		end
	end
	local function reservePair(now: number)
		if phase ~= "active" or pair or #queue.order < 2 or remaining <= config.noExpansionLast + config.countdown then return end
		local a, b = Roster.count(roster)
		if a ~= b or a >= 3 then return end
		local pending: Pair = { owners = { queue.order[1], queue.order[2] }, deadline = now + config.countdown }
		pair = pending
		for team, owner in pending.owners do
			visitors[owner].result = nil
			ports.reset(owner, team, true)
		end
		changed()
	end
	local function start(now: number)
		local count = math.min(6, #queue.order - #queue.order % 2)
		if count < 2 then setPhase("idle", nil); return end
		local selected = {}
		for _ = 1, count do
			local owner = queue.order[1]
			ReadyQueue.remove(queue, owner)
			table.insert(selected, owner)
			visitors[owner].result = nil
		end
		roster = Roster.fromPairOrder(selected)
		matchId += 1
		scoreA, scoreB, remaining = 0, 0, config.duration
		setPhase("countdown", now + config.countdown)
		resetRoster()
	end
	local function activate()
		setPhase("active", nil)
		for owner in roster do ports.freeze(owner, false) end
	end
	-- Time stops in every preparation/pause. A delayed step crosses deadlines once,
	-- then integrates only the actual active interval, capped by victory/time limits.
	local function advance(now: number, occupants: { [number]: boolean })
		if destroyed then return end
		now = math.max(sampledAt, now)
		local cursor = sampledAt
		local oldA, oldB, oldTime = math.floor(scoreA), math.floor(scoreB), math.ceil(remaining)
		while cursor <= now do
			if phase == "gathering" or phase == "countdown" or phase == "resuming" then
				local due = deadline :: number
				if due > now then break end
				cursor = math.max(cursor, due)
				if phase == "gathering" then start(due) else activate() end
			elseif phase == "paused" then
				local due = deadline :: number
				if due > now then break end
				cursor = math.max(cursor, due)
				finish("interrupted", nil, due)
			elseif phase == "active" then
				local pending = pair
				local untilTime = if pending then math.min(now, pending.deadline) else now
				local current = ControlZone.read(roster, occupants)
				if current.zone ~= zone.zone or current.countA ~= zone.countA or current.countB ~= zone.countB then changed() end
				zone = current
				local before = remaining
				local reason, winner
				scoreA, scoreB, remaining, reason, winner = ControlZone.advance(scoreA, scoreB, remaining,
					untilTime - cursor, zone.zone, config.target)
				cursor += before - remaining
				if reason then
					finish(reason, winner, cursor)
				elseif pending and pending.deadline <= now then
					pair = nil
					for team, owner in pending.owners do
						ReadyQueue.remove(queue, owner)
						roster[owner] = team
						ports.freeze(owner, false)
					end
					changed()
				else break end
			else break end
		end
		sampledAt = now
		lastOccupants = table.clone(occupants)
		if oldA ~= math.floor(scoreA) or oldB ~= math.floor(scoreB) or oldTime ~= math.ceil(remaining) then changed() end
		fillVacancies(now)
		reservePair(now)
		gather(now)
	end

	function service.join(owner: number, now: number)
		if destroyed or visitors[owner] then return end
		advance(now, lastOccupants)
		visitors[owner] = {}
		changed()
	end
	local function removeFromMatch(owner: number, now: number)
		local team = roster[owner]
		if not team then return end
		roster[owner] = nil
		clearPair()
		ports.reset(owner, nil, false)
		-- A second exit during the same search must not extend its deadline.
		if phase ~= "paused" then
			setPhase("paused", now + config.pause)
			for member in roster do ports.freeze(member, true) end
		end
		changed()
		fillVacancies(now)
	end
	function service.ready(owner: number, value: boolean, now: number): (boolean, string?)
		if destroyed or not visitors[owner] then return false, "unknown_player" end
		advance(now, lastOccupants)
		if roster[owner] then
			if value then return false, "already_playing" end
			removeFromMatch(owner, now)
			return true, nil
		end
		if value then
			if ReadyQueue.add(queue, owner) then changed() end
		else
			if pairTeam(owner) then clearPair() end
			if ReadyQueue.remove(queue, owner) then changed() end
		end
		fillVacancies(now)
		reservePair(now)
		gather(now)
		return true, nil
	end
	function service.exit(owner: number, now: number): (boolean, string?)
		return service.ready(owner, false, now)
	end
	function service.leave(owner: number, now: number)
		if destroyed or not visitors[owner] then return end
		advance(now, lastOccupants)
		if pairTeam(owner) then clearPair() end
		ReadyQueue.remove(queue, owner)
		removeFromMatch(owner, now)
		visitors[owner] = nil
		changed()
		gather(now)
	end
	function service.step(now: number, occupants: { [number]: boolean }) advance(now, occupants) end
	function service.context(owner: number)
		local team = roster[owner] or pairTeam(owner)
		return { mode = if team then "match" else "training", team = team,
			matchId = if team then matchId else 0, frozen = team ~= nil and (not roster[owner] or phase ~= "active") }
	end
	function service.canAct(owner: number): boolean
		return not destroyed and visitors[owner] ~= nil and not service.context(owner).frozen
	end
	function service.snapshot(owner: number, _now: number)
		local context = service.context(owner)
		local position = ReadyQueue.position(queue, owner)
		local reason: string? = nil
		if position then
			if pairTeam(owner) then reason = "pair_preparing"
			elseif phase == "gathering" then reason = "gathering"
			elseif phase == "paused" then reason = "replacement"
			elseif phase == "active" and remaining <= config.noExpansionLast then reason = "last_seconds"
			elseif phase == "active" and select(1, Roster.count(roster)) >= 3 then reason = "match_full"
			else reason = "waiting_pair" end
		end
		local result = if visitors[owner] then visitors[owner].result else nil
		return { version = version, matchId = matchId, target = config.target, duration = config.duration, phase = phase, team = context.team, mode = context.mode,
			ready = queue.present[owner] == true, queuePosition = position, waitingReason = reason,
			scoreA = math.floor(scoreA), scoreB = math.floor(scoreB), remaining = remaining, deadline = deadline,
			zone = zone.zone, countA = zone.countA, countB = zone.countB,
			result = if result then table.clone(result) else nil, frozen = context.frozen,
			pairDeadline = if pairTeam(owner) and pair then pair.deadline else nil }
	end
	function service.destroy()
		if destroyed then return end
		destroyed = true
		for owner in visitors do ports.freeze(owner, false) end
		visitors, roster = {}, {}
		queue = ReadyQueue.new()
		pair = nil
		changed()
	end
	return service
end
return MatchService
