--!strict
local Service = require("../../build/test-source/server/application/lobby/ClassService")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
	local f: any = { lives = { [1] = 10, [2] = 20 }, living = { [1] = true, [2] = true },
		locked = {}, changes = {}, observed = {} }
	f.service = Service.new({
		life = function(owner) return f.lives[owner] or 0 end,
		alive = function(owner) return f.living[owner] == true end,
		locked = function(owner) return f.locked[owner] == true end,
		changed = function(owner, classId)
			table.insert(f.changes, { owner = owner, classId = classId })
			assert(f.service.get(owner) == classId, "Reset port observed the previous class")
			table.insert(f.observed, f.service.snapshot(owner))
			f.lives[owner] += 1 -- Synchronous runtime reset creates a new combat life.
			table.insert(f.observed, f.service.snapshot(owner))
		end,
	})
	f.service.join(1); f.service.join(2)
	return f
end
local function reject(f, owner, life, classId, reason)
	local ok, actual = f.service.select(owner, life, classId)
	assert(not ok and actual == reason, tostring(actual) .. " ~= " .. reason)
end

test("new visitor defaults to warlock and initial version is stable", function()
	local f = fixture(); local state = f.service.snapshot(1)
	assert(f.service.get(1) == "warlock" and state.classId == "warlock" and state.life == 10)
	assert(state.alive and not state.locked and state.version == 1)
	assert(#state.classes == 2 and state.classes[1] == "warlock" and state.classes[2] == "warrior")
	assert(f.service.snapshot(1).version == state.version and #f.changes == 0)
	assert(f.service.get(999) == "warlock" and f.service.snapshot(999).version == 0)
end)
test("selection changes class before synchronous reset and returns the new life", function()
	local f = fixture(); local before = f.service.snapshot(1)
	assert(f.service.select(1, 10, "warrior"))
	local state = f.service.snapshot(1)
	assert(f.observed[1].classId == "warrior" and f.observed[1].life == 10)
	assert(f.observed[2].classId == "warrior" and f.observed[2].life == 11)
	assert(state.classId == "warrior" and state.life == 11 and state.version > before.version)
	assert(#f.changes == 1 and f.changes[1].owner == 1 and f.changes[1].classId == "warrior")
	assert(f.service.snapshot(2).classId == "warlock" and f.service.snapshot(2).life == 20
		and f.service.snapshot(2).version == 1)
	reject(f, 1, 10, "warlock", "stale_life")
	assert(f.service.get(1) == "warrior" and #f.changes == 1)
	assert(f.service.select(1, 11, "warlock") and f.service.snapshot(1).life == 12)
end)
test("same choice and duplicate join do not reset life or regress a selection", function()
	local f = fixture(); local initial = f.service.snapshot(1).version
	assert(f.service.select(1, 10, "warlock"))
	assert(#f.changes == 0 and f.lives[1] == 10 and f.service.snapshot(1).version == initial)
	assert(f.service.select(1, 10, "warrior"))
	local selected = f.service.snapshot(1)
	f.service.join(1); f.service.join(1)
	assert(f.service.get(1) == "warrior" and f.service.snapshot(1).version == selected.version)
	assert(f.service.select(1, 11, "warrior"))
	assert(#f.changes == 1 and f.lives[1] == 11 and f.service.snapshot(1).version == selected.version)
end)
test("unknown and invalid selections never invoke the reset port", function()
	local f = fixture(); local version = f.service.snapshot(1).version
	reject(f, 999, 0, "warrior", "unknown_player")
	for _, value in { "archon", "Warrior", "", string.rep("x", 2000), 3, false } do
		reject(f, 1, 10, value, "invalid_class")
	end
	reject(f, 1, 9, "warrior", "stale_life")
	assert(#f.changes == 0 and f.service.get(1) == "warlock" and f.service.snapshot(1).version == version)
end)
test("queue or match lock is checked dynamically and cannot be bypassed by an old snapshot", function()
	local f = fixture(); local old = f.service.snapshot(1)
	f.locked[1] = true
	reject(f, 1, old.life, "warrior", "locked")
	local locked = f.service.snapshot(1)
	assert(locked.locked and locked.version > old.version and #f.changes == 0)
	assert(f.service.snapshot(1).version == locked.version)
	f.locked[1] = false
	local free = f.service.snapshot(1)
	assert(not free.locked and free.version > locked.version)
	assert(f.service.select(1, free.life, "warrior") and #f.changes == 1)
end)
test("death and externally renewed life invalidate selection without resetting twice", function()
	local f = fixture(); local before = f.service.snapshot(1)
	f.living[1] = false
	reject(f, 1, 10, "warrior", "dead")
	local dead = f.service.snapshot(1)
	assert(not dead.alive and dead.version > before.version and #f.changes == 0)
	f.living[1], f.lives[1] = true, 11
	reject(f, 1, 10, "warrior", "stale_life")
	local respawned = f.service.snapshot(1)
	assert(respawned.alive and respawned.life == 11 and respawned.version > dead.version)
	assert(f.service.select(1, 11, "warrior") and #f.changes == 1 and f.lives[1] == 12)
end)
test("snapshot data and class list are independent copies", function()
	local f = fixture(); local state = f.service.snapshot(1); local version = state.version
	state.classId, state.life, state.classes[1] = "warrior", 999, "forged"
	table.insert(state.classes, "archon")
	local fresh = f.service.snapshot(1)
	assert(fresh.classId == "warlock" and fresh.life == 10 and fresh.version == version)
	assert(#fresh.classes == 2 and fresh.classes[1] == "warlock" and f.service.snapshot(2).classes[1] == "warlock")
end)
test("leave clears selection and rejoin preserves monotonic owner versions", function()
	local f = fixture(); assert(f.service.select(1, 10, "warrior"))
	local selected = f.service.snapshot(1)
	f.service.leave(1); f.service.leave(1)
	local absent = f.service.snapshot(1)
	assert(f.service.get(1) == "warlock" and absent.classId == "warlock" and absent.life == 0
		and not absent.alive and not absent.locked and absent.version > selected.version)
	reject(f, 1, 11, "warrior", "unknown_player")
	f.lives[1] = 40; f.service.join(1)
	local returned = f.service.snapshot(1)
	assert(returned.classId == "warlock" and returned.life == 40 and returned.version > absent.version)
	assert(f.service.get(2) == "warlock" and #f.changes == 1)
end)
test("destroy is idempotent and cannot recreate registrations or trigger resets", function()
	local f = fixture(); f.service.destroy(); f.service.destroy(); f.service.join(1)
	reject(f, 1, 10, "warrior", "unknown_player")
	assert(f.service.get(1) == "warlock" and not f.service.snapshot(1).alive and #f.changes == 0)
end)
print("Class selection contracts:", total, "passed (production service; life/match ports simulated)")
