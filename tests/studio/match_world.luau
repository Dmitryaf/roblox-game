--!strict
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local Arena = require(modules.adapters.world.MatchArena)
local World = require(modules.adapters.world.MatchWorld)
local arena = Arena.create()
local contexts: { [number]: any } = { [101] = { mode = "match", team = 1, matchId = 1, frozen = false },
	[102] = { mode = "training", matchId = 0, frozen = false } }
local world = World.new(arena, function(owner) return contexts[owner] end, function(owner) return not contexts[owner].frozen end)
local rigs: { Model } = {}
local roots: { [number]: BasePart } = {}
for _, owner in {101, 102} do
	local rig = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name, root.Size, root.Anchored, root.Parent = "HumanoidRootPart", Vector3.new(2, 2, 1), true, rig
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck, humanoid.HipHeight, humanoid.Parent = false, 2, rig
	rig.Parent = workspace
	table.insert(rigs, rig)
	roots[owner] = root
	world.register(owner, rig, root, humanoid, arena.spawn(contexts[owner].team, owner))
	world.resetContext(owner, contexts[owner].team, false)
end
local count = 0
local function test(name: string, run: () -> ()) run(); count += 1; print("PASS Match geometry: " .. name) end
local ok, err = xpcall(function()
	test("training visitors receive distinct stable positions", function()
		local positions: { Vector3 } = {}
		for owner = 201, 250 do
			local base = arena.spawn(nil, owner)
			assert(arena.spawn(nil, owner) == base)
			assert(math.abs(base.Position.X - 230) < 33 and math.abs(base.Position.Z) < 69)
			for _, previous in positions do assert((previous - base.Position).Magnitude >= 9) end
			table.insert(positions, base.Position)
		end
		for owner = 201, 250 do arena.forget(owner) end
	end)
	test("spawn has support and blocks casting in either direction", function()
		assert(world.position(101) and world.origin(101) == nil)
		local hit = world.sweep(101, Vector3.new(0, 4, 98), Vector3.new(0, 0, 20), 0.8)
		assert(hit and hit.Z <= 102)
		local outward = world.sweep(101, Vector3.new(0, 4, 118), Vector3.new(0, 0, -30), 0.8)
		assert(outward and outward.Z == 118)
	end)
	test("leaving pad enables cast but return teleport is rejected", function()
		world.move(101, Vector3.new(0, 3.2, 98))
		assert(world.origin(101))
		assert(world.landing(101, Vector3.new(0, 4, 106), Vector3.zAxis) == nil)
		world.resetContext(101, 1, false)
		assert(world.position(101).Z == 118 and world.validate(101))
	end)
	test("enemy pad and path through protected pad reject landing", function()
		world.move(101, Vector3.new(0, 3.2, -98))
		assert(world.landing(101, Vector3.new(0, 4, -110), -Vector3.zAxis) == nil)
		assert(world.landing(101, Vector3.new(0, 4, -140), -Vector3.zAxis) == nil)
	end)
	test("safe arena landing still works", function()
		world.move(101, Vector3.new(45, 3.2, 0))
		local destination = world.landing(101, Vector3.new(60, 4, 0), Vector3.xAxis)
		assert(destination and math.abs(destination.X - 57) < 0.01)
	end)
	test("practice and match stay in separate bounds and cannot damage practice target across context", function()
		world.move(102, Vector3.new(230, 3.2, 0))
		assert(world.origin(102))
		assert(world.landing(102, Vector3.new(80, 4, 0), Vector3.xAxis) == nil)
		local _, target = world.sweep(102, Vector3.new(230, 4, 0), Vector3.new(0, 0, -50), 0.8)
		assert(target)
		world.damage(101, target, 25)
		assert(target.Health == 100)
		world.damage(102, target, 25)
		assert(target.Health == 75)
	end)
	test("frozen participant cannot cast and fresh life drops old pad restriction", function()
		contexts[101].frozen = true
		assert(world.origin(101) == nil)
		contexts[101].frozen = false
		world.remove(101)
		world.register(101, rigs[1], roots[101], rigs[1]:FindFirstChildOfClass("Humanoid"), arena.spawn(1, 101))
		assert(world.validate(101))
	end)
end, debug.traceback)
for _, owner in {101, 102} do world.remove(owner) end
for _, rig in rigs do rig:Destroy() end
arena.folder:Destroy()
assert(ok, err)
print(tostring(count) .. " match geometry tests passed")
return true
