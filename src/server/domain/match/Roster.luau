--!strict
export type State = { [number]: number }
local Roster = {}
function Roster.count(state: State): (number, number)
	local a, b = 0, 0
	for _, team in state do
		if team == 1 then a += 1 else b += 1 end
	end
	return a, b
end
function Roster.fromPairOrder(owners: { number }): State
	local state: State = {}
	for index, owner in owners do state[owner] = if index % 2 == 1 then 1 else 2 end
	return state
end
return Roster
