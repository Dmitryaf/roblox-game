--!strict
-- Private local instrumentation. No client command can enable it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local StudioMatchFixture = {}
local function enabled(): boolean
	local token = ReplicatedStorage:FindFirstChild("StudioTestToken")
	return RunService:IsStudio() and token ~= nil and token:IsA("StringValue") and ServerStorage:GetAttribute("MatchTest") == true
end
function StudioMatchFixture.config(default: any): any
    if enabled() and ServerStorage:GetAttribute("ArenaTest") == true then
        return { gathering = 5, countdown = 0.3, pause = 3, duration = 240, target = 150, noExpansionLast = 5 }
    end
    if enabled() and ServerStorage:GetAttribute("OverlapTest") == true then
        return { gathering = 2.5, countdown = 0.3, pause = 3, duration = 180, target = 150, noExpansionLast = 5 }
    end
    if enabled() and (ServerStorage:GetAttribute("HandsTest") == true or ServerStorage:GetAttribute("WarriorTest") == true or ServerStorage:GetAttribute("DashTest") == true or ServerStorage:GetAttribute("ContactTest") == true or ServerStorage:GetAttribute("HeavyTest") == true or ServerStorage:GetAttribute("MixedTest") == true or ServerStorage:GetAttribute("FeedbackTest") == true or ServerStorage:GetAttribute("TransferTest") == true) then
        return { gathering = 0.3, countdown = 0.3, pause = 3, duration = 120, target = 150, noExpansionLast = 5 }
    end
	return if enabled() then { gathering = 2, countdown = 1, pause = 3, duration = 30, target = 3, noExpansionLast = 5 } else default
end
function StudioMatchFixture.attach(matches: any, world: any, now: () -> number, combat: any?): () -> ()
	if not enabled() then return function() end end
	local fixture = Instance.new("BindableFunction")
	fixture.Name = "MatchTestBridge"
	fixture.OnInvoke = function(action: string, owner: number, position: Vector3?)
		if action == "combat" and combat then
            return { arrow = combat.snapshot(owner), hands = combat.handsSnapshot(owner),
                melee = combat.meleeSnapshot(owner), heavy = combat.heavySnapshot(owner), dash = combat.dashSnapshot(owner) }
        end
        if action == "snapshot" then return matches.snapshot(owner, now()) end
		if action == "context" then return matches.context(owner) end
		if action == "position" then return world.position(owner) end
		if action == "place" and position then world.move(owner, position); return true end
		if action == "kill" then
			local player = Players:GetPlayerByUserId(owner)
			local humanoid = if player and player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid then humanoid.Health = 0 end
			return humanoid ~= nil
		end
		error("Unsupported match fixture command")
	end
	fixture.Parent = ServerStorage
	return function() fixture:Destroy() end
end
return StudioMatchFixture
