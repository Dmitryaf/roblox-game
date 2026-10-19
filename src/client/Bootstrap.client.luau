--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hud = require(script.Parent.presentation.ArrowHud)
local Effects = require(script.Parent.presentation.ArrowEffects)
local Input = require(script.Parent.input.ArrowInput)
local Controller = require(script.Parent.controllers.ArrowController)
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 15)
assert(remote and remote:IsA("RemoteEvent"), "Combat test server did not start; check Server Output.")
local gui = player:WaitForChild("PlayerGui") :: PlayerGui
local stop = Controller.start(player, remote, Hud.new(gui), Effects.new(), Input.bind)
script.Destroying:Connect(stop)
