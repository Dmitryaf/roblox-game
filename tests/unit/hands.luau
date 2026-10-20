--!strict
local Vector3 = require("@lune/roblox").Vector3
-- These are staged production sources. Missing implementation is a hard failure.
local Service = require("../../build/test-source/server/application/combat/HandsService")
local Config = require("../../build/test-source/server/config/Hands")
local total = 0
local function test(name, run)
	run()
	total += 1
	print("PASS", name)
end
local function near(actual, expected)
	assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function fixture()
	local f: any = { events = {}, damages = {}, slows = {}, slowEvents = {}, members = {},
		living = { [1] = true, [2] = true, [3] = true }, blocked = false, now = 0, placements = {} }
	f.service = Service.new({
		alive = function(owner) return f.living[owner] == true end,
		placement = function(owner, point, range, radius)
			table.insert(f.placements, { owner = owner, point = point, range = range, radius = radius })
			if f.blocked or point.X ~= point.X or point.Y ~= point.Y or point.Z ~= point.Z
				or point.Magnitude > range then return nil end
			return Vector3.new(point.X, 0.1, point.Z)
		end,
		targets = function(owner) return table.clone(f.members[owner] or {}) end,
		damage = function(owner, target, amount)
			table.insert(f.damages, { owner = owner, target = target, amount = amount, at = f.now })
		end,
		slow = function(target, multiplier)
			f.slows[target] = multiplier
			table.insert(f.slowEvents, { target = target, multiplier = multiplier })
		end,
		emit = function(event) table.insert(f.events, event) end,
	}, Config)
	f.service.join(1, 10)
	f.service.join(2, 20)
	function f.cast(owner, at)
		owner, f.now = owner or 1, at or f.now
		assert(f.service.cast(owner, if owner == 1 then 10 else 20, Vector3.new(4, 0, 0), f.now))
		for index = #f.events, 1, -1 do
			local event = f.events[index]
			if event.kind == "preparing" and event.owner == owner then return event end
		end
		error("Accepted cast did not emit preparation")
	end
	function f.step(at)
		f.now = at
		f.service.step(at)
	end
	function f.damage(owner, target)
		local sum = 0
		for _, event in f.damages do
			if (not owner or event.owner == owner) and (not target or event.target == target) then sum += event.amount end
		end
		return sum
	end
	function f.eventsOf(kind, owner)
		local events = {}
		for _, event in f.events do
			if event.kind == kind and (not owner or event.owner == owner) then table.insert(events, event) end
		end
		return events
	end
	function f.areas(owner)
		local areas = {}
		for _, area in f.service.snapshot(1).active do if not owner or area.owner == owner then table.insert(areas, area) end end
		return areas
	end
	return f
end

test("approved hands parameters and accepted placement are authoritative", function()
	assert(Config.windup == 0.8 and Config.duration == 4 and Config.cooldown == 9)
	assert(Config.radius == 8 and Config.range == 30 and Config.slowMultiplier == 0.65)
	assert(Config.damagePerSecond == 6 and Config.tickInterval == 0.5)
	local f = fixture()
	local event = f.cast(1, 7)
	assert(event.owner == 1 and event.life == 10 and type(event.areaId) == "number")
	assert(event.position == Vector3.new(4, 0.1, 0) and event.radius == Config.radius)
	near(event.startedAt, 7); near(event.launchAt, 7.8); near(event.expiresAt, 11.8); near(event.readyAt, 16)
	assert(f.placements[1].range == 30 and f.placements[1].radius == 8)
	assert(#f.areas(1) == 1 and f.areas(1)[1].kind == "preparing")
end)

test("preparation and launch do not deal early damage; first half-second tick does", function()
	local f = fixture(); f.members[1] = { "target" }; local event = f.cast()
	f.step(event.launchAt - 0.001)
	assert(#f.damages == 0 and f.slows.target == nil and #f.eventsOf("active") == 0)
	f.step(event.launchAt)
	assert(#f.eventsOf("active", 1) == 1 and #f.damages == 0)
	near(f.slows.target, 0.65)
	f.step(event.launchAt + 0.499)
	assert(#f.damages == 0)
	f.step(event.launchAt + 0.5)
	assert(#f.damages == 1 and f.damages[1].target == "target" and f.damage(1, "target") == 3)
end)

test("one full occupancy deals eight ticks including exact expiry, then ends once", function()
	local f = fixture(); f.members[1] = { "target" }; local event = f.cast()
	f.step(event.launchAt)
	for tick = 1, 8 do f.step(event.launchAt + tick * Config.tickInterval) end
	assert(#f.damages == 8 and f.damage(1, "target") == 24 and #f.areas() == 0)
	near(f.slows.target, 1)
	local ended = f.eventsOf("ended", 1)
	assert(#ended == 1 and ended[1].areaId == event.areaId)
	f.step(100); f.service.die(1); f.service.leave(1); f.service.destroy()
	assert(#f.damages == 8 and #f.eventsOf("ended", 1) == 1)
end)

test("leaving before a tick restores speed and avoids damage; new entry earns no history", function()
	local f = fixture(); f.members[1] = { "early" }; local event = f.cast()
	f.step(event.launchAt)
	f.members[1] = {}; f.step(event.launchAt + 0.2)
	near(f.slows.early, 1)
	f.step(event.launchAt + 0.5)
	assert(#f.damages == 0)
	f.members[1] = { "late" }; f.step(event.launchAt + 0.6)
	assert(f.damage(nil, "late") == 0); near(f.slows.late, 0.65)
	f.step(event.launchAt + 1)
	assert(f.damage(nil, "late") == 3 and f.damage(nil, "early") == 0)
end)

test("a long frame samples one bounded tick and does not leave a catch-up backlog", function()
	local f = fixture(); local event = f.cast()
	f.step(event.launchAt)
	f.members[1] = { "new entrant" }; f.step(4)
	assert(#f.damages == 1 and f.damage(nil, "new entrant") == 3, "A late sample received retroactive ticks")
	f.step(4); f.step(4.01)
	assert(#f.damages == 1, "Skipped ticks leaked into successive frames")
	f.step(4.3)
	assert(#f.damages == 2 and f.damage(nil, "new entrant") == 6)
	f.step(event.expiresAt)
	assert(f.damage(nil, "new entrant") <= 9 and #f.areas() == 0)
end)

test("duplicate target membership never multiplies one source tick or slow", function()
	local f = fixture(); f.members[1] = { "target", "target" }; local event = f.cast()
	f.step(event.launchAt); f.step(event.launchAt + 0.5)
	assert(f.damage(1, "target") == 3 and #f.damages == 1)
	near(f.slows.target, 0.65)
end)

test("overlapping different owners add damage but slow only to the strongest multiplier", function()
	local f = fixture(); f.members[1], f.members[2] = { "shared" }, { "shared" }
	local first, second = f.cast(1), f.cast(2)
	assert(first.areaId ~= second.areaId)
	f.step(Config.windup); near(f.slows.shared, 0.65)
	f.step(Config.windup + 0.5)
	assert(f.damage(1, "shared") == 3 and f.damage(2, "shared") == 3 and f.damage(nil, "shared") == 6)
	f.service.die(1)
	assert(#f.areas(1) == 0 and #f.areas(2) == 1)
	near(f.slows.shared, 0.65)
	f.step(Config.windup + 1)
	assert(f.damage(1, "shared") == 3 and f.damage(2, "shared") == 6)
	f.members[2] = {}; f.step(Config.windup + 1.1)
	near(f.slows.shared, 1)
end)

test("unknown owner, forged life, death and suspension cannot create areas", function()
	local f = fixture()
	for _, request in { { 3, 30 }, { 1, 20 }, { 1, 9 } } do
		assert(not f.service.cast(request[1], request[2], Vector3.zero, 0))
	end
	f.living[1] = false
	assert(not f.service.cast(1, 10, Vector3.zero, 0))
	f.living[1] = true
	f.service.pause(1, 0)
	assert(f.service.snapshot(1).suspended and not f.service.cast(1, 10, Vector3.zero, 0))
	assert(#f.areas() == 0 and #f.events == 0 and #f.damages == 0)
end)

test("invalid placement does not spend cooldown or emit preparation", function()
	local f = fixture()
	assert(not f.service.cast(1, 10, Vector3.new(31, 0, 0), 0))
	f.blocked = true
	assert(not f.service.cast(1, 10, Vector3.zero, 0))
	assert(#f.events == 0 and f.service.snapshot(1).readyAt == 0)
	f.blocked = false
	assert(f.service.cast(1, 10, Vector3.zero, 0))
end)

test("cooldown survives expiry and becomes available on the exact boundary", function()
	local f = fixture(); local event = f.cast()
	f.step(event.expiresAt)
	assert(not f.service.cast(1, 10, Vector3.zero, Config.cooldown - 0.001))
	assert(f.service.cast(1, 10, Vector3.zero, Config.cooldown))
end)

test("death during preparation prevents activation and all effects", function()
	local f = fixture(); f.members[1] = { "target" }; local event = f.cast()
	f.step(event.launchAt / 2); f.living[1] = false; f.step(event.launchAt)
	assert(#f.areas() == 0 and #f.eventsOf("active", 1) == 0 and #f.damages == 0)
	assert(#f.eventsOf("ended", 1) == 1 and f.service.snapshot(1).alive == false)
end)

test("pause cancels active area, restores slow and freezes cooldown until resume", function()
	local f = fixture(); f.members[1] = { "target" }; f.cast()
	f.step(0.8); f.step(1.3)
	f.service.pause(1, 1.4)
	assert(f.service.snapshot(1).suspended and #f.areas() == 0)
	near(f.slows.target, 1)
	f.step(11.4)
	assert(f.damage(1, "target") == 3 and not f.service.cast(1, 10, Vector3.zero, 11.4))
	f.service.resume(1, 11.4)
	assert(not f.service.snapshot(1).suspended)
	near(f.service.snapshot(1).readyAt, 19)
	assert(not f.service.cast(1, 10, Vector3.zero, 18.999))
	assert(f.service.cast(1, 10, Vector3.zero, 19))
end)

test("new life clears only its own area and cooldown; old life remains invalid", function()
	local f = fixture(); f.members[1], f.members[2] = { "target" }, { "target" }
	f.cast(1); f.cast(2); f.step(0.8)
	f.service.join(1, 11)
	assert(#f.areas(1) == 0 and #f.areas(2) == 1)
	near(f.slows.target, 0.65)
	assert(f.service.snapshot(1).life == 11 and f.service.snapshot(1).readyAt == 0)
	assert(not f.service.cast(1, 10, Vector3.zero, 0.9))
	assert(f.service.cast(1, 11, Vector3.zero, 0.9))
end)

test("leave and repeated destruction release all slow contributions without duplicate ends", function()
	local f = fixture(); f.members[1], f.members[2] = { "shared", "one" }, { "shared", "two" }
	f.cast(1); f.cast(2); f.step(0.8)
	f.service.leave(1)
	near(f.slows.one, 1); near(f.slows.shared, 0.65)
	assert(#f.areas(2) == 1 and #f.eventsOf("ended", 1) == 1)
	f.service.destroy(); f.service.destroy(); f.step(100)
	near(f.slows.shared, 1); near(f.slows.two, 1)
	assert(#f.areas() == 0 and #f.eventsOf("ended", 1) == 1 and #f.eventsOf("ended", 2) == 1)
end)

test("frames crossing tick boundaries retain final sample without replaying stalled areas", function()
    local f = fixture(); local event = f.cast(); f.members[1] = { "enemy" }
    f.step(event.launchAt + 0.02)
    for index = 1, 8 do f.step(event.launchAt + index * Config.tickInterval + 0.016) end
    near(f.damage(1, "enemy"), 24)
    assert(#f.service.snapshot(1).active == 0 and f.slows.enemy == 1)
    local stalled = fixture(); local missed = stalled.cast(); stalled.members[1] = { "enemy" }
    stalled.step(missed.expiresAt + 0.016)
    assert(stalled.damage() == 0 and #stalled.service.snapshot(1).active == 0)
end)
print(string.format("%d hands contract tests passed (production service; world ports simulated, no Studio physics).", total))
