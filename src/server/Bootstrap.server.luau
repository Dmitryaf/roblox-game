--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(script.Parent.config.Warlock)
local HandsConfig = require(script.Parent.config.Hands)
local HandsService = require(script.Parent.application.combat.HandsService)
local WarlockCombat = require(script.Parent.application.combat.WarlockCombat)
local HandsGateway = require(script.Parent.adapters.networking.HandsGateway)
local ClassService = require(script.Parent.application.lobby.ClassService)
local ClassCombat = require(script.Parent.application.combat.ClassCombat)
local ClassGateway = require(script.Parent.adapters.networking.ClassGateway)
local MeleeGateway = require(script.Parent.adapters.networking.MeleeGateway)
local MeleeService = require(script.Parent.application.combat.MeleeService)
local SwordWorld = require(script.Parent.adapters.world.SwordWorld)
local WarriorConfig = require(script.Parent.config.Warrior)
local HeavyConfig = require(script.Parent.config.Heavy)
local HeavyStrikeService = require(script.Parent.application.combat.HeavyStrikeService)
local DashConfig = require(script.Parent.config.Dash)
local DashService = require(script.Parent.application.combat.DashService)
local DashGateway = require(script.Parent.adapters.networking.DashGateway)
local MatchConfig = require(script.Parent.config.Match)
local Arena = require(script.Parent.adapters.world.MatchArena)
local World = require(script.Parent.adapters.world.MatchWorld)
local ArrowService = require(script.Parent.application.combat.ArrowService)
local MatchService = require(script.Parent.application.match.MatchService)
local MatchCombat = require(script.Parent.application.combat.MatchCombat)
local ArrowGateway = require(script.Parent.adapters.networking.ArrowGateway)
local MatchGateway = require(script.Parent.adapters.networking.MatchGateway)
local Runtime = require(script.Parent.adapters.runtime.MatchRuntime)
local Fixture = require(script.Parent.adapters.runtime.StudioMatchFixture)
local ArrowInterceptService = require(script.Parent.application.combat.ArrowInterceptService)
local LivingMagic = require(script.Parent.config.LivingMagic)
local CoverService = require(script.Parent.application.combat.CoverService)
local CoverWorld = require(script.Parent.adapters.world.CoverWorld)
local CoverConfig = require(script.Parent.config.LivingCover)

assert(RunService:IsStudio(), "This prototype is Studio-only until release approval.")
Players.CharacterAutoLoads = false
Players.RespawnTime = Config.respawn
local arena = Arena.create()
local experiment = game:GetService("ServerStorage"):GetAttribute("LivingMagicExperiment") == true
ReplicatedStorage:SetAttribute("LivingMagicExperiment", experiment)
ReplicatedStorage:SetAttribute("MatchEnabled", true)
local function remote(name: string): RemoteEvent
    local event = Instance.new("RemoteEvent")
    event.Name, event.Parent = name, ReplicatedStorage
    return event
end
local arrowRemote, matchRemote, handsRemote = remote("ArrowRemote"), remote("MatchRemote"), remote("HandsRemote")
local classRemote, meleeRemote = remote("ClassRemote"), remote("MeleeRemote")
local dashRemote, heavyRemote = remote("DashRemote"), remote("HeavyRemote")
local now = function() return workspace:GetServerTimeNow() end
local matches: any
local world = World.new(arena, function(owner) return matches.context(owner) end,
    function(owner) return matches.canAct(owner) end)
local combat: any
local runtime: any
local classes = ClassService.new({
    life = function(owner) return combat.snapshot(owner).life end, alive = world.alive,
    locked = function(owner)
        local state = matches.snapshot(owner, now())
        return state.mode ~= "training" or state.ready or state.frozen
    end,
    changed = function(owner) runtime.reset(owner, nil, false) end,
})
local function reaction(target: Humanoid): any
    local model = target.Parent
    return if model and model:IsA("Model") then { targetModel = model, targetLife = model:GetAttribute("CombatLife") or 0 } else nil
end
local melee: any
local sword = SwordWorld.new(world)
local coverWorld = if experiment then CoverWorld.new(world, arena.folder, CoverConfig) else nil
local cover = if coverWorld then CoverService.new({
    alive = world.alive, choose = coverWorld.choose, position = coverWorld.position,
    clearForRaise = coverWorld.clearForRaise, show = coverWorld.show, remove = coverWorld.remove,
    reset = coverWorld.reset, targetSlot = coverWorld.targetSlot, strikeTargets = coverWorld.strikeTargets,
    emit = function(event) handsRemote:FireAllClients(event) end,
}, CoverConfig) else nil
local intercept = if experiment then ArrowInterceptService.new({
    swings = function() return if melee then melee.snapshot(0).active else {} end,
    alive = world.alive, origin = world.origin, visible = sword.visible,
    allowed = function(caster: number, defender: number): boolean
        local source, target = matches.context(caster), matches.context(defender)
        return source.mode == "match" and target.mode == "match" and source.matchId == target.matchId
            and source.team ~= target.team and matches.canAct(caster) and matches.canAct(defender)
            and world.attackReason(defender) == nil
    end,
}, LivingMagic) else nil
local arrow = ArrowService.new({
    origin = world.origin, alive = world.alive, sweep = world.sweep,
    damage = world.damage, landing = world.landing, move = world.move, impact = reaction,
    intercept = intercept,
    coverHit = if cover then cover.hit else nil,
    emit = function(event) arrowRemote:FireAllClients(event) end,
}, Config)
local hands = cover or HandsService.new({ alive = world.alive, placement = world.placement, targets = world.areaTargets,
    damage = world.damage, slow = world.slow, emit = function(event) handsRemote:FireAllClients(event) end }, HandsConfig)
melee = MeleeService.new({ alive = world.alive, origin = world.origin, face = world.face,
    targets = sword.targets, damage = world.damage, impact = sword.impact, reaction = reaction,
    emit = function(event) meleeRemote:FireAllClients(event) end }, WarriorConfig)
local dash = DashService.new({ alive = world.alive, start = world.startDash, stop = world.stopDash,
    emit = function(event) dashRemote:FireAllClients(event) end }, DashConfig)
local heavy = HeavyStrikeService.new({ alive = world.alive, origin = world.origin, face = world.face,
    targets = sword.targets, damage = world.damage, impact = sword.impact, reaction = reaction,
    token = world.slowToken, targetOwner = world.targetOwner,
    slow = function(target, multiplier) world.slow(target, multiplier, "heavy") end,
    onStrike = if cover then function(owner, direction, at) cover.strike(owner, direction, at) end else nil,
    emit = function(event) heavyRemote:FireAllClients(event) end }, HeavyConfig)
combat = ClassCombat.new(WarlockCombat.new(arrow, hands, not experiment), melee, classes.get, dash, heavy)
runtime = Runtime.new(combat, world, arena, now, Config.respawn, classes)
matches = MatchService.new({ reset = runtime.reset, freeze = runtime.freeze }, Fixture.config(MatchConfig))
local guarded = MatchCombat.new(combat, matches, runtime.tick, world.attackReason)
local arrowGateway = ArrowGateway.new(arrowRemote, guarded, now)
local matchGateway = MatchGateway.new(matchRemote, matches, now, runtime.tick, world.alive)
local handsGateway = HandsGateway.new(handsRemote, { cast = guarded.castHands, snapshot = guarded.handsSnapshot }, now)
local classGateway = ClassGateway.new(classRemote, classes, now)
local meleeGateway = MeleeGateway.new(meleeRemote, { cast = guarded.swing, snapshot = guarded.meleeSnapshot }, now)
local dashGateway = DashGateway.new(dashRemote, { cast = guarded.dash, snapshot = guarded.dashSnapshot }, now)
local heavyGateway = MeleeGateway.new(heavyRemote, { cast = guarded.heavyStrike, snapshot = guarded.heavySnapshot }, now)
runtime.start(matches, arrowGateway, matchGateway, handsGateway, classGateway, meleeGateway, dashGateway, heavyGateway)
local stopFixture = Fixture.attach(matches, world, now, combat)
game:BindToClose(function()
    runtime.destroy()
    if coverWorld then coverWorld.destroy() end
    stopFixture()
    arrowRemote:Destroy(); matchRemote:Destroy(); handsRemote:Destroy(); classRemote:Destroy(); meleeRemote:Destroy(); dashRemote:Destroy(); heavyRemote:Destroy(); arena.folder:Destroy()
end)
