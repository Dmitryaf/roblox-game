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
local RunService = game:GetService("RunService")
local ClassController = require(script.Parent.controllers.ClassController)
local ClassHud = require(script.Parent.presentation.ClassHud)
local MeleeController = require(script.Parent.controllers.MeleeController)
local MeleeHud = require(script.Parent.presentation.MeleeHud)
local MeleeEffects = require(script.Parent.presentation.MeleeEffects)
local MeleeInput = require(script.Parent.input.MeleeInput)
local DashController = require(script.Parent.controllers.DashController)
local DashHud = require(script.Parent.presentation.DashHud)
local DashEffects = require(script.Parent.presentation.DashEffects)
local DashInput = require(script.Parent.input.DashInput)
local DashMotion = require(script.Parent.presentation.DashMotion)
local WarriorAppearance = require(script.Parent.presentation.WarriorAppearance)
local player = Players.LocalPlayer
local dashMotion = DashMotion.new(player)
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 15)
assert(remote and remote:IsA("RemoteEvent"), "Combat test server did not start; check Server Output.")
local gui = player:WaitForChild("PlayerGui") :: PlayerGui
local arrowEffects = Effects.new()
local stop = Controller.start(player, remote, Hud.new(gui), arrowEffects, Input.bind)
local stopClass: (() -> ())? = nil
local stopMelee: (() -> ())? = nil
local stopDash: (() -> ())? = nil
local warrior = WarriorAppearance.new()
local appearanceStep = RunService.RenderStepped:Connect(function() warrior.step(workspace:GetServerTimeNow()) end)
local stopHands: (() -> ())? = nil
if ReplicatedStorage:GetAttribute("MatchEnabled") == true then
    local classRemote = ReplicatedStorage:WaitForChild("ClassRemote", 15)
    local meleeRemote = ReplicatedStorage:WaitForChild("MeleeRemote", 15)
    assert(classRemote and classRemote:IsA("RemoteEvent"), "Class server did not initialize")
    assert(meleeRemote and meleeRemote:IsA("RemoteEvent"), "Melee server did not initialize")
    stopClass = ClassController.start(player, classRemote, ClassHud.new(gui))
    stopMelee = MeleeController.start(player, meleeRemote, MeleeHud.new(gui), MeleeEffects.new(), MeleeInput.bind)
    local dashRemote = ReplicatedStorage:WaitForChild("DashRemote", 15)
    assert(dashRemote and dashRemote:IsA("RemoteEvent"), "Dash server did not initialize")
    stopDash = DashController.start(player, dashRemote, DashHud.new(gui), DashEffects.new(), DashInput.bind)
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
	dashMotion.destroy()
	appearanceStep:Disconnect(); warrior.destroy()
	if stopClass then stopClass() end
	if stopMelee then stopMelee() end
	if stopDash then stopDash() end
	if stopHands then stopHands() end
	stop()
	if stopMatch then stopMatch() end
end)
