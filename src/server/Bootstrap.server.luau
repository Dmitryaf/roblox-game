--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(script.Parent.config.Warlock)
local HandsConfig = require(script.Parent.config.Hands)
local HandsService = require(script.Parent.application.combat.HandsService)
local WarlockCombat = require(script.Parent.application.combat.WarlockCombat)
local HandsGateway = require(script.Parent.adapters.networking.HandsGateway)
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

assert(RunService:IsStudio(), "This prototype is Studio-only until release approval.")
Players.CharacterAutoLoads = false
Players.RespawnTime = Config.respawn
local arena = Arena.create()
ReplicatedStorage:SetAttribute("MatchEnabled", true)
local function remote(name: string): RemoteEvent
    local event = Instance.new("RemoteEvent")
    event.Name, event.Parent = name, ReplicatedStorage
    return event
end
local arrowRemote, matchRemote, handsRemote = remote("ArrowRemote"), remote("MatchRemote"), remote("HandsRemote")
local now = function() return workspace:GetServerTimeNow() end
local matches: any
local world = World.new(arena, function(owner) return matches.context(owner) end,
    function(owner) return matches.canAct(owner) end)
local arrow = ArrowService.new({
    origin = world.origin, alive = world.alive, sweep = world.sweep,
    damage = world.damage, landing = world.landing, move = world.move,
    emit = function(event) arrowRemote:FireAllClients(event) end,
}, Config)
local hands = HandsService.new({ alive = world.alive, placement = world.placement, targets = world.areaTargets,
    damage = world.damage, slow = world.slow, emit = function(event) handsRemote:FireAllClients(event) end }, HandsConfig)
local combat = WarlockCombat.new(arrow, hands)
local runtime = Runtime.new(combat, world, arena, now, Config.respawn)
matches = MatchService.new({ reset = runtime.reset, freeze = runtime.freeze }, Fixture.config(MatchConfig))
local guarded = MatchCombat.new(combat, matches, runtime.tick, world.attackReason)
local arrowGateway = ArrowGateway.new(arrowRemote, guarded, now)
local matchGateway = MatchGateway.new(matchRemote, matches, now, runtime.tick, world.alive)
local handsGateway = HandsGateway.new(handsRemote, { cast = guarded.castHands, snapshot = guarded.handsSnapshot }, now)
runtime.start(matches, arrowGateway, matchGateway, handsGateway)
local stopFixture = Fixture.attach(matches, world, now)
game:BindToClose(function()
    runtime.destroy()
    stopFixture()
    arrowRemote:Destroy(); matchRemote:Destroy(); handsRemote:Destroy(); arena.folder:Destroy()
end)
