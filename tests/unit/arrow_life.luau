--!strict
-- Real ArrowController/ArrowEffects/CastPose; engine rendering and appearance are boundary mocks.
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local V, C = rb.Vector3, rb.CFrame
local function module(path, env) return luau.load(fs.readFile("src/" .. path .. ".luau"), { environment = env })() end
local Timeline = module("client/presentation/PreparationTimeline", {})
local function signal()
	local list, event = {}, {}
	function event:Connect(callback)
		local connection = { Connected = true }; function connection:Disconnect() self.Connected = false end
		table.insert(list, { connection, callback }); return connection
	end
	function event.fire(...) for _, item in list do if item[1].Connected then item[2](...) end end end
	return event
end
local total = 0
local function test(name, action) action(); total += 1; print("PASS", name) end
local forward = V.new(0, 0, -1)
local function angle(a, b) local _, value = a:ToObjectSpace(b):ToAxisAngle(); return math.abs(value) end
local function fixture()
	local f = { time = 100, bodies = {}, players = {}, visuals = {}, appearance = {}, appearancesStopped = {}, objects = {}, sent = {}, forwarded = {}, bursts = 0 }
	f.render, f.heartbeat, f.messages = signal(), signal(), signal()
	function f.body(owner, life)
		local body = { life = life, classId = "warlock", rootPresent = true, motors = {}, base = {} }
		local character = { Parent = true }; body.character = character
		function character:GetAttribute(name) return if name == "CombatLife" then body.life else body.classId end
		body.human = { Health = 100 }
		body.rootData = { Parent = character, Anchored = false, CFrame = C.new(10, 3, 0), Position = V.new(10, 3, 0) }
		body.root = setmetatable({}, { __index = function(_, key) return if key == "IsA" then function(_, kind) return kind == "BasePart" end else body.rootData[key] end,
			__newindex = function(_, key) error("Arrow life presentation wrote physical root: " .. key) end })
		function character:FindFirstChild(name) return if name == "HumanoidRootPart" then (if body.rootPresent then body.root else nil) else if name == "UpperTorso" then {} else nil end
		function character:FindFirstChildOfClass() return body.human end
		local descendants = {}
		for _, name in { "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow" } do
			local joint = { Name = name, Parent = character, Transform = C.Angles(0.02, 0.03, 0.01), C0 = C.identity }
			function joint:IsA(kind) return kind == "Motor6D" end
			body.motors[name], body.base[name] = joint, joint.Transform; table.insert(descendants, joint)
		end
		function character:GetDescendants() return descendants end
		local player = f.players[owner] or { UserId = owner }; player.Character = character; f.players[owner], f.bodies[owner] = player, body
		return body
	end
	f.body(1, 7); f.body(2, 20)
	local players = { LocalPlayer = f.players[1] }; function players:GetPlayerByUserId(owner) return f.players[owner] end
	local services = { Players = players, RunService = { RenderStepped = f.render, Heartbeat = f.heartbeat }, Debris = { AddItem = function() end },
		ReplicatedStorage = { Shared = { presentation = { ArrowStyle = "Style" } } } }
	f.game = {}; function f.game:GetService(name) return services[name] end
	f.world = {}; function f.world:GetServerTimeNow() return f.time end
	f.pose = module("client/presentation/CastPose", { game = f.game, workspace = f.world, Vector3 = V, CFrame = C,
		script = { Parent = { PreparationTimeline = "Timeline" } }, require = function(name) assert(name == "Timeline"); return Timeline end }).new(nil, true)
	local dependencies = { Style = { sounds = {} }, CastPose = {}, Matter = {},
		WarlockAppearance = { new = function() return {
			cast = function(owner) f.appearance[owner] = f.bodies[owner].life end,
			stop = function(owner) f.appearance[owner] = nil; f.appearancesStopped[owner] = (f.appearancesStopped[owner] or 0) + 1 end,
			step = function() end, destroy = function() end } end },
		ChaosArrow = { new = function(_, event, flying)
			local visual = { event = event, flying = flying, attachedLife = f.bodies[event.owner].life, character = f.players[event.owner].Character,
				step = function() end, destroy = function(self) end }
			function visual.destroy() visual.destroyed = true end
			table.insert(f.visuals, visual); return visual
		end }, ChaosImpact = { new = function() f.bursts += 1; return { step = function() return false end } end } }
	f.instance = { new = function(kind)
		assert(kind ~= "LinearVelocity" and kind ~= "VectorForce", "Presentation created movement")
		local object = { ClassName = kind, Destroy = function(self) self.destroyed = true; self.Parent = nil end, Play = function() end }
		table.insert(f.objects, object); return object
	end }
	local names = {}; for name in dependencies do names[name] = name end
	names.ChaosMatter = "Matter"
	f.effects = module("client/presentation/ArrowEffects", { game = f.game, workspace = f.world, Vector3 = V, Instance = f.instance,
		script = { Parent = names }, require = function(name) return assert(dependencies[name]) end }).new(f.pose)
	function f.event(owner, life, id, kind)
		return { kind = kind or "preparing", owner = owner, life = life, castId = id, requestId = id + 10, startedAt = 100,
			launchAt = 100.7, expiresAt = 103.2, position = if kind == "flying" or kind == "launched" then V.new(10, 3, -10) else nil,
			direction = forward, speed = 58, readyAt = 104 }
	end
	function f.state(active, life) return { life = life or f.bodies[1].life, alive = true, suspended = false, readyAt = 0, active = active or {} } end
	function f.tick(at) f.time = at; f.pose.beforePose(); f.pose.afterPose(at); f.effects.step(at) end
	function f.controller()
		local remote = { OnClientEvent = f.messages }; function remote:FireServer(request) table.insert(f.sent, request) end
		local hud = { show = function(status) f.status = status end, destroy = function() end }
		f.stop = module("client/controllers/ArrowController", { game = f.game, workspace = f.world }).start(f.players[1], remote, hud, f.effects,
			function(_, cast, teleport, transfer) f.cast, f.teleport, f.transfer = cast, teleport, transfer; return function() end end)
		f.messages.fire({ kind = "snapshot", state = f.state() })
	end
	function f.destroy() if f.stop then f.stop() else f.effects.destroy() end; f.pose.destroy() end
	return f
end

test("old preparing cannot attach to a newer foreign body or animate its joints", function()
	local f = fixture(); f.body(2, 21); f.controller()
	f.messages.fire(f.event(2, 20, 1)); f.tick(100.1)
	assert(#f.visuals == 0 and not f.pose.active(2) and f.appearance[2] == nil)
	f.messages.fire({ kind = "snapshot", state = f.state({ f.event(2, 20, 1) }) }); f.tick(100.2)
	assert(#f.visuals == 0 and not f.pose.active(2)); f.destroy()
end)

test("future-life event waits for the right body class and root then recovers once", function()
	local f = fixture(); f.controller(); local event = f.event(2, 21, 1)
	f.messages.fire(event); f.tick(100.1); assert(#f.visuals == 0 and not f.pose.active(2))
	local body = f.body(2, 21); body.rootPresent = false; body.classId = "warrior"
	f.tick(100.2); assert(#f.visuals == 0)
	body.rootPresent = true; body.classId = "warlock"; f.tick(100.3); f.tick(100.32)
	assert(#f.visuals == 1 and f.visuals[1].attachedLife == 21 and f.pose.active(2) and f.appearance[2] == 21)
	assert(angle(body.motors.RightShoulder.Transform, body.base.RightShoulder) > 0.1)
	f.messages.fire(event); f.effects.sync({ event }); assert(#f.visuals == 1); f.destroy()
end)

test("late ended expiry and old snapshot removal cannot stop the newer accepted owner pose", function()
	for _, source in { "ended", "expiry", "snapshot" } do
		local f = fixture(); local old = f.event(2, 20, 1); f.effects.event(old)
		local nextEvent = f.event(2, 20, 2); nextEvent.startedAt, nextEvent.launchAt, nextEvent.expiresAt = 100.1, 100.9, 104
		if source == "expiry" then old.expiresAt = 100.15 end
		f.effects.event(nextEvent); f.tick(100.12)
		local stopped = f.appearancesStopped[2] or 0
		if source == "ended" then local ending = f.event(2, 20, 1, "ended"); ending.reason = "reset"; f.effects.event(ending)
		elseif source == "expiry" then f.tick(100.2)
		else f.effects.sync({ nextEvent }) end
		assert(f.pose.active(2) and f.appearance[2] == 20 and (f.appearancesStopped[2] or 0) == stopped,
			"Old " .. source .. " stopped a newer cast")
		assert(f.visuals[1].destroyed and not f.visuals[2].destroyed); f.destroy()
	end
end)

test("old-life ended can remove its visual without stopping a new-body preview or replaying stale impact", function()
	local f = fixture(); f.effects.event(f.event(1, 7, 1)); f.body(1, 8)
	f.pose.step(100.1); assert(f.effects.preview(50, 8, forward)); f.tick(100.15)
	local ending = f.event(1, 7, 1, "ended"); ending.reason = "dead"; f.effects.event(ending)
	assert(f.pose.active(1) and f.visuals[1].destroyed)
	ending.reason, ending.position = "hit", V.zero; f.effects.event(ending); assert(f.bursts == 0)
	f.effects.cancelPreview(49); assert(f.pose.active(1)); f.effects.cancelPreview(50); assert(not f.pose.active(1)); f.destroy()
end)

test("pending future visuals are bounded expired retired and destroyed without later attachment", function()
	local f = fixture()
	for id = 1, 30 do f.effects.event(f.event(2, 21, id)) end
	f.body(2, 21); f.tick(100.1); assert(#f.visuals == 24, "Future visual queue exceeded its finite cap"); f.destroy()
	for _, scenario in { "timeout", "expiry", "ended", "newer_life", "destroy" } do
		local g = fixture(); local event = g.event(2, 21, 1)
		if scenario == "expiry" then event.expiresAt = 100.15 end
		g.effects.event(event)
		if scenario == "ended" then local ended = g.event(2, 21, 1, "ended"); ended.reason = "reset"; g.effects.event(ended)
		elseif scenario == "newer_life" then g.body(2, 22); g.tick(100.1)
		elseif scenario == "destroy" then g.effects.destroy()
		else g.tick(if scenario == "expiry" then 100.16 else 102.01) end
		g.body(2, 21); g.tick(102.1); assert(#g.visuals == 0, "Discarded future visual reattached after " .. scenario); g.destroy()
	end
end)

test("a queued flying phase cannot regress into old preparing or replay on a retired cast", function()
	local f = fixture(); f.effects.event(f.event(2, 21, 1, "flying")); f.effects.event(f.event(2, 21, 1))
	f.body(2, 21); f.tick(100.2); assert(#f.visuals == 1 and f.visuals[1].flying and not f.pose.active(2))
	local ended = f.event(2, 21, 1, "ended"); ended.reason = "hit"; f.effects.event(ended)
	f.effects.event(f.event(2, 21, 1)); assert(#f.visuals == 1); f.destroy()
end)

test("own reply request correlation and a new life preserve the current pending preview", function()
	local f = fixture(); f.controller(); f.cast(forward); local first = f.sent[#f.sent]
	f.messages.fire({ kind = "reply", requestId = first.requestId - 1, life = 7, state = f.state(), ok = false })
	assert(f.pose.active(1)); f.cast(forward); assert(f.sent[#f.sent] == first)
	f.messages.fire({ kind = "reply", requestId = first.requestId, life = 7, state = f.state(), ok = false, reason = "blocked" })
	assert(not f.pose.active(1))
	f.body(1, 8); f.messages.fire({ kind = "snapshot", state = f.state() }); f.cast(forward); local current = f.sent[#f.sent]
	f.messages.fire({ kind = "reply", requestId = first.requestId, life = 7, state = f.state({}, 7), ok = false })
	assert(f.pose.active(1) and current.requestId > first.requestId)
	local accepted = f.event(1, 8, 3); accepted.requestId = current.requestId
	f.messages.fire({ kind = "reply", requestId = current.requestId, life = 8, state = f.state({ accepted }), ok = true })
	f.effects.cancelPreview(current.requestId); assert(f.pose.active(1)); f.destroy()
end)

test("snapshot foreign owner lives remain independent of ours and never regress after a newer event", function()
	local f = fixture(); f.controller(); f.body(2, 21)
	f.messages.fire(f.event(2, 21, 2)); assert(#f.visuals == 1)
	f.messages.fire({ kind = "snapshot", state = f.state({ f.event(2, 20, 1), f.event(2, 21, 2) }) })
	assert(#f.visuals == 1 and not f.visuals[1].destroyed)
	f.messages.fire(f.event(2, 20, 3)); assert(#f.visuals == 1); f.destroy()
end)

test("external Hands cast remains compatible and an old arrow cannot stop that shared pose", function()
	local f = fixture(); local old = f.event(1, 7, 1); f.effects.event(old)
	f.effects.prepare(1, 100.8, forward, 100.1); f.tick(100.2)
	local ended = f.event(1, 7, 1, "ended"); ended.reason = "reset"; f.effects.event(ended)
	assert(f.pose.active(1) and f.appearance[1] == 7)
	f.effects.stopCast(1); assert(not f.pose.active(1) and f.appearance[1] == nil); f.destroy()
end)

test("real melee and heavy crescents cover the configured range and 100 degree arc", function()
	for _, style in { "melee", "heavy" } do
		local f = fixture()
		f.bodies[1].classId = "warrior"
		local config = module("server/config/" .. (if style == "heavy" then "Heavy" else "Warrior"), {})
		local swordPose = { begin = function() end, beginHeavy = function() end, stop = function() end, step = function() end }
		local impact = { new = function() return { hit = function() end, cancel = function() end, step = function() end, destroy = function() end } end }
		local effects = module("client/presentation/MeleeEffects", { game = f.game, workspace = f.world, Vector3 = V, CFrame = C, Color3 = rb.Color3,
			ColorSequence = rb.ColorSequence, NumberSequence = rb.NumberSequence, Instance = f.instance, Enum = { Material = { Neon = "Neon" } },
			script = { Parent = { MeleePose = "Pose", MeleeImpact = "Impact" } }, require = function(name) return if name == "Impact" then impact else {} end,
		}).new(swordPose, if style == "heavy" then "heavy" else nil)
		local event = { kind = "preparing", owner = 1, life = 7, swingId = 1, direction = forward, style = if style == "heavy" then "heavy" else nil,
			startedAt = 100, hitAt = 100 + config.windup, expiresAt = 100 + config.windup + config.recovery }
		effects.event(event); f.time = event.hitAt; effects.step(f.time)
		local count, low, high = 0, math.huge, -math.huge
		for _, object in f.objects do
			if object.ClassName ~= "Attachment" or not object.Position or not object.Parent or object.Parent.Name ~= (if style == "heavy" then "WarriorHeavySwing" else "WarriorSwing") then continue end
			local point = object.Position; count += 1
			assert(math.abs((point * V.new(1, 0, 1)).Magnitude - config.range) < 0.0001, "Visual crescent radius mismatches actual server range")
			local radians = math.atan2(point.X, -point.Z); low, high = math.min(low, radians), math.max(high, radians)
		end
		assert(count == 10 and math.abs(math.deg(high - low) - config.arcDegrees) < 0.001)
		effects.destroy(); f.destroy()
	end
end)

test("redirect replaces flight visual once and stale launch cannot undo it", function()
	local f = fixture(); f.controller()
	local launch = f.event(1, 7, 1, "launched"); f.messages.fire(launch)
	local redirect = table.clone(launch); redirect.kind, redirect.redirected, redirect.damageOwner = "redirected", true, 2
	redirect.position, redirect.direction, redirect.sampledAt = V.new(10, 3, -20), -forward, 101
	f.messages.fire(redirect)
	assert(#f.visuals == 2 and f.visuals[1].destroyed and f.visuals[2].flying)
	f.messages.fire(redirect); f.messages.fire(launch)
	assert(#f.visuals == 2 and not f.visuals[2].destroyed)
	f.teleport(); assert(f.sent[#f.sent].action == "teleport" and f.sent[#f.sent].castId == 1)
	f.destroy()
end)

print(string.format("%d arrow life/visual geometry boundary tests passed", total))
