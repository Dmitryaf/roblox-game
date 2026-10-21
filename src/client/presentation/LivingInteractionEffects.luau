--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Feedback = require(script.Parent.LivingInteractionFeedback)
local Burst = require(script.Parent.LivingInteractionBurst)
local Effects = {}
function Effects.new()
    local folder = Instance.new("Folder")
    folder.Name, folder.Parent = "LocalLivingInteractions", workspace
    local feedback = Feedback.new({
        now = function() return workspace:GetServerTimeNow() end,
        valid = function(owner: number, life: number): boolean
            local player = Players:GetPlayerByUserId(owner)
            local character = if player then player.Character else nil
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
            return character ~= nil and character.Parent ~= nil and character:GetAttribute("CombatLife") == life
                and root ~= nil and root:IsA("BasePart") and not root.Anchored and humanoid ~= nil and humanoid.Health > 0
        end,
        create = function(kind: string, event: any, expires: number) return Burst.new(folder, kind, event, expires) end,
    })
    local stopped, lastStep = false, 0
    local function step()
        local now = workspace:GetServerTimeNow()
        lastStep = now; feedback.step(now)
    end
    local render = RunService.RenderStepped:Connect(step)
    local heartbeat = RunService.Heartbeat:Connect(function()
        if workspace:GetServerTimeNow() - lastStep > 0.1 then step() end
    end)
    local effects = { arrow = feedback.arrow, cover = feedback.cover, syncCover = feedback.syncCover, inspect = feedback.inspect }
    function effects.destroy()
        if stopped then return end
        stopped = true
        render:Disconnect(); heartbeat:Disconnect(); feedback.destroy(); folder:Destroy()
    end
    return effects
end
return Effects
