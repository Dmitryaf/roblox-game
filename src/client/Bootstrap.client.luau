--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hud = require(script.Parent.presentation.ArrowHud)
local Effects = require(script.Parent.presentation.ArrowEffects)
local Input = require(script.Parent.input.ArrowInput)
local Controller = require(script.Parent.controllers.ArrowController)
local MatchHud = require(script.Parent.presentation.MatchHud)
local MatchController = require(script.Parent.controllers.MatchController)
local HandsHud = require(script.Parent.presentation.HandsHud)
local HandsEffects = require(script.Parent.presentation.HandsEffects)
local HandsInput = require(script.Parent.input.HandsInput)
local HandsController = require(script.Parent.controllers.HandsController)
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 15)
assert(remote and remote:IsA("RemoteEvent"), "Combat test server did not start; check Server Output.")
local gui = player:WaitForChild("PlayerGui") :: PlayerGui
local arrowEffects = Effects.new()
local stop = Controller.start(player, remote, Hud.new(gui), arrowEffects, Input.bind)
local stopHands: (() -> ())? = nil
if ReplicatedStorage:GetAttribute("MatchEnabled") == true then
    local handsRemote = ReplicatedStorage:WaitForChild("HandsRemote", 15)
    assert(handsRemote and handsRemote:IsA("RemoteEvent"), "Hands server did not initialize")
    stopHands = HandsController.start(player, handsRemote, HandsHud.new(gui),
        HandsEffects.new({ begin = arrowEffects.prepare, stop = arrowEffects.stopCast }), HandsInput.bind)
end
local stopMatch: (() -> ())? = nil
local matchRemote = ReplicatedStorage:WaitForChild("MatchRemote", 5)
if matchRemote and matchRemote:IsA("RemoteEvent") then
	stopMatch = MatchController.start(player, matchRemote, MatchHud.new(gui))
end
script.Destroying:Connect(function()
	if stopHands then stopHands() end
	stop()
	if stopMatch then stopMatch() end
end)
