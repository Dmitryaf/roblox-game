--!strict
-- Static geometry blocks the travelled path. Native physics owns body contacts:
-- asynchronous character snapshots cannot reconstruct an earlier collision.
local MovementSweep = {}
function MovementSweep.blocker(character: Model, root: BasePart, previous: CFrame, delta: Vector3): RaycastResult?
    local size = root.Size * 0.96 -- Keep the guard inside the real body, including its depth.
    local ignored: { Instance } = { character }
    local query = RaycastParams.new()
    query.FilterType, query.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
    for _ = 1, 32 do
        query.FilterDescendantsInstances = ignored
        local hit = workspace:Blockcast(previous, size, delta, query)
        if not hit then return nil end
        local model = hit.Instance:FindFirstAncestorOfClass("Model")
        local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
        if not model or not humanoid then return hit end
        table.insert(ignored, model)
        -- Recast, so ignoring a historical character never hides a wall behind it.
    end
    -- A crowded query never opens a path through unchecked static geometry.
    query.FilterDescendantsInstances = ignored
    return workspace:Blockcast(previous, size, delta, query)
end
return MovementSweep
