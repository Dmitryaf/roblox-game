--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = rb.Vector3, rb.CFrame
local source = fs.readFile("src/client/input/DashInput.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture()
	local f = { classId = "warrior", actions = {}, directions = {}, focused = nil, unbound = {} }
	f.humanoid = { MoveDirection = Vector3.new(2, 0, -1).Unit, Health = 100 }
	f.root = { CFrame = CFrame.identity }; function f.root:IsA(class) return class == "BasePart" end
	local character = {}
	function character:GetAttribute() return f.classId end
	function character:FindFirstChild() return f.root end
	function character:FindFirstChildOfClass() return f.humanoid end
	local actions = {}
	function actions:BindAction(name, callback, touch, key)
		assert(not touch); f.actions[name] = { callback = callback, key = key }
	end
	function actions:UnbindAction(name) f.actions[name] = nil; table.insert(f.unbound, name) end
	local input = {}; function input:GetFocusedTextBox() return f.focused end
	local game = {}; function game:GetService(name) return if name == "ContextActionService" then actions else input end
	local module = luau.load(source, { environment = { game = game, Vector3 = Vector3,
		Enum = { ContextActionResult = { Pass = "Pass", Sink = "Sink" }, UserInputState = { Begin = "Begin" }, KeyCode = { E = "E" } },
	} })()
	f.stop = module.bind({ Character = character }, function(direction) table.insert(f.directions, direction) end)
	function f.press(state)
		local action = f.actions.WarriorDash
		return if action then action.callback("WarriorDash", state or "Begin") else "Pass"
	end
	return f
end
test("warrior E uses the horizontal movement direction and standing falls back to facing", function()
	local f = fixture()
	assert(f.actions.WarriorDash.key == "E" and f.press() == "Sink")
	assert((f.directions[1] - Vector3.new(2, 0, -1).Unit).Magnitude < 0.0001)
	f.humanoid.MoveDirection = Vector3.zero; assert(f.press() == "Sink")
	assert(f.directions[2] == Vector3.new(0, 0, -1)); f.stop()
end)
test("warlock and unknown classes pass E to the teleport binding", function()
	local f = fixture(); f.classId = "warlock"; assert(f.press() == "Pass")
	f.classId = nil; assert(f.press() == "Pass" and #f.directions == 0); f.stop()
end)
test("text focus, key release, death and an absent root never send a dash", function()
	local f = fixture(); f.focused = {}; assert(f.press() == "Pass")
	f.focused = nil; assert(f.press("End") == "Pass")
	f.humanoid.Health = 0; assert(f.press() == "Pass")
	f.humanoid.Health = 100; f.root = nil; assert(f.press() == "Pass" and #f.directions == 0); f.stop()
end)
test("the horizontal fallback cannot create a non-finite direction and cleanup preserves teleport", function()
	local f = fixture(); f.humanoid.MoveDirection = Vector3.new(0, 1, 0)
	f.root.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
	assert(f.press() == "Pass" and #f.directions == 0)
	f.actions.TeleportArrow = {}; f.stop()
	assert(#f.unbound == 1 and f.unbound[1] == "WarriorDash" and f.actions.TeleportArrow)
end)
print(string.format("%d DashInput interaction tests passed", total))
