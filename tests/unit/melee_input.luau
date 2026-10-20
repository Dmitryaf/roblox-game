--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector2, Vector3, CFrame = rb.Vector2, rb.Vector3, rb.CFrame
local source = fs.readFile("src/client/input/MeleeInput.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
	local f = { classId = "warrior", mouse = Vector2.new(500, 336), actions = {}, swings = {}, rays = {}, focused = nil, unbound = {} }
	f.hit = { Position = Vector3.new(12, 20, -16) }
	local root = { Position = Vector3.new(2, 3, 4), CFrame = CFrame.identity }
	function root:IsA(class) return class == "BasePart" end
	local character = {}; function character:FindFirstChild() return root end
	function character:GetAttribute() return f.classId end
	local gui = {}; function gui:GetGuiObjectsAtPosition(x, y)
		return if x >= 40 and x <= 220 and y >= 160 and y <= 190 then { { IsA = function(_, class) return class == "GuiButton" end } } else {}
	end
	local player = { Character = character }; function player:FindFirstChildOfClass() return gui end
	local camera = {}; function camera:ViewportPointToRay(x, y)
		table.insert(f.rays, Vector2.new(x, y)); return { Origin = Vector3.new(0, 6, 10), Direction = Vector3.new(0.2, 0.4, -1).Unit }
	end
	local world = { CurrentCamera = camera }; function world:Raycast(_, direction, params)
		assert(params.FilterDescendantsInstances[1] == character and params.FilterType == "Exclude" and math.abs(direction.Magnitude - 500) < 0.001)
		return f.hit
	end
	local actions = {}; function actions:BindAction(name, callback, touch, key)
		assert(not touch); f.actions[name] = { callback = callback, key = key }
	end
	function actions:UnbindAction(name) f.actions[name] = nil; table.insert(f.unbound, name) end
	local input = {}; function input:GetMouseLocation() return f.mouse end; function input:GetFocusedTextBox() return f.focused end
	local guiService = {}; function guiService:GetGuiInset() return Vector2.new(0, 36), Vector2.new(0, 0) end
	local services = { ContextActionService = actions, UserInputService = input, GuiService = guiService }
	local game = {}; function game:GetService(name) return assert(services[name]) end
	local module = luau.load(source, { environment = { game = game, workspace = world, Vector3 = Vector3,
		RaycastParams = { new = function() return {} end }, Enum = { ContextActionResult = { Pass = "Pass", Sink = "Sink" },
			UserInputState = { Begin = "Begin" }, UserInputType = { MouseButton1 = "MouseButton1" }, RaycastFilterType = { Exclude = "Exclude" } },
	} })()
	f.stop = module.bind(player, function(direction) table.insert(f.swings, direction) end)
	function f.press(state) local action = f.actions.WarriorSwing; return if action then action.callback("WarriorSwing", state or "Begin") else "Pass" end
	return f
end
test("warrior LMB flattens cursor aim to a unit horizontal direction", function()
	local f = fixture()
	assert(f.actions.WarriorSwing.key == "MouseButton1" and f.press() == "Sink")
	local expected = Vector3.new(10, 0, -20).Unit
	assert(#f.swings == 1 and (f.swings[1] - expected).Magnitude < 0.0001 and f.swings[1].Y == 0)
	assert(f.rays[1] == Vector2.new(500, 336)); f.stop()
end)
test("warlock and unknown classes pass LMB through to their own bindings", function()
	local f = fixture(); f.classId = "warlock"; assert(f.press() == "Pass")
	f.classId = nil; assert(f.press() == "Pass" and #f.swings == 0 and #f.rays == 0); f.stop()
end)
test("GUI inset, text focus and key release prevent accidental attacks", function()
	local f = fixture(); f.mouse = Vector2.new(100, 216); assert(f.press() == "Pass")
	f.mouse = Vector2.new(500, 336); f.focused = {}; assert(f.press() == "Pass")
	f.focused = nil; assert(f.press("End") == "Pass" and #f.swings == 0); f.stop()
end)
test("vertical cursor target uses the character's horizontal facing without NaN", function()
	local f = fixture(); f.hit = { Position = Vector3.new(2, 30, 4) }
	assert(f.press() == "Sink" and f.swings[1] == Vector3.new(0, 0, -1)); f.stop()
end)
test("sky aim remains horizontal and cleanup leaves arrow bindings alone", function()
	local f = fixture(); f.hit = nil; f.actions.CastArrow = {}
	assert(f.press() == "Sink" and f.swings[1].Y == 0 and math.abs(f.swings[1].Magnitude - 1) < 0.0001)
	f.stop(); assert(#f.unbound == 1 and f.unbound[1] == "WarriorSwing" and f.actions.CastArrow ~= nil)
	assert(f.press() == "Pass")
end)
print(string.format("%d MeleeInput interaction tests passed", total))
