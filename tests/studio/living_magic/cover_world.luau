--!strict
-- Called by the experiment's server fixture; no independent runner or player inputs.
local ServerScriptService = game:GetService("ServerScriptService")
local CoverWorld = require(ServerScriptService.Game.adapters.world.CoverWorld)
local CoverService = require(ServerScriptService.Game.application.combat.CoverService)
local Config = require(ServerScriptService.Game.config.LivingCover)
local SwordWorld = require(ServerScriptService.Game.adapters.world.SwordWorld)
local ArrowInterceptService = require(ServerScriptService.Game.application.combat.ArrowInterceptService)
local ArrowInterception = require(ServerScriptService.Game.domain.combat.ArrowInterception)
local Tests = {}
function Tests.run()
    local root = Instance.new("Folder")
    root.Name, root.Parent = "CoverWorldTest", workspace
    local origin = Config.slots[1] + Vector3.new(0, 4, 8)
    local events = {}
    local adapter = CoverWorld.new({ origin = function() return origin end }, root, Config)
    local service = CoverService.new({
        alive = function() return true end, choose = adapter.choose, position = adapter.position,
        clearForRaise = adapter.clearForRaise, show = adapter.show, remove = adapter.remove, reset = adapter.reset,
        targetSlot = adapter.targetSlot, strikeTargets = adapter.strikeTargets,
        emit = function(event) table.insert(events, event) end,
    }, Config)
    local function body(at: Vector3): Model
        local model = Instance.new("Model")
        model.Name, model.Parent = "CoverOccupant", root
        local p = Instance.new("Part")
        p.Name, p.Size, p.Position, p.Anchored = "HumanoidRootPart", Vector3.new(2, 5, 2), at, true
        p.Parent = model
        local human = Instance.new("Humanoid")
        human.RequiresNeck, human.Parent = false, model
        return model
    end
    local function raise(at: number): BasePart
        service.join(-9001, math.floor(at) + 1)
        assert(service.cast(-9001, math.floor(at) + 1, Config.slots[1], at))
        assert(root:FindFirstChild("RaiseWarning", true), "warning must replicate before collision")
        assert(not root:FindFirstChild("RaisedSlab", true), "warning must not be solid")
        service.step(at + Config.windup)
        local core = root:FindFirstChild("RaisedSlab", true)
        assert(core and core:IsA("BasePart") and core.CanCollide and core.CanQuery)
        return core
    end
    local ok, failure = pcall(function()
        -- Validate the real prepared sites against the current arena, not a mocked floor.
        local overlap = OverlapParams.new()
        overlap.FilterDescendantsInstances, overlap.RespectCanCollide = { root }, true
        for _, position in Config.slots do
            local hits = workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, Config.size.Y / 2, 0)),
                Config.size - Vector3.new(0.05, 0.1, 0.05), overlap)
            assert(#hits == 0, "prepared cover site intersects existing solid geometry")
        end
        assert(adapter.choose(-9001, Config.slots[1]) == 1)
        assert(adapter.choose(-9001, Vector3.new(80, 0, 60)) == nil)
        local oldOrigin = origin; origin = Vector3.new(230, 4, 60)
        local slot, reason = adapter.choose(-9001, Config.slots[1])
        assert(slot == nil and reason == "out_of_range"); origin = oldOrigin

        service.join(-9001, 1)
        assert(service.cast(-9001, 1, Config.slots[1], 0))
        local intruder = body(Config.slots[1] + Vector3.new(0, 3, 0))
        assert(not adapter.clearForRaise(1), "character entering warning must block raise")
        service.step(Config.windup)
        assert(root:FindFirstChild("RaisedSlab", true) == nil and events[#events].reason == "occupied")
        intruder:Destroy()
        assert(adapter.clearForRaise(1))

        local core = raise(10)
        local sword = SwordWorld.new({ origin = function() return origin end })
        local intercept = ArrowInterceptService.new({
            swings = function() return { { owner = -9002, life = 1, direction = -Vector3.zAxis, hitAt = 10.5 } } end,
            alive = function() return true end, allowed = function() return true end,
            origin = function() return origin end, visible = sword.visible,
        }, { window = 0.18, range = 7, arcDegrees = 100 })
        local incoming = Config.slots[1] + Vector3.new(0, 4, -12)
        local travel = Vector3.new(0, 0, 11)
        origin = Config.slots[1] + Vector3.new(0, 4, 4)
        assert(ArrowInterception.fraction(incoming, travel, 10.4, 10.6, origin - Vector3.yAxis,
            -Vector3.zAxis, 10.5, 0.18, 7, 100) ~= nil, "regression must reach blade sector in front of slab")
        assert(intercept(-9001, incoming, travel, 10.4, 10.6) == nil,
            "warrior behind slab must not intercept an arrow in front of it through solid cover")
        origin = oldOrigin
        for _, side in { -1, 1 } do
            local from = Config.slots[1] + Vector3.new(0, 4, side * 8)
            local hit = workspace:Raycast(from, Vector3.new(0, 0, -side * 16))
            assert(hit and hit.Instance == core, "raised slab must stop projectiles from both sides")
        end
        assert(#adapter.strikeTargets(-9002, -Vector3.zAxis, Config.strikeRange, Config.strikeArcDegrees) == 1)
        assert(#adapter.strikeTargets(-9002, Vector3.zAxis, Config.strikeRange, Config.strikeArcDegrees) == 0,
            "heavy swing away from slab must miss")
        local wall = Instance.new("Part")
        wall.Size, wall.Position, wall.Anchored = Vector3.new(14, 8, 1), Config.slots[1] + Vector3.new(0, 4, 4), true
        wall.Parent = root
        assert(#adapter.strikeTargets(-9002, -Vector3.zAxis, Config.strikeRange, Config.strikeArcDegrees) == 0,
            "heavy swing must not destroy cover through another wall")
        wall:Destroy()
        service.join(-9002, 1)
        assert(service.strike(-9002, -Vector3.zAxis, 11) == 1)
        assert(core.Parent == nil and not service.hit(core, 11))
        origin = Config.slots[1] + Vector3.new(0, 4, 4)
        assert(intercept(-9001, incoming, travel, 10.4, 10.6) ~= nil,
            "destroying slab must expose the same blade sector to the incoming arrow")
        origin = oldOrigin
        local fragment = root:FindFirstChild("HarmlessFragment", true)
        assert(fragment and fragment:IsA("BasePart") and not fragment.CanCollide and not fragment.CanQuery and not fragment.CanTouch)
        service.join(-9001, 2)
        assert(root:FindFirstChild("CoverFragments", true) == nil, "life reset must clear cosmetic debris")

        local second = raise(20)
        assert(not service.hit(core, 21) and second.Parent ~= nil, "stale hit must preserve replacement")
        assert(service.hit(second, 21) and not second:IsDescendantOf(root))
        service.destroy(); adapter.destroy()
        assert(#root:GetChildren() == 0, "teardown must release all cover instances")
    end)
    service.destroy(); adapter.destroy(); root:Destroy()
    assert(ok, tostring(failure))
    print("LIVING_COVER_WORLD_PASS: sites, warning occupancy, bilateral collision, heavy and intercept LOS, stale hits, cleanup")
end
return Tests
