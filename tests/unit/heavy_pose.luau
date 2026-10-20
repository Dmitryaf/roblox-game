--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = rb.Vector3, rb.CFrame
local function loadMotion(name)
	return luau.load(fs.readFile("src/client/presentation/" .. name .. ".luau"), { environment = { Vector3 = Vector3 } })()
end
local Heavy, Melee, Dash = loadMotion("HeavyMotion"), loadMotion("MeleeMotion"), loadMotion("DashPoseMotion")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function difference(a, b) local _, angle = (a:Inverse() * b):ToAxisAngle(); return math.abs(angle) end
local function signal()
	local listeners, event = {}, {}
	function event:Connect(callback)
		local c = { Connected = true }; function c:Disconnect() self.Connected = false end
		table.insert(listeners, { c, callback }); return c
	end
	function event.fire(...) for _, item in listeners do if item[1].Connected then item[2](...) end end end
	function event.count() local n = 0; for _, item in listeners do if item[1].Connected then n += 1 end end; return n end
	return event
end
local function fixture()
	local f = { time = 100, life = 7, classId = "warrior", motors = {}, base = {}, faces = {}, objects = {}, impacts = {} }
	f.animation, f.simulation, f.heartbeat = signal(), signal(), signal()
	f.character = { Parent = true }
	function f.character:GetAttribute(name) return if name == "CombatClass" then f.classId else f.life end
	f.humanoid = { Parent = f.character, Health = 100, AutoRotate = true, MoveDirection = Vector3.new(0, 0, -1) }
	f.rootData = { Parent = f.character, Anchored = false, CFrame = CFrame.new(10, 3, 2), AssemblyLinearVelocity = Vector3.new(0, 5, -16) }
	f.root = setmetatable({}, {
		__index = function(_, key)
			if key == "IsA" then return function(_, name) return name == "BasePart" end end
			if key == "Position" then return f.rootData.CFrame.Position end
			return f.rootData[key]
		end,
		__newindex = function(_, key) error("Heavy presentation wrote root " .. key) end,
	})
	function f.character:FindFirstChildOfClass() return f.humanoid end
	function f.character:FindFirstChild(name) return if name == "HumanoidRootPart" then f.root else nil end
	local descendants = {}
	for index, name in { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "RightHip", "LeftHip", "RightKnee", "LeftKnee" } do
		local motor = { Name = name, Parent = f.character, C0 = CFrame.Angles(0.12, 0.06, 0.03), Transform = CFrame.Angles(index * 0.01, 0.08, -0.04) }
		function motor:IsA(kind) return kind == "Motor6D" end
		f.motors[name], f.base[name] = motor, motor.Transform; table.insert(descendants, motor)
	end
	function f.character:GetDescendants() return descendants end
	f.player = { Character = f.character }
	local players = { LocalPlayer = f.player }; function players:GetPlayerByUserId(owner) return if owner == 10 then f.player else nil end
	local facing = {}
	function facing.new(_, direction)
		f.humanoid.AutoRotate = false
		local value = { direction = direction, destroyed = false, steps = 0 }
		function value.step() value.steps += 1 end
		function value.destroy() value.destroyed = true; f.humanoid.AutoRotate = true end
		table.insert(f.faces, value); return value
	end
	f.world = {}; function f.world:GetServerTimeNow() return f.time end
	local services = { Players = players, RunService = { PreAnimation = f.animation, PreSimulation = f.simulation, Heartbeat = f.heartbeat }, Debris = { AddItem = function() end } }
	f.game = {}; function f.game:GetService(name) return assert(services[name]) end
	local modules = { MeleeMotion = Melee, DashPoseMotion = Dash, HeavyMotion = Heavy, MeleeFacing = facing }
	local names = {}; for name in modules do names[name] = name end
	f.pose = luau.load(fs.readFile("src/client/presentation/MeleePose.luau"), { environment = {
		game = f.game, workspace = f.world, CFrame = CFrame, Vector3 = Vector3, script = { Parent = names }, require = function(name) return assert(modules[name]) end,
	} })().new()
	function f.frame(delta)
		f.time += delta or 0.016; f.animation.fire()
		for name, motor in f.motors do f.base[name] = CFrame.Angles((f.time - 100) * 0.1, 0.08, -0.04); motor.Transform = f.base[name] end
		f.simulation.fire(delta or 0.016)
	end
	function f.restored() for name, motor in f.motors do assert(difference(motor.Transform, f.base[name]) < 0.00001, "Not restored: " .. name) end end
	function f.beginHeavy(id) f.pose.beginHeavy(10, 100.65, 100, 101.25, Vector3.new(0, 0, -1), id or 1) end
	function f.effects(style)
		local poseModule = { new = function() error("Effects unexpectedly created another pose owner") end }
		local impactModule = { new = function(_, variant)
			local value = { variant = variant, hits = {}, cancels = {} }; table.insert(f.impacts, value)
			value.hit = function(event) table.insert(value.hits, event) end
			value.cancel = function(owner, id) table.insert(value.cancels, { owner, id }) end
			value.step, value.destroy = function() end, function() end
			return value
		end }
		local instance = { new = function(class)
			local object = { ClassName = class, Destroy = function(self) self.destroyed = true end, Play = function(self) self.played = true end }
			table.insert(f.objects, object); return object
		end }
		local dependencies = { Pose = poseModule, Impact = impactModule }
		return luau.load(fs.readFile("src/client/presentation/MeleeEffects.luau"), { environment = {
			game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame, Color3 = rb.Color3, ColorSequence = rb.ColorSequence,
			NumberSequence = rb.NumberSequence, Instance = instance, script = { Parent = { MeleePose = "Pose", MeleeImpact = "Impact" } },
			require = function(name) return dependencies[name] end,
		} })().new(f.pose, style)
	end
	return f
end
local forward = Vector3.new(0, 0, -1)
test("heavy has a deliberate coil through the server windup then follows through while preserving the native running legs", function()
	local f = fixture(); f.beginHeavy()
	f.frame(0.16); local first = f.motors.RightShoulder.Transform
	f.frame(0.36); assert(difference(first, f.motors.RightShoulder.Transform) > 0.35)
	local coil = f.motors.RightShoulder.Transform; f.frame(0.13)
	assert(difference(coil, f.motors.RightShoulder.Transform) > 0.7)
	local contact = f.motors.RightShoulder.Transform; f.frame(0.1)
	assert(difference(contact, f.motors.RightShoulder.Transform) > 0.5)
	for _, name in { "RightHip", "LeftHip", "RightKnee", "LeftKnee" } do assert(f.motors[name].Transform == f.base[name]) end
	assert(f.root.AssemblyLinearVelocity == Vector3.new(0, 5, -16) and f.root.CFrame == CFrame.new(10, 3, 2))
	f.frame(0.51); f.restored(); assert(f.humanoid.AutoRotate); f.pose.destroy()
end)
test("normal and heavy may share swing id 1 without their late ended messages canceling each other", function()
	local f = fixture(); f.beginHeavy(1); f.frame(0.25)
	f.pose.stop(10, "melee", 1); f.pose.stop(10, "heavy", 0)
	assert(not f.faces[1].destroyed)
	f.pose.begin(10, f.time + 0.3, f.time, f.time + 0.75, forward, 1); f.frame(0.12)
	local current = f.motors.RightShoulder.Transform
	f.pose.stop(10, "heavy", 1); assert(f.motors.RightShoulder.Transform == current and not f.faces[2].destroyed)
	f.pose.stop(10, "melee", 1); f.restored(); f.pose.destroy()
end)
test("heavy and dash exchange one pose owner and late cancel preserves the newer action", function()
	local f = fixture(); f.pose.beginDash(10, 0.28, forward, 1); f.frame(0.1)
	f.beginHeavy(1); f.frame(0.12); local current = f.motors.Waist.Transform
	f.pose.stop(10, "dash", 1); assert(f.motors.Waist.Transform == current)
	f.pose.beginDash(10, 0.28, forward, 2); f.frame(0.1)
	current = f.motors.Waist.Transform; f.pose.stop(10, "heavy", 1)
	assert(f.motors.Waist.Transform == current and f.faces[1].destroyed)
	f.pose.destroy(); f.restored()
end)
test("late confirmation blends smoothly and keeps the fixed accepted aim instead of restarting windup", function()
	local f = fixture(); f.time = 100.5; f.beginHeavy()
	f.pose.step(f.time); f.animation.fire(); f.simulation.fire(0)
	f.restored(); assert(f.faces[1].direction == forward)
	f.frame(0.04); assert(difference(f.motors.RightShoulder.Transform, f.base.RightShoulder) > 0.5)
	near(Heavy.time(100.65, 100, 100.65, 101.25), 0.65)
	near(Heavy.time(110.9, 110, 110.9, 111.8), 0.65)
	f.pose.destroy(); f.restored()
end)
test("heavy death life class pause expiry and destroy restore Animator and the facing owner", function()
	for _, reason in { "dead", "life", "class", "pause", "expiry", "destroy" } do
		local f = fixture(); f.beginHeavy(); f.frame(0.3)
		if reason == "dead" then f.humanoid.Health = 0
		elseif reason == "life" then f.life = 8
		elseif reason == "class" then f.classId = "warlock"
		elseif reason == "pause" then f.rootData.Anchored = true
		elseif reason == "expiry" then f.time = 101.26
		else f.pose.destroy() end
		f.pose.step(f.time); f.restored(); assert(f.humanoid.AutoRotate and f.faces[1].destroyed)
		f.pose.destroy(); assert(f.animation.count() == 0 and f.simulation.count() == 0)
	end
end)
test("heavy contact keys stay finite and continuous with nonzero blade speed across accepted hit time", function()
	local shoulder
	for _, channel in Heavy.channels do
		for _, name in channel.names do assert(not name:find("Hip") and not name:find("Knee")) end
		for index = 0, 1250 do
			local value = Heavy.sample(channel.keys, index / 1000)
			assert(value.X == value.X and value.Y == value.Y and value.Z == value.Z and value.Magnitude < 3)
		end
		if channel.names[1] == "RightShoulder" then shoulder = channel end
	end
	local dt = 0.0001
	local before, contact, after = Heavy.sample(shoulder.keys, 0.65 - dt), Heavy.sample(shoulder.keys, 0.65), Heavy.sample(shoulder.keys, 0.65 + dt)
	assert((after - before).Magnitude / (2 * dt) > 1 and (after - before).Magnitude < 0.01)
	assert(((after - contact) / dt - (contact - before) / dt).Magnitude < 0.1)
	near(Heavy.weight(0, 1), 0); near(Heavy.weight(1.25, 1), 0); near(Heavy.weight(0.65, 1), 1)
end)
test("real Effects style routing and same-id cleanup preserve the newer shared heavy pose", function()
	local f = fixture(); local normal, heavy = f.effects(nil), f.effects("heavy")
	local event = { kind = "preparing", owner = 10, life = 7, swingId = 1, direction = forward, startedAt = 100, hitAt = 100.65, expiresAt = 101.25 }
	normal.event(event); heavy.event(event); assert(#f.faces == 1)
	local heavyEvent = table.clone(event); heavyEvent.style = "heavy"
	heavy.event(heavyEvent); normal.event(heavyEvent); assert(#f.faces == 2)
	f.frame(0.3); local current = f.motors.RightShoulder.Transform
	local ended = table.clone(event); ended.kind, ended.reason = "ended", "paused"
	normal.event(ended); assert(f.motors.RightShoulder.Transform == current and not f.faces[2].destroyed)
	local contact = table.clone(heavyEvent); contact.kind = "contact"; heavy.event(contact)
	assert(f.impacts[2].variant == "heavy" and #f.impacts[2].hits == 1 and #f.impacts[1].hits == 0)
	ended.style = "heavy"; heavy.event(ended); f.restored()
	normal.destroy(); heavy.destroy(); f.pose.destroy()
end)
print(string.format("%d Heavy pose/presentation contract tests passed", total))
