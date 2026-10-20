--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector2, Vector3 = roblox.Vector2, roblox.Vector3
local source = fs.readFile("src/client/input/ArrowInput.luau")
local total = 0
local function test(name, run)
	run()
	total += 1
	print("PASS", name)
end
local function fixture()
	local f = { mouse = Vector2.new(100, 216), focused = nil, casts = {}, teleports = 0, actions = {}, unbound = {}, rays = {} }
	-- Geometry is expressed in GUI coordinates. The button is only 30px high:
	-- a raw screen click with the 36px top inset would miss this rectangle.
	local rectangles = {
		{ left = 40, top = 160, width = 180, height = 30, class = "GuiButton" },
		{ left = 260, top = 160, width = 120, height = 30, class = "TextLabel" },
	}
	local gui = {}
	function gui:GetGuiObjectsAtPosition(x, y)
		local hits = {}
		for _, rectangle in rectangles do
			if x >= rectangle.left and x <= rectangle.left + rectangle.width and y >= rectangle.top and y <= rectangle.top + rectangle.height then
				local object = {}
				function object:IsA(class) return rectangle.class == class end
				table.insert(hits, object)
			end
		end
		return hits
	end
	local root = { Position = Vector3.new(2, 3, 4) }
	function root:IsA(class) return class == "BasePart" end
	local character = {}; function character:GetAttribute() return f.classId end
	function character:FindFirstChild(name) return if name == "HumanoidRootPart" then root else nil end
	local player = { Character = character }
	function player:FindFirstChildOfClass(class) return if class == "PlayerGui" then gui else nil end
	local camera = {}
	function camera:ViewportPointToRay(x, y)
		table.insert(f.rays, Vector2.new(x, y))
		return { Origin = Vector3.new(0, 6, 10), Direction = Vector3.new(0, -0.1, -1).Unit }
	end
	local world = { CurrentCamera = camera }
	function world:Raycast(origin, direction, params)
		assert(origin == Vector3.new(0, 6, 10) and math.abs(direction.Magnitude - 500) < 0.001)
		assert(params.FilterType == "Exclude" and params.FilterDescendantsInstances[1] == character)
		return { Position = Vector3.new(20, 4, -30) }
	end
	local actions = {}
	function actions:BindAction(name, callback, touchButton, key)
		assert(not touchButton)
		f.actions[name] = { callback = callback, key = key }
	end
	function actions:UnbindAction(name)
		f.actions[name] = nil
		table.insert(f.unbound, name)
	end
	local input = {}
	function input:GetFocusedTextBox() return f.focused end
	function input:GetMouseLocation() return f.mouse end
	local guiService = {}
	function guiService:GetGuiInset() return Vector2.new(0, 36), Vector2.new(0, 0) end
	local services = { ContextActionService = actions, UserInputService = input, GuiService = guiService }
	local game = {}
	function game:GetService(name) return assert(services[name]) end
	local ArrowInput = luau.load(source, { debugName = "ArrowInput", environment = {
		game = game, workspace = world, Vector3 = Vector3, RaycastParams = { new = function() return {} end },
		Enum = { UserInputState = { Begin = "Begin" }, ContextActionResult = { Pass = "Pass", Sink = "Sink" },
			RaycastFilterType = { Exclude = "Exclude" }, UserInputType = { MouseButton1 = "MouseButton1" }, KeyCode = { E = "E" } },
	} })()
	f.stop = ArrowInput.bind(player, function(direction) table.insert(f.casts, direction) end, function() f.teleports += 1 end)
	function f.press(name, state)
		local action = f.actions[name]
		return if action then action.callback(name, state or "Begin") else "Pass"
	end
	return f
end

test("screen click over Ready button accounts for inset and never casts", function()
	local f = fixture()
	-- GUI point (100,180) lies inside the actual rectangle; raw y=216 is outside.
	assert(f.press("CastArrow") == "Pass")
	assert(#f.casts == 0 and #f.rays == 0)
	f.stop()
end)

test("world click casts a unit direction and preserves raw camera coordinates", function()
	local f = fixture(); f.mouse = Vector2.new(500, 336)
	assert(f.press("CastArrow") == "Sink")
	assert(#f.casts == 1 and #f.rays == 1 and f.rays[1] == Vector2.new(500, 336))
	local expected = (Vector3.new(20, 4, -30) - Vector3.new(2, 4, 4)).Unit
	assert((f.casts[1] - expected).Magnitude < 0.0001 and math.abs(f.casts[1].Magnitude - 1) < 0.0001)
	f.stop()
end)

test("decorative HUD label does not consume a world cast", function()
	local f = fixture(); f.mouse = Vector2.new(300, 216)
	assert(f.press("CastArrow") == "Sink" and #f.casts == 1)
	f.stop()
end)

test("focused text and key release never trigger abilities", function()
	local f = fixture(); f.mouse = Vector2.new(500, 336); f.focused = {}
	assert(f.press("CastArrow") == "Pass" and f.press("TeleportArrow") == "Pass")
	f.focused = nil
	assert(f.press("CastArrow", "End") == "Pass" and f.press("TeleportArrow", "End") == "Pass")
	assert(#f.casts == 0 and f.teleports == 0)
	f.stop()
end)

test("E invokes teleport once and cleanup removes both input bindings", function()
	local f = fixture()
	assert(f.actions.CastArrow.key == "MouseButton1" and f.actions.TeleportArrow.key == "E")
	assert(f.press("TeleportArrow") == "Sink" and f.teleports == 1)
	f.stop()
	assert(#f.unbound == 2 and f.actions.CastArrow == nil and f.actions.TeleportArrow == nil)
	assert(f.press("CastArrow") == "Pass" and f.press("TeleportArrow") == "Pass")
	assert(#f.casts == 0 and f.teleports == 1)
end)
test("warrior input does not consume magic controls", function()
 local f = fixture(); f.classId = "warrior"
 assert(f.press("CastArrow") == "Pass" and f.press("TeleportArrow") == "Pass")
 assert(#f.casts == 0 and f.teleports == 0 and #f.rays == 0)
 f.stop()
end)
print(string.format("%d ArrowInput interaction tests passed", total))
