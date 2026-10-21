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
local CoverEffects = require(script.Parent.presentation.CoverEffects)
local HandsInput = require(script.Parent.input.HandsInput)
local HandsController = require(script.Parent.controllers.HandsController)
local RunService = game:GetService("RunService")
local ClassController = require(script.Parent.controllers.ClassController)
local ClassHud = require(script.Parent.presentation.ClassHud)
local MeleeController = require(script.Parent.controllers.MeleeController)
local MeleeHud = require(script.Parent.presentation.MeleeHud)
local MeleeEffects = require(script.Parent.presentation.MeleeEffects)
local MeleeInput = require(script.Parent.input.MeleeInput)
local HeavyHud = require(script.Parent.presentation.HeavyHud)
local DashController = require(script.Parent.controllers.DashController)
local DashHud = require(script.Parent.presentation.DashHud)
local DashEffects = require(script.Parent.presentation.DashEffects)
local DashInput = require(script.Parent.input.DashInput)
local DashMotion = require(script.Parent.presentation.DashMotion)
local WarriorPose = require(script.Parent.presentation.MeleePose)
local WarriorAppearance = require(script.Parent.presentation.WarriorAppearance)
local CastPose = require(script.Parent.presentation.CastPose)
local PoseLayers = require(script.Parent.presentation.PoseLayers)
local ClassLocomotion = require(script.Parent.presentation.ClassLocomotion)
local HitReaction = require(script.Parent.presentation.HitReaction)
local player = Players.LocalPlayer
local dashMotion = DashMotion.new(player)
local warriorPose = WarriorPose.new(true)
local castPose = CastPose.new(nil, true)
local hitReaction = HitReaction.new()
local locomotion = ClassLocomotion.new({ isActing = function(character: Model): boolean
    local owner = Players:GetPlayerFromCharacter(character)
    return owner ~= nil and (warriorPose.active(owner.UserId) or castPose.active(owner.UserId))
end })
local layers = PoseLayers.new({locomotion, warriorPose, castPose, hitReaction})
local reactionConnections: { RBXScriptConnection } = {}
local function observeReaction(remoteEvent: RemoteEvent)
    table.insert(reactionConnections, remoteEvent.OnClientEvent:Connect(function(event: any) hitReaction.hit(event) end))
end
local remote = ReplicatedStorage:WaitForChild("ArrowRemote", 15)
assert(remote and remote:IsA("RemoteEvent"), "Combat test server did not start; check Server Output.")
local gui = player:WaitForChild("PlayerGui") :: PlayerGui
observeReaction(remote)
local arrowEffects = Effects.new(castPose)
local experiment = ReplicatedStorage:GetAttribute("LivingMagicExperiment") == true
local stop = Controller.start(player, remote, Hud.new(gui), arrowEffects, Input.bind, experiment)
local stopClass: (() -> ())? = nil
local stopMelee: (() -> ())? = nil
local stopDash: (() -> ())? = nil
local stopHeavy: (() -> ())? = nil
local warrior = WarriorAppearance.new()
local appearanceStep = RunService.RenderStepped:Connect(function() warrior.step(workspace:GetServerTimeNow()) end)
local stopHands: (() -> ())? = nil
if ReplicatedStorage:GetAttribute("MatchEnabled") == true then
    local classRemote = ReplicatedStorage:WaitForChild("ClassRemote", 15)
    local meleeRemote = ReplicatedStorage:WaitForChild("MeleeRemote", 15)
    assert(classRemote and classRemote:IsA("RemoteEvent"), "Class server did not initialize")
    assert(meleeRemote and meleeRemote:IsA("RemoteEvent"), "Melee server did not initialize")
    stopClass = ClassController.start(player, classRemote, ClassHud.new(gui))
    observeReaction(meleeRemote)
    stopMelee = MeleeController.start(player, meleeRemote, MeleeHud.new(gui), MeleeEffects.new(warriorPose), MeleeInput.bind, nil, experiment)
    local heavyRemote = ReplicatedStorage:WaitForChild("HeavyRemote", 15)
    assert(heavyRemote and heavyRemote:IsA("RemoteEvent"), "Heavy strike server did not initialize")
    observeReaction(heavyRemote)
    stopHeavy = MeleeController.start(player, heavyRemote, HeavyHud.new(gui),
        MeleeEffects.new(warriorPose, "heavy"), MeleeInput.bindHeavy, "heavy", experiment)
    local dashRemote = ReplicatedStorage:WaitForChild("DashRemote", 15)
    assert(dashRemote and dashRemote:IsA("RemoteEvent"), "Dash server did not initialize")
    stopDash = DashController.start(player, dashRemote, DashHud.new(gui), DashEffects.new(warriorPose), DashInput.bind)
    local handsRemote = ReplicatedStorage:WaitForChild("HandsRemote", 15)
    assert(handsRemote and handsRemote:IsA("RemoteEvent"), "Hands server did not initialize")
    local handsPose = { begin = arrowEffects.prepare, stop = arrowEffects.stopCast }
    stopHands = HandsController.start(player, handsRemote, HandsHud.new(gui, experiment),
        if experiment then CoverEffects.new(handsPose) else HandsEffects.new(handsPose), HandsInput.bind, experiment)
end
local stopMatch: (() -> ())? = nil
local matchRemote = ReplicatedStorage:WaitForChild("MatchRemote", 5)
if matchRemote and matchRemote:IsA("RemoteEvent") then
	stopMatch = MatchController.start(player, matchRemote, MatchHud.new(gui))
end
script.Destroying:Connect(function()
    layers.destroy()
    for _, connection in reactionConnections do connection:Disconnect() end
    hitReaction.destroy(); castPose.destroy(); locomotion.destroy()
	dashMotion.destroy()
	appearanceStep:Disconnect(); warrior.destroy()
	if stopClass then stopClass() end
	if stopMelee then stopMelee() end
	if stopDash then stopDash() end
	if stopHeavy then stopHeavy() end
	if stopHands then stopHands() end
	stop()
	if stopMatch then stopMatch() end
	warriorPose.destroy()
end)
