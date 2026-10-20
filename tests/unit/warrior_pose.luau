--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = rb.Vector3, rb.CFrame
local MeleeMotion = luau.load(fs.readFile("src/client/presentation/MeleeMotion.luau"), { environment = { Vector3 = Vector3 } })()
local DashMotion = luau.load(fs.readFile("src/client/presentation/DashPoseMotion.luau"), { environment = { Vector3 = Vector3 } })()
local source = fs.readFile("src/client/presentation/MeleePose.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function signal()
	local listeners, event = {}, {}
	function event:Connect(callback)
		local connection = { Connected = true }; function connection:Disconnect() self.Connected = false end
		table.insert(listeners, { connection, callback }); return connection
	end
	function event.fire(...) for _, value in listeners do if value[1].Connected then value[2](...) end end end
	function event.count() local n = 0; for _, value in listeners do if value[1].Connected then n += 1 end end; return n end
	return event
end
local function difference(a, b)
	local _, angle = (a:Inverse() * b):ToAxisAngle()
	return math.abs(angle) + (a.Position - b.Position).Magnitude
end
local function fixture()
	local f = { time = 100, classId = "warrior", life = 7, motors = {}, base = {}, legs = {}, faces = {} }
	f.animation, f.simulation = signal(), signal()
	local character = { Parent = true }
	f.character = character
	function character:GetAttribute(name) return if name == "CombatClass" then f.classId else f.life end
	local humanoid = { Parent = character, Health = 100, MoveDirection = Vector3.new(0, 0, -1), AutoRotate = true }
	f.humanoid = humanoid
	local rootData = { Parent = character, Anchored = false, CFrame = CFrame.new(12, 3, 4), AssemblyLinearVelocity = Vector3.new(0, 4, -16) }
	local root = setmetatable({}, {
		__index = function(_, key) return if key == "IsA" then function(_, name) return name == "BasePart" end else rootData[key] end,
		__newindex = function(_, key) error("Pose must not write root " .. key) end,
	})
	f.root, f.rootData = root, rootData
	function character:FindFirstChildOfClass() return humanoid end
	function character:FindFirstChild() return root end
	local descendants = {}
	for index, name in { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "RightHip", "LeftHip", "RightKnee", "LeftKnee" } do
		local motor = { Name = name, Parent = character, C0 = CFrame.Angles(0.12, 0.06, 0.03), Transform = CFrame.Angles(index * 0.013, 0.08, -0.04) }
		function motor:IsA(kind) return kind == "Motor6D" end
		f.motors[name], f.base[name] = motor, motor.Transform
		if index > 7 then f.legs[name] = true end
		table.insert(descendants, motor)
	end
	function character:GetDescendants() return descendants end
	local player = { Character = character }
	f.player = player
	local players = { LocalPlayer = player }; function players:GetPlayerByUserId(owner) return if owner == 10 then player else nil end
	local facing = {}
	function facing.new()
		humanoid.AutoRotate = false
		local entry = { steps = 0, destroyed = false }
		function entry.step() entry.steps += 1 end
		function entry.destroy() entry.destroyed = true; humanoid.AutoRotate = true end
		table.insert(f.faces, entry); return entry
	end
	local game = {}; function game:GetService(name) return if name == "Players" then players else { PreAnimation = f.animation, PreSimulation = f.simulation } end
	local world = {}; function world:GetServerTimeNow() return f.time end
	local modules = { MeleeMotion = MeleeMotion, DashPoseMotion = DashMotion, MeleeFacing = facing }
	local module = luau.load(source, { environment = { game = game, workspace = world, Vector3 = Vector3, CFrame = CFrame,
		script = { Parent = { MeleeMotion = "MeleeMotion", DashPoseMotion = "DashPoseMotion", MeleeFacing = "MeleeFacing" } }, require = function(name) return assert(modules[name]) end,
	} })()
	f.pose = module.new()
	function f.frame(delta, animate)
		f.time += delta or 0.016
		f.animation.fire()
		if animate then
			for name, motor in f.motors do f.base[name] = CFrame.Angles((f.time - 100) * 0.1, 0.08, -0.04); motor.Transform = f.base[name] end
		end
		f.simulation.fire(delta or 0.016)
	end
	function f.restored()
		for name, motor in f.motors do assert(difference(motor.Transform, f.base[name]) < 0.00001, "Not restored: " .. name) end
	end
	return f
end
local forward = Vector3.new(0, 0, -1)
test("late dash ended cannot cancel the newer sword pose and stale sword ids cannot cancel it either", function()
	local f = fixture(); f.pose.beginDash(10, 0.28, forward, 101); f.frame(0.08)
	assert(difference(f.motors.Waist.Transform, f.base.Waist) > 0.05)
	f.pose.begin(10, f.time + 0.3, f.time, f.time + 0.75, forward, 201); f.frame(0.12)
	local current = f.motors.RightShoulder.Transform
	f.pose.stop(10, "dash", 101); f.pose.stop(10, "melee", 200)
	assert(f.motors.RightShoulder.Transform == current and not f.faces[1].destroyed)
	f.frame(0.02); assert(difference(f.motors.RightShoulder.Transform, f.base.RightShoulder) > 0.1)
	f.pose.stop(10, "melee", 201); f.restored(); assert(f.faces[1].destroyed)
	f.pose.destroy()
end)
test("late sword ended cannot cancel the dash and a prior dash id cannot cancel its successor", function()
	local f = fixture(); f.pose.begin(10, 100.3, 100, 100.75, forward, 201); f.frame(0.1)
	f.pose.beginDash(10, 0.28, forward, 102); assert(f.faces[1].destroyed and f.humanoid.AutoRotate)
	f.frame(0.1); local current = f.motors.Waist.Transform
	f.pose.stop(10, "melee", 201); f.pose.stop(10, "dash", 101)
	assert(current == f.motors.Waist.Transform)
	f.frame(0.04); assert(difference(f.motors.Waist.Transform, f.base.Waist) > 0.3)
	f.pose.stop(10, "dash", 102); f.restored(); f.pose.destroy()
end)
test("dash animates a low upper-body drive over a full local duration without touching legs root physics or AutoRotate", function()
	for _, direction in { forward, Vector3.xAxis, -forward } do
		local f = fixture(); f.pose.beginDash(10, 0.28, direction, 101)
		f.frame(0.06, true); local brace = f.motors.Waist.Transform
		f.frame(0.08, true); assert(difference(f.motors.Waist.Transform, brace) > 0.1)
		assert(difference(f.motors.RightElbow.Transform, f.base.RightElbow) > 0.5)
		for name in f.legs do assert(f.motors[name].Transform == f.base[name], "Pose took ownership of running leg " .. name) end
		assert(f.humanoid.AutoRotate and #f.faces == 0 and f.root.AssemblyLinearVelocity == Vector3.new(0, 4, -16))
		f.frame(0.15, true); f.restored(); f.pose.destroy()
	end
end)
test("death class life change pause replacement and local duration expiry restore the current Animator basis", function()
	for _, reason in { "dead", "class", "life", "paused", "replacement", "expired" } do
		local f = fixture(); f.pose.beginDash(10, 0.28, forward, 1); f.frame(0.12, true)
		if reason == "dead" then f.humanoid.Health = 0
		elseif reason == "class" then f.classId = "warlock"
		elseif reason == "life" then f.life = 8
		elseif reason == "paused" then f.rootData.Anchored = true
		elseif reason == "replacement" then f.player.Character = nil
		else f.time += 0.2 end
		f.pose.step(f.time); f.restored(); f.pose.destroy()
	end
end)
test("cleanup restores only its own overlay and never overwrites a later Animator transform", function()
	local f = fixture(); f.pose.beginDash(10, 0.28, forward, 1); f.frame(0.14)
	local external = CFrame.Angles(0.7, 0.3, 0.1); f.motors.Waist.Transform = external
	f.pose.stop(10, "dash", 1); assert(f.motors.Waist.Transform == external)
	f.base.Waist = external; f.restored()
	f.pose.beginDash(10, 0.28, forward, 2); f.frame(0.1)
	f.pose.destroy(); f.restored(); assert(f.animation.count() == 0 and f.simulation.count() == 0)
end)
test("dash keys remain finite bounded and end in neutral pose with no lower-body channels", function()
	assert(DashMotion.time(105, 105, 105.28) == 0 and DashMotion.time(106, 105, 105.28) == 0.28)
	assert(DashMotion.weight(0) == 0 and DashMotion.weight(0.28) == 0)
	for _, channel in DashMotion.channels do
		for _, name in channel.names do assert(not name:find("Hip") and not name:find("Knee") and not name:find("Ankle")) end
		for index = 0, 280 do
			local value = DashMotion.sample(channel.keys, index / 1000)
			assert(value.X == value.X and value.Y == value.Y and value.Z == value.Z and value.Magnitude < 2)
		end
		assert(DashMotion.sample(channel.keys, 0.28).Magnitude == 0)
	end
end)
print(string.format("%d shared warrior pose lifecycle tests passed", total))
