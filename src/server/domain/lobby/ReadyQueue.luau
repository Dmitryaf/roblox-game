--!strict
export type State = { order: { number }, present: { [number]: boolean } }
local ReadyQueue = {}
function ReadyQueue.new(): State
	return { order = {}, present = {} }
end
function ReadyQueue.add(state: State, owner: number): boolean
	if state.present[owner] then return false end
	state.present[owner] = true
	table.insert(state.order, owner)
	return true
end
function ReadyQueue.remove(state: State, owner: number): boolean
	if not state.present[owner] then return false end
	state.present[owner] = nil
	local index = table.find(state.order, owner)
	if index then table.remove(state.order, index) end
	return true
end
function ReadyQueue.position(state: State, owner: number): number?
	return table.find(state.order, owner)
end
return ReadyQueue
