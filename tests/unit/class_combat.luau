--!strict
local Vector3 = require("@lune/roblox").Vector3
local Arrow = require("../../build/test-source/server/application/combat/ArrowService")
local Hands = require("../../build/test-source/server/application/combat/HandsService")
local fs, luau = require("@lune/fs"), require("@lune/luau")
local SwordSwing = require("../../build/test-source/server/domain/combat/SwordSwing")
local Melee = luau.load(fs.readFile("build/test-source/server/application/combat/MeleeService.luau"), { environment = {
	Vector3 = Vector3, require = function(path) assert(path == "../../domain/combat/SwordSwing"); return SwordSwing end,
} })()
local Warlock = require("../../build/test-source/server/application/combat/WarlockCombat")
local Aggregate = require("../../build/test-source/server/application/combat/ClassCombat")
local ArrowConfig = require("../../build/test-source/server/config/Warlock")
local HandsConfig = require("../../build/test-source/server/config/Hands")
local MeleeConfig = require("../../build/test-source/server/config/Warrior")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a - b) < 0.000001) end
local aim, point = Vector3.new(1, 0, 0), Vector3.new(4, 0, 0)
local function fixture()
	local f = { now = 0, classes = { [1] = "warlock", [2] = "warrior" }, living = { [1] = true, [2] = true },
		positions = { [1] = Vector3.new(0, 3, 0), [2] = Vector3.new(6, 3, 0) },
		events = { arrow = {}, hands = {}, melee = {} }, damages = { arrow = {}, hands = {}, melee = {} }, moves = {},
		slows = {}, faces = {}, placements = {}, arrowOrigins = 0 }
	local function alive(owner) return f.living[owner] == true end
	local function origin(owner) return f.positions[owner] end
	local function damage(kind)
		return function(owner, target, amount) table.insert(f.damages[kind], { owner = owner, target = target, amount = amount }) end
	end
	local function emit(kind) return function(event) table.insert(f.events[kind], event) end end
	local arrow = Arrow.new({ alive = alive, origin = function(owner) f.arrowOrigins += 1; return origin(owner) end,
		sweep = function() return nil, nil end, damage = damage("arrow"), landing = function(_, destination) return destination end,
		move = function(owner, destination) f.positions[owner] = destination; table.insert(f.moves, owner) end, emit = emit("arrow") }, ArrowConfig)
	local hands = Hands.new({ alive = alive, placement = function(owner, destination, range, radius)
		table.insert(f.placements, { owner = owner, range = range, radius = radius }); return destination end,
		targets = function() return { 2 } end, damage = damage("hands"), slow = function(target, amount) f.slows[target] = amount end,
		emit = emit("hands") }, HandsConfig)
	local melee = Melee.new({ alive = alive, origin = origin, face = function(owner, direction)
		table.insert(f.faces, { owner = owner, direction = direction }); return true end,
		targets = function() return { "arc-enemy", "arc-enemy" } end, damage = damage("melee"), emit = emit("melee") }, MeleeConfig)
	f.combat = Aggregate.new(Warlock.new(arrow, hands), melee, function(owner) return f.classes[owner] or "warlock" end)
	f.combat.join(1, 10); f.combat.join(2, 20)
	function f.step(at) f.now = at; f.combat.step(at) end
	function f.snapshots(owner) return { f.combat.snapshot(owner), f.combat.handsSnapshot(owner), f.combat.meleeSnapshot(owner) } end
	function f.armAll()
		assert(f.combat.cast(1, 10, aim, 0)); f.step(ArrowConfig.windup)
		assert(f.combat.castHands(1, 10, point, ArrowConfig.windup))
		f.step(ArrowConfig.windup + HandsConfig.windup)
		assert(f.combat.swing(2, 20, aim, f.now))
		assert(#f.combat.snapshot(1).active == 1 and #f.combat.handsSnapshot(1).active == 1 and #f.combat.meleeSnapshot(2).active == 1)
		assert(f.slows[2] == HandsConfig.slowMultiplier)
	end
	function f.ends(kind)
		local count = 0; for _, event in f.events[kind] do if event.kind == "ended" then count += 1 end end; return count
	end
	return f
end

test("aggregate joins and exposes the same authoritative life through all three abilities", function()
	local f = fixture()
	for owner, life in { [1] = 10, [2] = 20 } do
		for _, state in f.snapshots(owner) do assert(state.life == life and state.alive and not state.suspended and state.readyAt == 0 and #state.active == 0) end
	end
end)
test("wrong class refuses arrow, teleport, hands and sword before spending resources", function()
	local f = fixture()
	local attempts = {
		function() return f.combat.cast(2, 20, aim, 0) end,
		function() return f.combat.teleport(2, 20, 123, 0) end,
		function() return f.combat.castHands(2, 20, point, 0) end,
		function() return f.combat.swing(1, 10, aim, 0) end,
	}
	for _, attempt in attempts do local ok, reason = attempt(); assert(not ok and reason == "wrong_class") end
	assert(f.arrowOrigins == 0 and #f.moves == 0 and #f.placements == 0 and #f.faces == 0)
	for owner = 1, 2 do for _, state in f.snapshots(owner) do assert(state.readyAt == 0 and #state.active == 0) end end
end)
test("real arrow teleport, sword impact and hands slow/DoT all pass through the aggregate", function()
	local f = fixture(); assert(f.combat.cast(1, 10, aim, 0)); assert(f.combat.swing(2, 20, aim, 0))
	f.step(0.3)
	assert(#f.damages.melee == 1 and f.damages.melee[1].amount == 20)
	f.step(ArrowConfig.windup)
	local cast = f.combat.snapshot(1).active[1]
	assert(cast.kind == "flying" and f.combat.teleport(1, 10, cast.castId, 0.8))
	assert(#f.moves == 1 and f.positions[1].X > 0 and #f.combat.snapshot(1).active == 0)
	assert(f.combat.castHands(1, 10, point, 0.8)); f.step(1.6)
	assert(f.slows[2] == 0.65 and #f.damages.hands == 0)
	f.step(2.1); assert(#f.damages.hands == 1 and f.damages.hands[1].amount == 3)
	assert(#f.damages.arrow == 0 and f.placements[1].range == 30 and f.placements[1].radius == 8)
end)
test("warlock preparation excludes a second spell without blocking the other class", function()
	local f = fixture(); assert(f.combat.cast(1, 10, aim, 0))
	local ok, reason = f.combat.castHands(1, 10, point, 0.1)
	assert(not ok and reason == "busy" and #f.placements == 0)
	assert(f.combat.swing(2, 20, aim, 0.1)); f.step(ArrowConfig.windup)
	assert(f.combat.castHands(1, 10, point, ArrowConfig.windup))
end)
test("pause/resume reaches all abilities, removes slow and freezes each cooldown", function()
	local f = fixture(); f.armAll()
	local at = f.now
	local before = { f.combat.snapshot(1).readyAt, f.combat.handsSnapshot(1).readyAt, f.combat.meleeSnapshot(2).readyAt }
	f.combat.pause(1, at); f.combat.pause(2, at); f.combat.pause(1, at + 1)
	for owner = 1, 2 do for _, state in f.snapshots(owner) do assert(state.suspended and #state.active == 0) end end
	assert(f.slows[2] == 1 and f.ends("arrow") == 1 and f.ends("hands") == 1 and f.ends("melee") == 1)
	f.step(5); assert(#f.damages.melee == 0 and #f.damages.hands == 0)
	f.combat.resume(1, 10); f.combat.resume(2, 10)
	near(f.combat.snapshot(1).readyAt, before[1] + 10 - at)
	near(f.combat.handsSnapshot(1).readyAt, before[2] + 10 - at)
	near(f.combat.meleeSnapshot(2).readyAt, before[3] + 10 - at)
	for owner = 1, 2 do for _, state in f.snapshots(owner) do assert(not state.suspended) end end
end)
test("death cancels three active resources once and prevents later damage", function()
	local f = fixture(); f.armAll(); f.combat.die(1); f.combat.die(2); f.combat.die(1); f.step(3)
	for owner = 1, 2 do for _, state in f.snapshots(owner) do assert(not state.alive and #state.active == 0) end end
	assert(f.slows[2] == 1 and #f.damages.hands == 0 and #f.damages.melee == 0)
	assert(f.ends("arrow") == 1 and f.ends("hands") == 1 and f.ends("melee") == 1)
end)
test("new life clears old spell/swing state and resets cooldown without accepting stale requests", function()
	local f = fixture(); f.armAll(); f.combat.join(1, 11); f.combat.join(2, 21); f.step(3)
	for owner, life in { [1] = 11, [2] = 21 } do
		for _, state in f.snapshots(owner) do assert(state.life == life and state.alive and #state.active == 0 and state.readyAt == 0) end
	end
	for _, attempt in {
		function() return f.combat.cast(1, 10, aim, 3) end,
		function() return f.combat.castHands(1, 10, point, 3) end,
		function() return f.combat.swing(2, 20, aim, 3) end,
	} do local ok, reason = attempt(); assert(not ok and reason == "stale_life") end
	assert(f.slows[2] == 1 and #f.damages.melee == 0 and #f.damages.hands == 0)
	assert(f.combat.swing(2, 21, aim, 3)); f.step(3.3); assert(#f.damages.melee == 1)
end)
test("class change plus runtime life reset removes old powers and authorizes the new class", function()
	local f = fixture(); assert(f.combat.cast(1, 10, aim, 0))
	f.classes[1] = "warrior"; f.combat.join(1, 11)
	local ok, reason = f.combat.cast(1, 11, aim, 0.1); assert(not ok and reason == "wrong_class")
	assert(f.combat.swing(1, 11, aim, 0.1)); f.step(0.4)
	assert(#f.combat.snapshot(1).active == 0 and #f.damages.melee == 1 and f.damages.melee[1].owner == 1)
end)
test("leave and destroy clear all abilities and remove every slow contribution", function()
	for _, method in { "leave", "destroy" } do
		local f = fixture(); f.armAll()
		if method == "leave" then f.combat.leave(1); f.combat.leave(2) else f.combat.destroy() end
		f.step(3)
		for owner = 1, 2 do for _, state in f.snapshots(owner) do assert(state.life == 0 and not state.alive and #state.active == 0) end end
		assert(f.slows[2] == 1 and #f.damages.melee == 0 and #f.damages.hands == 0)
		assert(f.ends("arrow") == 1 and f.ends("hands") == 1 and f.ends("melee") == 1)
	end
end)
print(string.format("%d ClassCombat real-service integration tests passed", total))
