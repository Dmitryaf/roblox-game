--!strict
local Vector3 = require("@lune/roblox").Vector3
local Service = require("../../build/test-source/server/application/combat/ArrowService")
local Config = require("../../build/test-source/server/config/Warlock")
local total = 0
local function test(name, run)
	run()
	total += 1
	print("PASS", name)
end
local function close(a, b) assert(math.abs(a-b) < 0.000001) end
local function fixture()
	local f = { events = {}, moves = {}, damages = {}, sweeps = 0 }
	f.service = Service.new({
		origin = function() return Vector3.new(0,4,0) end,
		alive = function() return true end,
		sweep = function() f.sweeps += 1; return nil,nil end,
		damage = function(...) table.insert(f.damages, {...}) end,
		landing = function(_,position) return position end,
		move = function(...) table.insert(f.moves, {...}) end,
		emit = function(event) table.insert(f.events, event) end,
	}, Config)
	f.service.join(1,10); f.service.join(2,20)
	function f.cast(owner, life, now)
		assert(f.service.cast(owner,life,Vector3.xAxis,now))
		return f.events[#f.events].castId
	end
	return f
end

test("pause cancels preparing or flying projectile once and rejects cast and teleport", function()
	for _, at in {0.1,0.7} do
		local f = fixture()
		local id = f.cast(1,10,0)
		f.service.step(at)
		f.service.pause(1,at)
		local events = #f.events
		f.service.pause(1,at+1)
		assert(#f.events == events and f.events[events].kind == "ended" and f.events[events].reason == "paused")
		assert(f.service.snapshot(1).suspended and #f.service.snapshot(1).active == 0)
		local ok,reason = f.service.cast(1,10,Vector3.xAxis,at+2)
		assert(not ok and reason == "paused")
		ok,reason = f.service.teleport(1,10,id,at+2)
		assert(not ok and reason == "paused")
		local sweeps = f.sweeps
		f.service.step(100)
		assert(f.sweeps == sweeps and #f.moves == 0 and #f.damages == 0 and #f.events == events)
	end
end)
test("cooldown shifts by exactly frozen interval and duplicate pause or resume cannot extend it", function()
	local f = fixture()
	f.cast(1,10,0)
	f.service.pause(1,1)
	f.service.pause(1,5)
	f.service.resume(1,11)
	f.service.resume(1,12)
	close(f.service.snapshot(1).readyAt, Config.cooldown+10)
	assert(not f.service.snapshot(1).suspended)
	local ok,reason = f.service.cast(1,10,Vector3.xAxis,Config.cooldown+10-0.001)
	assert(not ok and reason == "cooldown")
	assert(f.service.cast(1,10,Vector3.xAxis,Config.cooldown+10))
end)
test("new life clears pause and cooldown, old life and old teleport cannot act", function()
	local f = fixture()
	local id = f.cast(1,10,0)
	f.service.pause(1,0.1)
	f.service.join(1,11)
	assert(not f.service.snapshot(1).suspended and f.service.snapshot(1).readyAt == 0)
	local ok,reason = f.service.cast(1,10,Vector3.xAxis,0.2)
	assert(not ok and reason == "stale_life")
	ok,reason = f.service.teleport(1,10,id,0.2)
	assert(not ok and reason == "stale_life")
	assert(f.service.cast(1,11,Vector3.xAxis,0.2))
end)
test("one owner pause does not stop another life; leaving clears suspended state", function()
	local f = fixture()
	f.cast(1,10,0)
	local id = f.cast(2,20,0)
	f.service.pause(1,0.1)
	assert(f.service.teleport(2,20,id,0.8) and #f.moves == 1)
	f.service.leave(1)
	f.service.resume(1,10)
	local snapshot = f.service.snapshot(1)
	assert(not snapshot.suspended and snapshot.life == 0 and not snapshot.alive)
	f.service.join(1,12)
	assert(f.service.cast(1,12,Vector3.xAxis,10))
	f.service.destroy(); f.service.destroy()
	assert(#f.service.snapshot(1).active == 0)
end)
print("Arrow pause contracts:", total, "passed")
