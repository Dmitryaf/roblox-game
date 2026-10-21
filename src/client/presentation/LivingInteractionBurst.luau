--!strict
-- Short directional accents leave the slab silhouette and outgoing projectile visible.
local Matter = require(script.Parent.ChaosMatter)
local Burst = {}
local green, gold, stone = Color3.fromRGB(103, 219, 118), Color3.fromRGB(255, 207, 119), Color3.fromRGB(63, 73, 63)
type Chip = { part: Part, origin: Vector3, velocity: Vector3, spin: CFrame }
function Burst.new(folder: Folder, kind: string, event: any, expires: number)
    local started = workspace:GetServerTimeNow()
    local duration = math.max(0.01, expires - started)
    local position: Vector3 = event.position
    local redirect = kind == "redirect"
    local color = if redirect then gold else green
    local root = Instance.new("Folder")
    root.Name, root.Parent = "Living" .. kind, folder
    root:SetAttribute("InteractionKind", kind)
    root:SetAttribute("ActionId", event.castId or event.areaId)
    game:GetService("Debris"):AddItem(root, duration + 0.1)
    local anchor = Matter.part(root, "CueAnchor", Vector3.one * 0.1, color)
    anchor.Transparency, anchor.Position = 1, position
    local light = Matter.light(anchor, color, if redirect then 3.4 else 2, if redirect then 8 else 12)
    local sound = Instance.new("Sound")
    sound.Name, sound.SoundId = "InteractionCue", "rbxasset://sounds/living-magic-v1/" .. kind .. ".wav"
    sound.Volume = if kind == "gather" then 0.28 elseif redirect then 0.75 else 0.65
    sound.RollOffMinDistance, sound.RollOffMaxDistance = 8, 95
    sound.Parent = anchor
    sound:Play()
    local arcs: { Part } = {}
    local chips: { Chip } = {}
    local outward = if redirect and event.direction then event.direction else Vector3.zAxis
    if outward.Magnitude < 0.1 then outward = Vector3.zAxis end
    local basis = CFrame.lookAt(position, position + outward)
    local count = if redirect then 8 elseif kind == "gather" then 12 else 10
    for index = 1, count do
        local p = Matter.part(root, if redirect then "BladeSpark" else "StoneEmber", Vector3.new(0.09, 0.09, 0.6), color)
        p.Transparency = 0.2
        table.insert(arcs, p)
    end
    if kind == "raise" or kind == "shatter" then
        for index = 1, 10 do
            local side = if index % 2 == 0 then 1 else -1
            local origin = position + Vector3.new((index % 5 - 2) * 1.8, if kind == "raise" then 0.1 else 1 + index % 4, side * 1.6)
            local p = Matter.part(root, "LocalHarmlessChip", Vector3.new(0.22 + index % 3 * 0.12, 0.24, 0.4), stone)
            p.Material = Enum.Material.Slate
            table.insert(chips, { part = p, origin = origin,
                velocity = Vector3.new((index % 5 - 2) * 2, if kind == "raise" then 4 else 6, side * (5 + index % 3)),
                spin = CFrame.Angles(index * 0.67, index * 0.4, index * 0.91) })
        end
    end
    local alive = true
    local handle = {}
    function handle.step(now: number)
        if not alive then return end
        local age = math.clamp(now - started, 0, duration)
        local alpha = age / duration
        light.Brightness = (if redirect then 3.4 else 2) * (1 - alpha) ^ 2
        for index, p in arcs do
            local angle = index / count * math.pi * 2
            if redirect then
                -- Fan around the blade contact, then pull the eye toward the new trajectory.
                local radius = 0.25 + age * (4 + index % 3)
                p.CFrame = basis * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, -age * 5)
                    * CFrame.Angles(math.cos(angle) * 0.6, math.sin(angle) * 0.6, angle)
                p.Size = Vector3.new(0.07, 0.07, math.max(0.1, 1.3 * (1 - alpha)))
            elseif kind == "gather" then
                local radius = 1.4 + (1 - alpha) * 3
                p.CFrame = CFrame.new(position + Vector3.new(math.cos(angle + age * 2) * radius, 0.15 + alpha * 0.6,
                    math.sin(angle + age * 2) * radius * 0.6)) * CFrame.Angles(0, -angle - age * 2, 0)
                p.Size = Vector3.new(0.08, 0.12 + alpha * 0.25, 0.4)
            else
                local radius = 0.8 + age * (if kind == "shatter" then 9 else 5)
                p.CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * radius, 0.2 + math.sin(alpha * math.pi) * 0.6,
                    math.sin(angle) * radius * 0.55)) * CFrame.Angles(0, -angle, 0)
                p.Size = Vector3.new(0.1, 0.12, 0.9 * (1 - alpha) + 0.1)
            end
            p.Transparency = 0.15 + alpha * 0.85
        end
        for _, chip in chips do
            chip.part.CFrame = CFrame.new(chip.origin + chip.velocity * age - Vector3.yAxis * (age * age * 14))
                * chip.spin:Lerp(CFrame.identity, alpha) * CFrame.Angles(age * 5, 0, age * 3)
            chip.part.Transparency = math.clamp((alpha - 0.35) / 0.65, 0, 1)
        end
    end
    function handle.destroy()
        if not alive then return end
        alive = false; root:Destroy()
    end
    handle.step(started)
    return handle
end
return Burst
