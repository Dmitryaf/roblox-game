--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hud = require(script.Parent.presentation.ArrowHud)
local Effects = require(script.Parent.presentation.ArrowEffects)
local Input = require(script.Parent.input.ArrowInput)
local Controller = require(script.Parent.controllers.ArrowController)
local MatchHud = require(script.Parent.presentation.MatchHud)
local MatchController = require(script.Parent.controllers.MatchController)
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 15)
assert(remote and remote:IsA("RemoteEvent"), "Combat test server did not start; check Server Output.")
local gui = player:WaitForChild("PlayerGui") :: PlayerGui
local stop = Controller.start(player, remote, Hud.new(gui), Effects.new(), Input.bind)
local stopMatch: (() -> ())? = nil
local matchRemote = ReplicatedStorage:WaitForChild("MatchRemote", 5)
if matchRemote and matchRemote:IsA("RemoteEvent") then
	stopMatch = MatchController.start(player, matchRemote, MatchHud.new(gui))
end
script.Destroying:Connect(function()
	stop()
	if stopMatch then stopMatch() end
end)
