--!strict
-- Real Controller + Effects + shared MeleePose. World physics is deliberately read-only.
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = rb.Vector3, rb.CFrame
local function module(name, env) return luau.load(fs.readFile("src/client/" .. name .. ".luau"), { environment = env })() end
local motions = {}
for _, name in { "MeleeMotion", "HeavyMotion", "DashPoseMotion", "PreparationTimeline" } do motions[name] = module("presentation/" .. name, { Vector3 = Vector3 }) end
local function signal()
	local list, event = {}, {}
	function event:Connect(callback)
		local connection = { Connected = true }; function connection:Disconnect() self.Connected = false end
		table.insert(list, { connection, callback }); return connection
	end
	function event.fire(...) for _, item in list do if item[1].Connected then item[2](...) end end end
	return event
end
local function difference(a, b) local _, angle = a:ToObjectSpace(b):ToAxisAngle(); return math.abs(angle) + (a.Position - b.Position).Magnitude end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local total = 0
local function test(name, action) action(); total += 1; print("PASS", name) end
local forward = Vector3.new(0, 0, -1)
local function fixture()
	local f = { time = 100, life = 7, classId = "warrior", motors = {}, base = {}, objects = {}, sent = {}, faces = 0, ruptures = 0 }
	local character = { Parent = true }; f.character = character
	function character:GetAttribute(name) return if name == "CombatLife" then f.life else f.classId end
	f.human = { Parent = character, Health = 100, MoveDirection = forward, AutoRotate = true }
	f.rootData = { Parent = character, Anchored = false, Position = Vector3.new(12, 3, 4), CFrame = CFrame.new(12, 3, 4), AssemblyLinearVelocity = Vector3.new(0, 4, -16) }
	f.root = setmetatable({}, { __index = function(_, key) return if key == "IsA" then function(_, name) return name == "BasePart" end else f.rootData[key] end,
		__newindex = function(_, key) error("Dash preparation wrote physical root: " .. key) end })
	function character:FindFirstChildOfClass() return f.human end
	function character:FindFirstChild() return f.root end
	local descendants = {}
	for _, name in { "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightHip", "LeftHip" } do
		local motor = { Parent = character, Name = name, Transform = CFrame.Angles(0.03, 0.05, 0.02), C0 = CFrame.identity }
		function motor:IsA(kind) return kind == "Motor6D" end
		f.motors[name], f.base[name] = motor, motor.Transform; table.insert(descendants, motor)
	end
	function character:GetDescendants() return descendants end
	f.player = { UserId = 10, Character = character }
	local players = { LocalPlayer = f.player }; function players:GetPlayerByUserId(owner) return if owner == 10 then f.player else nil end
	f.render, f.heartbeat, f.messages = signal(), signal(), signal()
	local services = { Players = players, RunService = { RenderStepped = f.render, Heartbeat = f.heartbeat } }
	f.game = {}; function f.game:GetService(name) return services[name] end
	f.world = {}; function f.world:GetServerTimeNow() return f.time end
	local dependencies = table.clone(motions)
	dependencies.MeleeFacing = { new = function() f.faces += 1; return { step = function() end, destroy = function() end } end }
	local names = {}; for name in dependencies do names[name] = name end
	f.pose = module("presentation/MeleePose", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame,
		script = { Parent = names }, require = function(name) return assert(dependencies[name]) end }).new(true)
	local instance = { new = function(kind)
		assert(kind ~= "LinearVelocity" and kind ~= "VectorForce" and kind ~= "AlignPosition", "Preview created physical mover")
		local value = { ClassName = kind, Play = function() end, Destroy = function(self) self.destroyed = true; self.Parent = nil end }
		table.insert(f.objects, value); return value
	end }
	local rupture = { new = function()
		f.ruptures += 1
		return { finish = function() end, destroy = function() end, step = function() return true end }
	end }
	f.effects = module("presentation/DashEffects", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame, Color3 = rb.Color3,
		ColorSequence = rb.ColorSequence, NumberSequence = rb.NumberSequence, Instance = instance,
		script = { Parent = { DashRupture = "Rupture", MeleePose = "Pose" } }, require = function(name) return if name == "Rupture" then rupture else {} end }).new(f.pose)
	function f.state(fields)
		local value = { life = f.life, alive = true, suspended = false, readyAt = 0, active = {} }
		for key, item in fields or {} do value[key] = item end; return value
	end
	function f.event(request, id)
		return { kind = "started", owner = 10, life = f.life, dashId = id or 1, requestId = request, direction = forward,
			duration = 0.28, startedAt = f.time, expiresAt = f.time + 0.28, readyAt = f.time + 5 }
	end
	function f.tick(at)
		f.time = at; f.pose.beforePose(); f.pose.afterPose(at, 1 / 60); f.render.fire()
	end
	function f.restored() for name, motor in f.motors do assert(difference(motor.Transform, f.base[name]) < 0.00001, "Not restored: " .. name) end end
	function f.controller()
		local remote = { OnClientEvent = f.messages }; function remote:FireServer(request) table.insert(f.sent, request) end
		local hud = { show = function(status, note) f.status, f.note = status, note end, destroy = function() end }
		f.stop = module("controllers/DashController", { game = f.game, workspace = f.world }).start(f.player, remote, hud, f.effects,
			function(_, callback) f.cast = callback; return function() end end)
		f.messages.fire({ kind = "reply", requestId = f.sent[1].requestId, state = f.state(), ok = true, life = f.life })
	end
	function f.reply(request, state, ok, reason)
		f.messages.fire({ kind = "reply", requestId = request, state = state, ok = ok ~= false, reason = reason, life = state.life })
	end
	function f.destroy() if f.stop then f.stop() else f.effects.destroy() end; f.pose.destroy(); f.restored() end
	return f
end

test("real E prepares a bounded brace before server approval without movement facing or launch VFX", function()
	local f = fixture(); f.controller(); local count = #f.objects
	f.cast(forward); assert(#f.sent == 2 and f.pose.active(10))
	f.tick(100.016); assert(difference(f.motors.RightShoulder.Transform, f.base.RightShoulder) > 0.02)
	f.tick(100.04); local held = f.motors.RightShoulder.Transform
	for _, at in { 100.2, 100.8, 102.4 } do f.tick(at); assert(difference(held, f.motors.RightShoulder.Transform) < 0.00001) end
	assert(#f.objects == count and f.ruptures == 0 and f.faces == 0 and f.human.AutoRotate)
	assert(f.root.AssemblyLinearVelocity == Vector3.new(0, 4, -16) and f.root.CFrame == CFrame.new(12, 3, 4))
	assert(f.motors.RightHip.Transform == f.base.RightHip and f.motors.LeftHip.Transform == f.base.LeftHip)
	f.destroy()
end)

test("matching confirmation adopts the held pose without a neutral frame or a second start", function()
	local f = fixture(); assert(f.effects.preview(21, 7, forward)); f.tick(100.2)
	local before = f.motors.RightShoulder.Transform
	local event = f.event(21, 8); f.effects.event(event)
	assert(f.motors.RightShoulder.Transform == before and f.faces == 0)
	f.tick(100.2); near(difference(before, f.motors.RightShoulder.Transform), 0)
	f.tick(100.26); local driven = f.motors.RightShoulder.Transform
	assert(difference(before, driven) > 0.1)
	f.effects.event(table.clone(event)); f.effects.sync({ table.clone(event) }); f.pose.beginDash(10, 0.28, forward, 8, 21)
	f.tick(100.26); near(difference(driven, f.motors.RightShoulder.Transform), 0)
	f.effects.cancelPreview(21); assert(f.pose.active(10), "Late denial erased accepted dash")
	f.tick(100.481); assert(not f.pose.active(10)); f.destroy()
end)

test("a reply snapshot can adopt before the broadcast without restarting when the broadcast arrives", function()
	local f = fixture(); f.controller(); f.cast(forward); local request = f.sent[2].requestId; f.tick(100.15)
	local held = f.motors.RightShoulder.Transform; local event = f.event(request, 9)
	f.reply(request, f.state({ readyAt = 105, active = { event } }), true)
	f.tick(100.15); near(difference(held, f.motors.RightShoulder.Transform), 0)
	f.tick(100.2); local during = f.motors.RightShoulder.Transform
	f.messages.fire(event); f.tick(100.2); near(difference(during, f.motors.RightShoulder.Transform), 0)
	assert(f.ruptures == 1); f.destroy()
end)

test("local cooldown active and pending gates do not send repeated E or create another preview", function()
	local f = fixture(); f.controller(); f.cast(forward); f.cast(forward); assert(#f.sent == 2)
	f.tick(100.1); local event = f.event(f.sent[2].requestId, 1)
	f.reply(f.sent[2].requestId, f.state({ readyAt = 105, active = { event } }), true)
	f.cast(forward); assert(#f.sent == 2)
	f.tick(100.5); f.cast(forward); assert(#f.sent == 2 and not f.pose.active(10))
	f.tick(105.01); f.cast(forward); assert(#f.sent == 3 and f.pose.active(10)); f.destroy()
end)

test("denial and missing confirmation restore the pose with no launch and cannot confirm an old retry", function()
	local f = fixture(); f.controller(); f.cast(forward); local old = f.sent[2].requestId
	f.tick(100.08); f.reply(old, f.state(), false, "blocked"); assert(not f.pose.active(10)); f.restored()
	f.cast(forward); local lost = f.sent[3].requestId; f.tick(102.7)
	assert(not f.pose.active(10) and f.sent[#f.sent].action == "sync" and f.ruptures == 0)
	local syncId = f.sent[#f.sent].requestId; f.reply(syncId, f.state(), true); f.cast(forward)
	local newest = f.sent[#f.sent].requestId; f.tick(102.75)
	f.reply(lost, f.state(), false, "blocked"); f.messages.fire(f.event(old, 10))
	assert(f.pose.active(10) and f.ruptures == 0 and newest > lost)
	f.reply(newest, f.state(), false, "blocked"); assert(not f.pose.active(10)); f.destroy()
end)

test("death pause class and new-life resets remove only the preview and never create delayed launch", function()
	for _, cause in { "death", "pause", "class", "life", "anchored" } do
		local f = fixture(); f.controller(); f.cast(forward); local request = f.sent[2].requestId; f.tick(100.1)
		if cause == "death" then f.human.Health = 0
		elseif cause == "pause" then f.messages.fire({ kind = "snapshot", state = f.state({ suspended = true }) })
		elseif cause == "class" then f.classId = "warlock"
		elseif cause == "life" then f.life = 8; f.messages.fire({ kind = "snapshot", state = f.state() })
		else f.rootData.Anchored = true end
		f.tick(100.2); assert(not f.pose.active(10)); f.restored(); assert(f.ruptures == 0)
		f.effects.cancelPreview(request); f.destroy()
	end
end)

test("dash preview rejection and cancellation preserve an unrelated melee or heavy action", function()
	for _, kind in { "melee", "heavy" } do
		local f = fixture()
		if kind == "heavy" then f.pose.beginHeavy(10, 100.65, 100, 101.25, forward, 50)
		else f.pose.begin(10, 100.3, 100, 100.75, forward, 50) end
		f.tick(100.1); local held = f.motors.RightShoulder.Transform
		assert(not f.effects.preview(2, 7, forward)); f.effects.cancelPreview(); f.effects.cancelPreview(2)
		assert(f.pose.active(10) and f.motors.RightShoulder.Transform == held)
		f.effects.destroy(); assert(f.pose.active(10)); f.pose.destroy(); f.restored()
	end
end)

test("direct wrong request and stale life cannot adopt the newer dash preview", function()
	local f = fixture(); assert(not f.pose.previewDash(10, 2, 6, forward))
	assert(f.pose.previewDash(10, 2, 7, forward) and not f.pose.previewDash(10, 3, 7, forward)); f.tick(100.1)
	local held = f.motors.RightShoulder.Transform
	f.pose.beginDash(10, 0.28, forward, 99, 1); f.tick(100.1); near(difference(held, f.motors.RightShoulder.Transform), 0)
	f.life = 8; f.pose.beginDash(10, 0.28, forward, 99, 2); f.tick(100.2); assert(not f.pose.active(10)); f.destroy()
end)

print(string.format("%d Dash preparation boundary tests passed", total))
