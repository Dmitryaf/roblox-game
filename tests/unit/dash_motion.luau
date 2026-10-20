--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector2, Vector3, CFrame = rb.Vector2, rb.Vector3, rb.CFrame
local source = fs.readFile("src/client/presentation/DashMotion.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(actual, expected) assert(math.abs(actual - expected) < 0.0001, tostring(actual) .. " ~= " .. tostring(expected)) end
local function vectorNear(actual, expected) assert((actual - expected).Magnitude < 0.0001, tostring(actual) .. " ~= " .. tostring(expected)) end
local function signal()
	local listeners, event = {}, {}
	function event:Connect(callback)
		local c = { Connected = true }; function c:Disconnect() self.Connected = false end
		table.insert(listeners, { c, callback }); return c
	end
	function event.fire(...) for _, item in listeners do if item[1].Connected then item[2](...) end end end
	function event.count() local count = 0; for _, item in listeners do if item[1].Connected then count += 1 end end; return count end
	return event
end
local function fixture(existing)
	local f = { attributes = { CombatClass = "warrior", CombatLife = 1 }, velocityWrites = 0, casts = {}, floorQueries = {} }
	f.simulation, f.added, f.removing = signal(), signal(), signal()
	f.classChanged, f.lifeChanged, f.childAdded, f.childRemoved = signal(), signal(), signal(), signal()
	f.rootAdded, f.rootRemoved, f.died = signal(), signal(), signal()
	f.humanoid = { Parent = true, Health = 100, WalkSpeed = 16, MoveDirection = Vector3.new(0, 0, -1), Died = f.died,
		HipHeight = 2, RigType = "R15" }
	f.character = { Parent = true, ChildAdded = f.childAdded, ChildRemoved = f.childRemoved }
	function f.character:GetAttribute(name) return f.attributes[name] end
	function f.character:GetAttributeChangedSignal(name) return if name == "CombatClass" then f.classChanged else f.lifeChanged end
	function f.character:FindFirstChild() return f.root end
	function f.character:FindFirstChildOfClass() return f.humanoid end
	f.data = { Parent = f.character, Anchored = false, Size = Vector3.new(2, 2, 1), Position = Vector3.new(0, 3, 0), AssemblyLinearVelocity = Vector3.new(55, 7, 0),
		ChildAdded = f.rootAdded, ChildRemoved = f.rootRemoved }
	f.root = setmetatable({}, {
		__index = function(_, key)
			if key == "IsA" then return function(_, name) return name == "BasePart" end end
			if key == "GetChildren" then return function() return if existing then { f.mover } else {} end end
			return f.data[key]
		end,
		__newindex = function(_, key, value)
			assert(key == "AssemblyLinearVelocity", "Motion wrote nonvelocity root property " .. key)
			f.velocityWrites += 1; f.data[key] = value
		end,
	})
	f.mover = { Name = "WarriorDashVelocity", Parent = f.root, Enabled = true, PlaneVelocity = Vector2.new(16 / 0.28, 0),
		attributes = { DashDirection = Vector3.xAxis, DashOrigin = Vector3.new(0, 3, 0), DashDistance = 16, DashSpeed = 16 / 0.28 } }
	function f.mover:IsA(name) return name == "LinearVelocity" end
	function f.mover:GetAttribute(name) return self.attributes[name] end
	f.player = { Character = f.character, CharacterAdded = f.added, CharacterRemoving = f.removing }
	local world = {}
	function world:Blockcast(frame, size, direction, params)
		assert(params.RespectCanCollide and params.FilterType == "Exclude" and params.FilterDescendantsInstances[1] == f.character)
		vectorNear(size, Vector3.new(3, 3.5, 3)); vectorNear(frame.Position, f.data.Position)
		table.insert(f.casts, direction)
		return if f.hit then { Distance = f.hit } else nil
	end
	function world:Raycast(origin, direction, params)
		assert(params.RespectCanCollide and params.FilterType == "Exclude" and params.FilterDescendantsInstances[1] == f.character)
		table.insert(f.floorQueries, { origin = origin, direction = direction })
		return if f.noGround then nil else { Normal = f.normal or Vector3.yAxis }
	end
	local game = {}; function game:GetService() return { PreSimulation = f.simulation } end
	local module = luau.load(source, { environment = { game = game, workspace = world, Vector2 = Vector2, Vector3 = Vector3, CFrame = CFrame,
		typeof = typeof,
		RaycastParams = { new = function() return {} end }, Enum = { RaycastFilterType = { Exclude = "Exclude" }, HumanoidRigType = { R6 = "R6" } },
	} })()
	f.motion = module.new(f.player)
	function f.start() f.rootAdded.fire(f.mover) end
	function f.step(delta) f.simulation.fire(delta or 1 / 60) end
	function f.removeMover() f.mover.Parent = nil; f.rootRemoved.fire(f.mover) end
	return f
end
test("existing or newly replicated server movers are clipped without creating or moving the body", function()
	for _, existing in { true, false } do
		local f = fixture(existing); if not existing then f.start() end
		f.step(); near(f.mover.PlaneVelocity.X, 16 / 0.28); near(f.mover.PlaneVelocity.Y, 0)
		assert(f.velocityWrites == 0 and #f.casts == 1)
		f.data.Position = Vector3.new(15.8, 3, 0); f.step(0.02)
		near(f.mover.PlaneVelocity.X, 7.5); assert(f.velocityWrites == 0 and f.mover.Enabled)
		f.motion.destroy()
	end
end)
test("the approved endpoint stops the mover and restores current walking while preserving vertical velocity", function()
	local f = fixture(true)
	for _, delta in { 0.04, 0.03, 0.05, 0.018, 0.025, 0.06, 0.02, 0.016, 0.016, 0.016, 0.016 } do
		f.step(delta)
		if f.mover.Enabled then f.data.Position += Vector3.new(f.mover.PlaneVelocity.X * delta, 0, f.mover.PlaneVelocity.Y * delta) end
		assert(f.data.Position.X <= 16 and f.data.Position.X >= 0, "Dash crossed its approved endpoint")
	end
	assert(not f.mover.Enabled and f.velocityWrites == 1)
	vectorNear(f.root.AssemblyLinearVelocity, Vector3.new(0, 7, -16))
	local writes = f.velocityWrites; f.step(); assert(f.velocityWrites == writes)
	f.motion.destroy()
end)
test("native blockcast reduces speed for a thin wall and hands control back before contact", function()
	local f = fixture(true); f.hit = 1; f.step(0.02)
	near(f.mover.PlaneVelocity.X, 32.5)
	f.hit = 0.4; f.step(0.02)
	assert(not f.mover.Enabled); vectorNear(f.root.AssemblyLinearVelocity, Vector3.new(0, 7, -16))
	f.motion.destroy()
end)
test("server deletion returns current running speed once and does not leave stale callbacks", function()
	local f = fixture(true); f.humanoid.MoveDirection = Vector3.xAxis; f.humanoid.WalkSpeed = 10
	f.data.AssemblyLinearVelocity = Vector3.new(57, -4, 0)
	f.removeMover(); assert(f.velocityWrites == 1)
	vectorNear(f.root.AssemblyLinearVelocity, Vector3.new(10, -4, 0))
	f.step(); assert(f.velocityWrites == 1 and #f.casts == 0)
	f.motion.destroy(); assert(f.simulation.count() == 0 and f.added.count() == 0 and f.removing.count() == 0)
	assert(f.rootAdded.count() == 0 and f.rootRemoved.count() == 0 and f.died.count() == 0)
end)
test("death anchoring removed roots and character removal never write through invalid bodies", function()
	for _, condition in { "death", "anchored", "root_removed", "character_removed" } do
		local f = fixture(true)
		if condition == "death" then f.humanoid.Health = 0; f.died.fire()
		elseif condition == "anchored" then f.data.Anchored = true
		elseif condition == "root_removed" then f.data.Parent = nil
		else f.removing.fire(f.character); f.player.Character = nil end
		f.step(); f.removeMover(); assert(f.velocityWrites == 0)
		f.motion.destroy(); assert(f.velocityWrites == 0)
	end
end)
test("life and class changes retire the old lease; malformed or unrelated movers are ignored", function()
	for _, change in { "life", "class" } do
		local f = fixture(true)
		if change == "life" then f.attributes.CombatLife = 2; f.lifeChanged.fire()
		else f.attributes.CombatClass = "warlock"; f.classChanged.fire() end
		assert(not f.mover.Enabled and f.velocityWrites == 1); f.step(); assert(#f.casts == 0)
		f.motion.destroy()
	end
	for _, invalid in { "other_name", "missing_attributes", "nonfinite", "vertical" } do
		local f = fixture(false)
		if invalid == "other_name" then f.mover.Name = "OtherMover"
		elseif invalid == "missing_attributes" then f.mover.attributes.DashOrigin = nil
		elseif invalid == "nonfinite" then f.mover.attributes.DashSpeed = math.huge
		else f.mover.attributes.DashDirection = Vector3.yAxis end
		f.start(); f.step(); assert(f.velocityWrites == 0 and #f.casts == 0)
		f.motion.destroy()
	end
end)
test("a replicated old origin safely shortens an already advanced local run and never adds dash distance", function()
	local f = fixture(false); f.data.Position = Vector3.new(2, 3, 0); f.start()
	for _ = 1, 30 do
		f.step(1 / 60)
		if f.mover.Enabled then f.data.Position += Vector3.new(f.mover.PlaneVelocity.X / 60, 0, 0) end
	end
	assert(not f.mover.Enabled); near(f.data.Position.X, 15.95)
	f.motion.destroy()
end)
test("a valid absolute corridor limit allows the full dash from the live body despite stale origin", function()
	local f = fixture(false); f.data.Position = Vector3.new(5, 3, 0)
	f.mover.attributes.DashLimit = Vector3.new(24, 3, 0); f.start()
	for _ = 1, 30 do
		f.step(1 / 60)
		if f.mover.Enabled then f.data.Position += Vector3.new(f.mover.PlaneVelocity.X / 60, 0, 0) end
	end
	assert(not f.mover.Enabled); near(f.data.Position.X, 20.95)
	assert(f.data.Position.X - 5 < 16); f.motion.destroy()
end)
test("live-body distance cannot cross the absolute wall corridor limit including a limit behind the body", function()
	for _, limit in { 10, 4 } do
		local f = fixture(false); f.data.Position = Vector3.new(5, 3, 0)
		f.mover.attributes.DashLimit = Vector3.new(limit, 3, 0); f.start()
		for _ = 1, 30 do
			f.step(1 / 60)
			if f.mover.Enabled then f.data.Position += Vector3.new(f.mover.PlaneVelocity.X / 60, 0, 0) end
		end
		assert(not f.mover.Enabled)
		near(f.data.Position.X, if limit > 5 then limit - 0.05 else 5)
		f.motion.destroy()
	end
end)
test("the next frame requires ground ahead of the body with rig height and collision filtering", function()
	for _, rig in { "R15", "R6" } do
		local f = fixture(true); f.humanoid.RigType = rig; f.humanoid.HipHeight = 4
		f.step(0.02)
		local query = f.floorQueries[1]
		near(query.origin.X, 16 / 0.28 * 0.02 + 1.5); near(query.origin.Y, 3.5)
		near(query.direction.Y, if rig == "R6" then -4.5 else -6.5)
		f.noGround = true; f.step(0.02)
		assert(not f.mover.Enabled); vectorNear(f.root.AssemblyLinearVelocity, Vector3.new(0, 7, -16))
		f.motion.destroy()
	end
	local f = fixture(true); f.normal = Vector3.xAxis; f.step(0.02)
	assert(not f.mover.Enabled, "A steep face is not supported ground"); f.motion.destroy()
end)
test("a new character can acquire its root later without retaining old body listeners", function()
	local f = fixture(false)
	f.removing.fire(f.character); assert(f.rootAdded.count() == 0 and f.rootRemoved.count() == 0)
	local root = f.root; f.root = nil
	f.added.fire(f.character); assert(f.rootAdded.count() == 0)
	f.root = root; f.childAdded.fire(root); assert(f.rootAdded.count() == 1 and f.rootRemoved.count() == 1)
	f.start(); f.step(); assert(#f.casts == 1 and f.mover.Enabled)
	f.motion.destroy(); assert(f.rootAdded.count() == 0 and f.rootRemoved.count() == 0)
end)
test("destroy disables only the existing mover and disconnects all character body and simulation listeners", function()
	local f = fixture(true); f.motion.destroy(); f.motion.destroy()
	assert(not f.mover.Enabled and f.velocityWrites == 1)
	for _, event in { f.simulation, f.added, f.removing, f.classChanged, f.lifeChanged, f.childAdded, f.childRemoved, f.rootAdded, f.rootRemoved, f.died } do
		assert(event.count() == 0)
	end
	f.step(); f.start(); assert(f.velocityWrites == 1 and #f.casts == 0)
end)
print(string.format("%d DashMotion lifecycle tests passed", total))
