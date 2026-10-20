--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector2, Vector3 = roblox.Vector2, roblox.Vector3
local source = fs.readFile("src/client/input/HandsInput.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function model(trainingTarget)
	local value = {}
	function value:GetAttribute(name) return name == "TrainingTarget" and trainingTarget end
	function value:FindFirstChildOfClass(class) return if class == "Humanoid" and trainingTarget then {} else nil end
	return value
end
local function partOf(owner)
	local value = {}
	function value:IsDescendantOf(ancestor) return ancestor == owner end
	function value:FindFirstAncestorOfClass(class) return if class == "Model" then owner else nil end
	return value
end
local function fixture()
	local f = { mouse = Vector2.new(500, 336), focused = nil, casts = {}, invalid = 0, actions = {}, rays = {}, unbound = {}, blockers = {}, queries = 0 }
	f.hit = { Position = Vector3.new(20, 2, -30), Normal = Vector3.new(0, 1, 0), Instance = partOf(model(false)) }
	local root = {}; function root:IsA(class) return class == "BasePart" end
	local character = {}; function character:FindFirstChild() return root end
	local gui = {}
	function gui:GetGuiObjectsAtPosition(x, y)
		if x >= 40 and x <= 220 and y >= 160 and y <= 190 then
			return { { IsA = function(_, class) return class == "GuiButton" end } }
		end
		return {}
	end
	local player = { Character = character }
	f.foreignCharacter = model(false)
	local players = {}; function players:GetPlayers() return { player, { Character = f.foreignCharacter } } end
	function player:FindFirstChildOfClass() return gui end
	local camera = {}
	function camera:ViewportPointToRay(x, y)
		table.insert(f.rays, Vector2.new(x, y))
		return { Origin = Vector3.new(0, 6, 10), Direction = Vector3.new(0, -0.1, -1).Unit }
	end
	local world = { CurrentCamera = camera }
	function world:Raycast(_, direction, params)
		f.queries += 1
		assert(math.abs(direction.Magnitude - 500) < 0.001 and params.FilterDescendantsInstances[1] == character)
		assert(params.FilterType == "Exclude" and params.IgnoreWater)
		for _, blocker in f.blockers do
			local excluded = false
			for _, ignored in params.FilterDescendantsInstances do
				if blocker.Instance:IsDescendantOf(ignored) then excluded = true end
			end
			if not excluded then return blocker end
		end
		return f.hit
	end
	local actions = {}
	function actions:BindAction(name, callback, touch, key) assert(not touch); f.actions[name] = { callback = callback, key = key } end
	function actions:UnbindAction(name) f.actions[name] = nil; table.insert(f.unbound, name) end
	local input = {}
	function input:GetFocusedTextBox() return f.focused end
	function input:GetMouseLocation() return f.mouse end
	local guiService = {}; function guiService:GetGuiInset() return Vector2.new(0, 36), Vector2.new(0, 0) end
	local services = { ContextActionService = actions, UserInputService = input, GuiService = guiService, Players = players }
	local game = {}; function game:GetService(name) return assert(services[name]) end
	local module = luau.load(source, { environment = { game = game, workspace = world,
		RaycastParams = { new = function() return {} end }, Enum = { UserInputState = { Begin = "Begin" },
			ContextActionResult = { Pass = "Pass", Sink = "Sink" }, RaycastFilterType = { Exclude = "Exclude" }, KeyCode = { Q = "Q" } },
	} })()
	f.stop = module.bind(player, function(position) table.insert(f.casts, position) end, function() f.invalid += 1 end)
	function f.press(state)
		local action = f.actions.CastHands
		return if action then action.callback("CastHands", state or "Begin") else "Pass"
	end
	return f
end

test("Q sends the exact ground position and camera keeps raw screen coordinates", function()
	local f = fixture()
	assert(f.actions.CastHands.key == "Q" and f.press() == "Sink")
	assert(#f.casts == 1 and f.casts[1] == Vector3.new(20, 2, -30))
	assert(f.rays[1] == Vector2.new(500, 336) and f.invalid == 0)
	f.stop()
end)
test("Q over a real GUI rectangle accounts for inset and does not cast", function()
	local f = fixture(); f.mouse = Vector2.new(100, 216)
	assert(f.press() == "Pass" and #f.casts == 0 and #f.rays == 0 and f.invalid == 0)
	f.stop()
end)
test("typing and key release pass without a cast or invalid-target feedback", function()
	local f = fixture(); f.focused = {}
	assert(f.press() == "Pass"); f.focused = nil
	assert(f.press("End") == "Pass" and #f.casts == 0 and f.invalid == 0)
	f.stop()
end)
test("sky and wall cannot become ground targets and provide feedback", function()
	local f = fixture(); f.hit = nil
	assert(f.press() == "Sink" and f.invalid == 1 and #f.casts == 0)
	f.hit = { Position = Vector3.new(20, 2, -30), Normal = Vector3.new(1, 0, 0), Instance = partOf(model(false)) }
	assert(f.press() == "Sink" and f.invalid == 2 and #f.casts == 0)
	f.stop()
end)
test("aiming through an opponent selects the ground instead of its sloped leg", function()
	local f = fixture()
	f.blockers = { { Position = Vector3.new(18, 3, -28), Normal = Vector3.new(0, 0.428, 0.9), Instance = partOf(f.foreignCharacter) } }
	assert(f.press() == "Sink" and #f.casts == 1 and f.invalid == 0)
	assert(f.casts[1] == f.hit.Position and f.queries == 1, "Opponent prevented selection of the ground behind it")
	f.stop()
end)
test("training target is ignored with one extra ray while physical cover remains solid", function()
	local f = fixture()
	f.blockers = { { Position = Vector3.new(18, 3, -28), Normal = Vector3.new(1, 0, 0), Instance = partOf(model(true)) } }
	assert(f.press() == "Sink" and #f.casts == 1 and f.casts[1] == f.hit.Position and f.queries == 2)
	f.stop()
	local covered = fixture()
	covered.blockers = {
		{ Position = Vector3.new(18, 3, -28), Normal = Vector3.new(1, 0, 0), Instance = partOf(model(true)) },
		{ Position = Vector3.new(19, 3, -29), Normal = Vector3.new(1, 0, 0), Instance = partOf(model(false)) },
	}
	assert(covered.press() == "Sink" and #covered.casts == 0 and covered.invalid == 1 and covered.queries == 2,
		"Ground aim incorrectly passed through physical cover behind the training target")
	covered.stop()
end)
test("cleanup removes only the hands binding", function()
	local f = fixture(); f.actions.CastArrow = { key = "MouseButton1" }
	f.stop()
	assert(#f.unbound == 1 and f.unbound[1] == "CastHands" and f.actions.CastArrow ~= nil)
	assert(f.press() == "Pass" and #f.casts == 0)
end)
print(string.format("%d HandsInput interaction tests passed", total))
