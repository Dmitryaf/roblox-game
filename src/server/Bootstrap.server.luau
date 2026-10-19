--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(script.Parent.config.Warlock)
local Arena = require(script.Parent.adapters.world.TestArena)
local World = require(script.Parent.adapters.world.CombatWorld)
local Service = require(script.Parent.application.combat.ArrowService)
local Gateway = require(script.Parent.adapters.networking.ArrowGateway)
local Runtime = require(script.Parent.adapters.runtime.SliceRuntime)

assert(RunService:IsStudio(), "This is a Studio-only combat test, not a public match release.")
Players.RespawnTime = Config.respawn
local arena, spawns = Arena.create()
local remote = Instance.new("RemoteEvent")
remote.Name = "ArrowRemote"
remote.Parent = ReplicatedStorage
local world = World.new(spawns)
local service = Service.new({
	origin = world.origin, alive = world.alive, sweep = world.sweep,
	damage = world.damage, landing = world.landing, move = world.move,
	emit = function(event) remote:FireAllClients(event) end,
}, Config)
local now = function() return workspace:GetServerTimeNow() end
local gateway = Gateway.new(remote, service, now)
local stop = Runtime.start(service, world, gateway, now)
game:BindToClose(function()
	stop()
	remote:Destroy()
	arena:Destroy()
end)
