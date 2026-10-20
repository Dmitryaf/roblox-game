--!strict
local ClassService = {}
local CLASSES = table.freeze({ "warlock", "warrior" })
export type Ports = { life: (number) -> number, alive: (number) -> boolean,
	locked: (number) -> boolean, changed: (number, string) -> () }
type Entry = { joined: boolean, selected: string, version: number,
	classId: string, life: number, alive: boolean, locked: boolean }

function ClassService.new(ports: Ports)
	local entries: { [number]: Entry } = {}
	local stopped = false
	local service = {}
	local function refresh(owner: number, entry: Entry)
		local classId = if entry.joined then entry.selected else "warlock"
		local life = if entry.joined then ports.life(owner) else 0
		local alive = entry.joined and ports.alive(owner)
		local locked = entry.joined and ports.locked(owner)
		if entry.classId ~= classId or entry.life ~= life or entry.alive ~= alive or entry.locked ~= locked then
			entry.version += 1
			entry.classId, entry.life, entry.alive, entry.locked = classId, life, alive, locked
		end
	end
	function service.join(owner: number)
		if stopped then return end
		local entry = entries[owner]
		if entry and entry.joined then return end
		if not entry then
			entry = { joined = false, selected = "warlock", version = 0,
				classId = "", life = -1, alive = false, locked = false }
			entries[owner] = entry
		end
		local joined = entry :: Entry
		joined.joined, joined.selected = true, "warlock"
		refresh(owner, joined)
	end
	function service.leave(owner: number)
		local entry = entries[owner]
		if not entry or not entry.joined then return end
		-- Keep the last observed version so reconnecting this owner cannot regress it.
		entry.joined, entry.selected = false, "warlock"
		refresh(owner, entry)
	end
	function service.get(owner: number): string
		local entry = entries[owner]
		return if entry and entry.joined then entry.selected else "warlock"
	end
	function service.select(owner: number, life: number, classId: string): (boolean, string?)
		local entry = entries[owner]
		if stopped or not entry or not entry.joined then return false, "unknown_player" end
		refresh(owner, entry)
		if table.find(CLASSES, classId) == nil then return false, "invalid_class" end
		if life ~= entry.life then return false, "stale_life" end
		if not entry.alive then return false, "dead" end
		if entry.locked then return false, "locked" end
		if entry.selected == classId then return true, nil end
		entry.selected = classId
		-- This synchronous port resets training/combat life. Reentrant snapshots see
		-- the new choice, including while the port publishes the new life.
		ports.changed(owner, classId)
		refresh(owner, entry)
		return true, nil
	end
	function service.snapshot(owner: number)
		local entry = entries[owner]
		if entry then refresh(owner, entry) end
		return { classId = if entry then entry.classId else "warlock",
			life = if entry then entry.life else 0, alive = if entry then entry.alive else false,
			locked = if entry then entry.locked else false, version = if entry then entry.version else 0,
			classes = table.clone(CLASSES) }
	end
	function service.destroy()
		stopped = true
		table.clear(entries)
	end
	return service
end
return ClassService
