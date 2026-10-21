--!strict
-- The server owns solid geometry. Warning marks, hands and fragments have no hitboxes.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CoverWorld = {}
function CoverWorld.new(world: any, parent: Instance, config: any)
    local folder = Instance.new("Folder")
    folder.Name, folder.Parent = "LivingCovers", parent
    local entries: { [number]: { id: number, owner: number, model: Model, core: Part? } } = {}
    local fragments: { [number]: { Folder } } = {}
    local adapter = {}
    local function part(parentInstance: Instance, name: string, size: Vector3, frame: CFrame, solid: boolean): Part
        local p = Instance.new("Part")
        p.Name, p.Size, p.CFrame = name, size, frame
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, solid, solid, false
        p.Material, p.Color = Enum.Material.Slate, Color3.fromRGB(49, 60, 52)
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.Parent = parentInstance
        return p
    end
    local function frame(slot: number): CFrame
        return CFrame.new(config.slots[slot] + Vector3.yAxis * (config.size.Y / 2))
    end
    local function label(base: BasePart, text: string)
        local gui = Instance.new("BillboardGui")
        gui.Size, gui.StudsOffset, gui.MaxDistance = UDim2.fromOffset(220, 35), Vector3.new(0, 1.5, 0), 60
        local t = Instance.new("TextLabel")
        t.Size, t.BackgroundTransparency, t.Text = UDim2.fromScale(1, 1), 1, text
        t.Font, t.TextSize, t.TextColor3 = Enum.Font.GothamBold, 15, Color3.fromRGB(168, 245, 173)
        t.Parent, gui.Parent = gui, base
    end
    for slot, position in config.slots do
        local mark = part(folder, "CoverSite" .. tostring(slot), Vector3.new(config.size.X, 0.06, config.size.Z + 1.5),
            CFrame.new(position + Vector3.yAxis * 0.06), false)
        mark.Material, mark.Color, mark.Transparency = Enum.Material.Neon, Color3.fromRGB(69, 154, 89), 0.65
        mark:SetAttribute("CoverSlot", slot)
        label(mark, "Q · ПОДНЯТЬ ПЛИТУ " .. tostring(slot))
    end
    function adapter.position(slot: number): Vector3 return config.slots[slot] end
    function adapter.choose(owner: number, aim: Vector3): (number?, string?)
        if aim.X ~= aim.X or aim.Y ~= aim.Y or aim.Z ~= aim.Z or aim.Magnitude == math.huge then return nil, "invalid_target" end
        local origin = world.origin(owner)
        if not origin then return nil, "invalid_position" end
        local best, distance: number? = nil, nil
        for slot, position in config.slots do
            local delta = (position - aim) * Vector3.new(1, 0, 1)
            if delta.Magnitude <= config.pickRadius and math.abs(aim.Y - position.Y) <= config.size.Y + 2
                and (distance == nil or delta.Magnitude < distance) then best, distance = slot, delta.Magnitude end
        end
        if not best then return nil, "invalid_target" end
        if (config.slots[best] - origin).Magnitude > config.range then return nil, "out_of_range" end
        return best, nil
    end
    function adapter.clearForRaise(slot: number): boolean
        local overlap = OverlapParams.new()
        overlap.FilterType = Enum.RaycastFilterType.Exclude
        overlap.FilterDescendantsInstances = { folder }
        -- The margin includes a character whose root is just outside the future stone.
        for _, p in workspace:GetPartBoundsInBox(frame(slot), config.size + Vector3.new(2, 1, 2), overlap) do
            local model = p:FindFirstAncestorOfClass("Model")
            local human = if model then model:FindFirstChildOfClass("Humanoid") else nil
            if human and human.Health > 0 then return false end
        end
        return true
    end
    function adapter.show(area: any, phase: string)
        local old = entries[area.slotId]
        if old then old.model:Destroy() end
        local model = Instance.new("Model")
        model.Name, model.Parent = "Cover" .. tostring(area.slotId), folder
        model:SetAttribute("CoverId", area.areaId)
        model:SetAttribute("CoverOwner", area.owner)
        local entry = { id = area.areaId, owner = area.owner, model = model, core = nil :: Part? }
        entries[area.slotId] = entry
        if phase == "preparing" then
            local warning = part(model, "RaiseWarning", config.size, frame(area.slotId), false)
            warning.Material, warning.Color, warning.Transparency = Enum.Material.Neon, Color3.fromRGB(92, 241, 119), 0.85
            label(warning, "ПЛИТА ПОДНИМАЕТСЯ")
        else
            local core = part(model, "RaisedSlab", config.size, frame(area.slotId), true)
            core:SetAttribute("LivingCover", true)
            core:SetAttribute("CoverSlot", area.slotId)
            entry.core = core
            local seam = part(model, "DemonicSeam", Vector3.new(0.18, config.size.Y - 1, config.size.Z + 0.03), frame(area.slotId), false)
            seam.Material, seam.Color = Enum.Material.Neon, Color3.fromRGB(91, 189, 116)
            for _, x in { -4, -2, 2, 4 } do
                for _, z in { -1, 1 } do
                    local handFrame = CFrame.new(area.position + Vector3.new(x, 1.2, z * (config.size.Z / 2 + 0.4)))
                    local palm = part(model, "StoneGrip", Vector3.new(0.8, 1.6, 0.55), handFrame, false)
                    palm.Color = Color3.fromRGB(35, 73, 49)
                    for finger = -1, 1 do
                        part(model, "GripFinger", Vector3.new(0.17, 0.7, 0.2), handFrame * CFrame.new(finger * 0.23, 1, -z * 0.12), false)
                    end
                end
            end
        end
    end
    function adapter.remove(area: any, reason: string)
        local entry = entries[area.slotId]
        if not entry or entry.id ~= area.areaId then return end
        entries[area.slotId] = nil
        entry.model:Destroy()
        if reason ~= "shattered" then return end
        local debris = Instance.new("Folder")
        debris.Name, debris.Parent = "CoverFragments", folder
        local owned = fragments[area.owner] or {}
        for i = #owned, 1, -1 do if not owned[i].Parent then table.remove(owned, i) end end
        table.insert(owned, debris); fragments[area.owner] = owned
        for index = 1, 8 do
            local x, side = ((index - 1) % 4 - 1.5) * 2.6, if index <= 4 then -1 else 1
            local origin = CFrame.new(area.position + Vector3.new(x, 2 + index % 3, side))
            local piece = part(debris, "HarmlessFragment", Vector3.new(1.2, 1.6, 0.8), origin, false)
            TweenService:Create(piece, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { CFrame = origin * CFrame.new(x * 0.3, 1, side * 4) * CFrame.Angles(index, 0.3, index * 0.4), Transparency = 1 }):Play()
        end
        Debris:AddItem(debris, 0.55)
    end
    function adapter.reset(owner: number)
        local owned: { Folder } = fragments[owner] or {}
        for _, debris in owned do debris:Destroy() end
        fragments[owner] = nil
    end
    function adapter.targetSlot(target: any): number?
        for slot, entry in entries do if entry.core == target and target ~= nil then return slot end end
        return nil
    end
    function adapter.strikeTargets(owner: number, direction: Vector3, range: number, arcDegrees: number): { number }
        local origin = world.origin(owner)
        if not origin then return {} end
        local flatDirection = direction * Vector3.new(1, 0, 1)
        if flatDirection.Magnitude < 0.1 then return {} end
        local result = {}
        for slot, entry in entries do
            local core = entry.core
            if not core then continue end
            local localPoint = core.CFrame:PointToObjectSpace(origin)
            local half = core.Size / 2
            local nearest = core.CFrame:PointToWorldSpace(Vector3.new(math.clamp(localPoint.X, -half.X, half.X),
                math.clamp(localPoint.Y, -half.Y, half.Y), math.clamp(localPoint.Z, -half.Z, half.Z)))
            local delta = nearest - origin
            local flat = delta * Vector3.new(1, 0, 1)
            if delta.Magnitude > range or (flat.Magnitude > 0.01 and flat.Unit:Dot(flatDirection.Unit) < math.cos(math.rad(arcDegrees / 2))) then continue end
            -- Match sword targeting: a wall/other cover must block the heavy strike.
            local p = RaycastParams.new()
            p.RespectCanCollide = true
            local player = game:GetService("Players"):GetPlayerByUserId(owner)
            p.FilterDescendantsInstances = if player and player.Character then { player.Character } else {}
            if delta.Magnitude < 0.01 then table.insert(result, slot); continue end
            local hit = workspace:Raycast(origin, delta.Unit * (delta.Magnitude + 0.1), p)
            if hit and hit.Instance == core then table.insert(result, slot) end
        end
        return result
    end
    function adapter.destroy()
        table.clear(entries); table.clear(fragments); folder:Destroy()
    end
    return adapter
end
return CoverWorld
