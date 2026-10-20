--!strict
local Vector3 = require("@lune/roblox").Vector3
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Config = require("../../build/test-source/server/config/Warrior")
local Domain = require("../../build/test-source/server/domain/combat/SwordSwing")
-- Lune has no Roblox Vector3 global. Inject only that value type and the real staged dependency.
local Service = luau.load(fs.readFile("build/test-source/server/application/combat/MeleeService.luau"), { environment = {
	Vector3 = Vector3, require = function(path) assert(path == "../../domain/combat/SwordSwing"); return Domain end,
} })()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a - b) < 0.000001, tostring(a) .. " ~= " .. tostring(b)) end
local direction = Vector3.new(1, 0, 0)
local function fixture()
	local f = { now = 0, events = {}, damages = {}, members = { "enemy" }, queries = {}, faces = {},
		living = { [1] = true, [2] = true }, origins = { [1] = Vector3.new(0, 3, 0), [2] = Vector3.new(10, 3, 0) }, blocked = false }
	f.service = Service.new({
		alive = function(owner) return f.living[owner] == true end,
		origin = function(owner) return f.origins[owner] end,
		face = function(owner, aim) table.insert(f.faces, { owner = owner, aim = aim }); return not f.blocked end,
		targets = function(owner, aim, range, arc)
			table.insert(f.queries, { owner = owner, aim = aim, range = range, arc = arc, at = f.now })
			return table.clone(f.members)
		end,
		damage = function(owner, target, amount)
			table.insert(f.damages, { owner = owner, target = target, amount = amount, at = f.now })
			if f.onDamage then f.onDamage(owner, target) end
		end,
		emit = function(event) table.insert(f.events, event) end,
	}, Config)
	f.service.join(1, 10); f.service.join(2, 20)
	function f.cast(owner, at, aim)
		owner, f.now = owner or 1, at or f.now
		return f.service.cast(owner, if owner == 1 then 10 else 20, aim or direction, f.now)
	end
	function f.step(at) f.now = at; f.service.step(at) end
	function f.eventsOf(kind, owner)
		local result = {}
		for _, event in f.events do if event.kind == kind and (not owner or event.owner == owner) then table.insert(result, event) end end
		return result
	end
	return f
end

test("production sword domain/config define the approved timing and single swing", function()
	assert(Config.windup == 0.3 and Config.recovery == 0.45 and Config.cooldown == 0.9)
	assert(Config.range == 7 and Config.arcDegrees == 100 and Config.damage == 20)
	local state = Domain.new(10)
	assert(Domain.reason(state, 9, 0) == "stale_life" and Domain.reason(state, 10, 0) == nil)
	local swing = Domain.begin(state, 1, 123, direction, 0, Config)
	assert(state.swing == swing and swing.owner == 1 and swing.life == 10 and swing.swingId == 123)
	near(swing.hitAt, 0.3); near(swing.expiresAt, 0.75); near(state.readyAt, 0.9)
	assert(Domain.reason(state, 10, 0) == "busy")
end)
test(".299 has no damage; .3 deals exactly 20 once per unique target in the arc", function()
	local f = fixture(); f.members = { "left", "center", "left", "right", "center" }
	assert(f.cast()); assert(#f.eventsOf("preparing") == 1 and #f.queries == 0)
	f.step(0.299); assert(#f.damages == 0 and #f.queries == 0)
	f.step(0.3); assert(#f.damages == 3 and #f.eventsOf("struck") == 1 and #f.queries == 1)
	local seen = {}
	for _, hit in f.damages do assert(not seen[hit.target] and hit.owner == 1 and hit.amount == 20 and hit.at == 0.3); seen[hit.target] = true end
	assert(seen.left and seen.center and seen.right)
	assert(f.queries[1].range == 7 and f.queries[1].arc == 100 and f.queries[1].aim == direction)
	f.step(0.31); f.step(0.74)
	assert(#f.damages == 3 and #f.queries == 1, "Recovery repeated a committed hit")
end)
test("targets and current origin are sampled at impact rather than during windup", function()
	local f = fixture(); f.members = { "left-before-impact" }; assert(f.cast())
	f.step(0.15); f.members = { "entered-during-windup" }; f.origins[1] = Vector3.new(4, 3, 0)
	f.step(0.3)
	assert(#f.damages == 1 and f.damages[1].target == "entered-during-windup")
	assert(f.eventsOf("struck")[1].position == Vector3.new(4, 3, 0))
	f.members = { "entered-after-hit" }; f.step(0.5); assert(#f.damages == 1)
end)
test("an empty impact can miss and enemies entering recovery are not hit", function()
	local f = fixture(); f.members = {}; assert(f.cast()); f.step(0.3)
	f.members = { "late-enemy" }; f.step(0.6)
	assert(#f.eventsOf("struck") == 1 and #f.damages == 0 and #f.queries == 1)
end)
test("a stalled frame past the full recovery cannot invent a historical hit", function()
	for _, at in { 0.75, 8 } do
		local f = fixture(); assert(f.cast()); f.step(at)
		assert(#f.damages == 0 and #f.queries == 0 and #f.eventsOf("struck") == 0)
		assert(#f.service.snapshot(1).active == 0 and f.eventsOf("ended")[1].reason == "expired")
	end
	local within = fixture(); assert(within.cast()); within.step(0.749)
	assert(#within.damages == 1 and #within.eventsOf("struck") == 1)
end)
test("recovery ends at .75 but the authoritative cooldown lasts until .9", function()
	local f = fixture(); assert(f.cast()); f.step(0.3); f.step(0.75)
	assert(#f.service.snapshot(1).active == 0 and #f.eventsOf("ended") == 1)
	local ok, reason = f.cast(1, 0.899); assert(not ok and reason == "cooldown")
	assert(f.cast(1, 0.9) and #f.eventsOf("preparing") == 2)
	near(f.service.snapshot(1).readyAt, 1.8)
end)
test("vertical/zero aim and rejected facing do not spend cooldown", function()
	for _, aim in { Vector3.new(0, 1, 0), Vector3.new(0, -1, 0), Vector3.new(0, 0, 0) } do
		local f = fixture(); local ok, reason = f.cast(1, 0, aim)
		assert(not ok and reason == "invalid_aim" and #f.events == 0 and #f.faces == 0 and f.service.snapshot(1).readyAt == 0)
		assert(f.cast(1, 0))
	end
	local f = fixture(); f.blocked = true
	local ok, reason = f.cast(); assert(not ok and reason == "invalid_position" and f.service.snapshot(1).readyAt == 0)
	f.blocked = false; assert(f.cast())
end)
test("sloped aim is flattened and normalized before facing and hit queries", function()
	local f = fixture(); assert(f.cast(1, 0, Vector3.new(0.6, 0.8, 0)))
	assert(f.faces[1].aim == direction and f.eventsOf("preparing")[1].direction == direction)
	f.step(0.3); assert(f.queries[1].aim == direction)
end)
test("death during preparation cancels once and no subsequent frame deals damage", function()
	local f = fixture(); assert(f.cast()); f.living[1] = false; f.step(0.15); f.step(0.4); f.service.die(1)
	assert(#f.eventsOf("ended") == 1 and f.eventsOf("ended")[1].reason == "dead" and #f.damages == 0)
	assert(not f.service.snapshot(1).alive and #f.service.snapshot(1).active == 0)
	local ok, reason = f.cast(1, 1); assert(not ok and reason == "dead")
end)
test("pause cancels the attack and freezes the remaining cooldown exactly once", function()
	local f = fixture(); assert(f.cast()); f.service.pause(1, 0.1); f.service.pause(1, 2)
	f.step(8); local ok, reason = f.cast(1, 8)
	assert(not ok and reason == "paused" and #f.damages == 0 and f.service.snapshot(1).suspended)
	assert(#f.eventsOf("ended") == 1 and f.eventsOf("ended")[1].reason == "paused")
	f.service.resume(1, 10); f.service.resume(1, 11)
	near(f.service.snapshot(1).readyAt, 10.8); assert(not f.service.snapshot(1).suspended)
	ok, reason = f.cast(1, 10.799); assert(not ok and reason == "cooldown")
	assert(f.cast(1, 10.8))
end)
test("new life, leave and destruction remove old attacks and reject stale life", function()
	local f = fixture(); assert(f.cast()); f.service.join(1, 11); f.step(0.3)
	assert(#f.damages == 0 and f.service.snapshot(1).life == 11 and f.service.snapshot(1).readyAt == 0)
	local ok, reason = f.service.cast(1, 10, direction, 0.3); assert(not ok and reason == "stale_life")
	assert(f.service.cast(1, 11, direction, 0.3)); f.service.leave(1); f.step(0.6)
	assert(#f.damages == 0 and f.service.snapshot(1).life == 0)
	ok, reason = f.service.cast(1, 11, direction, 1); assert(not ok and reason == "not_ready")
	assert(f.cast(2, 1)); f.service.destroy(); f.step(2)
	assert(#f.service.snapshot(2).active == 0 and f.service.snapshot(2).life == 0 and #f.damages == 0)
end)
test("impact cannot proceed after a reentrant death or missing current origin", function()
	local f = fixture(); f.members = { "first", "second" }
	f.onDamage = function() f.service.die(1) end
	assert(f.cast()); f.step(0.3); f.step(0.4)
	assert(#f.damages == 1 and f.damages[1].target == "first" and #f.eventsOf("ended") == 1)
	local unavailable = fixture(); assert(unavailable.cast()); unavailable.origins[1] = nil; unavailable.step(0.3)
	assert(#unavailable.damages == 0 and unavailable.eventsOf("ended")[1].reason == "invalid_position")
end)
print(string.format("%d MeleeService/domain tests passed", total))
