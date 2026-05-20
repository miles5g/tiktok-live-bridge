-- ============================================================
-- CameraScript  |  StarterPlayerScripts > LocalScript
-- Portrait-optimized cinematic camera for TikTok 9:16.
-- Row-based visibility: camera locks on row A–D; every row
-- closer to the camera than that row goes 100% transparent.
--   A (0) = back, near backdrop
--   D (3) = front, nearest camera
-- Example: camera on A → hide everyone on B, C, D.
-- ============================================================
-- WHERE TO PUT THIS:
--   Roblox Studio → Explorer → StarterPlayer → StarterPlayerScripts
--   Right-click → Insert Object → LocalScript → paste this in
--
-- ⚠️  This is a LOCALSCRIPT. Do NOT paste into ServerScriptService.
--     SpawnScript.lua goes in ServerScriptService instead.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
-- Show the dance floor immediately — never leave a black screen while waiting for server.
camera.CFrame = CFrame.lookAt(Vector3.new(0, 12, 25), Vector3.new(0, 8, -6))

local CAM_DISTANCE   = 10
local CAM_HEIGHT     = 2
local CAM_SIDE       = 0
local FOCUS_HEIGHT   = 2
local TWEEN_DURATION = 2.2
local FOLLOW_ALPHA   = 0.04
local CYCLE_INTERVAL = 5

local activeParts    = {}
local rootRows       = {}
local cycleIndex     = 1
local currentTarget  = nil
local isTweening     = false
local tweenStartTime = 0
local lastLockTime   = 0
local pendingFocus   = nil
local queueHasItems  = false

local localPlayer = Players.LocalPlayer

local function waitForRemote(name, timeoutSec)
    local deadline = tick() + (timeoutSec or 60)
    while tick() < deadline do
        local ev = ReplicatedStorage:FindFirstChild(name)
        if ev then return ev end
        task.wait(0.25)
    end
    warn("[Camera] RemoteEvent '" .. name .. "' not found. "
        .. "Paste SpawnScript.lua into ServerScriptService (Script), not CameraScript.")
    return nil
end

local cameraReadyEvent = waitForRemote("CameraReady", 60)
local cameraFocusEvent = waitForRemote("CameraFocus", 60)
local despawnEvent     = waitForRemote("DespawnCharacter", 60)
local queueStatusEvent = waitForRemote("QueueStatus", 60)
local focusEvent       = waitForRemote("FocusOnCharacter", 60)

-- ── Row system (must match SpawnScript slot.row) ───────────
-- Index 0–3 maps to letters A–D on the dance floor.

local ROW_LABELS       = { "A", "B", "C", "D" }
local currentCameraRow = nil   -- which row the camera is on; nil while panning

local function rowLabel(row)
    if typeof(row) == "number" and row >= 0 and row < #ROW_LABELS then
        return ROW_LABELS[row + 1]
    end
    return "?"
end

-- Rows with a higher index sit closer to the camera (in front of the focus row).
local function isInFrontOfCameraRow(dancerRow, cameraRow)
    return typeof(dancerRow) == "number" and typeof(cameraRow) == "number"
        and dancerRow > cameraRow
end

local function getModelRow(model)
    if not model then return nil end
    local row = model:GetAttribute("SpawnRow")
    if typeof(row) == "number" then return row end
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and rootRows[root] ~= nil then return rootRows[root] end
    return nil
end

local function setModelFade(model, hide)
    if not model or not model.Parent then return end
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
            desc.LocalTransparencyModifier = hide and 1 or 0
        elseif desc:IsA("Decal") or desc:IsA("Texture") then
            desc.Transparency = hide and 1 or 0
        elseif desc:IsA("SurfaceGui") then
            desc.Enabled = not hide
        end
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            local speed = hide and 0 or 0.75
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(speed)
            end
        end
    end
end

local function getAllDancers()
    local list = {}
    local localChar = localPlayer and localPlayer.Character
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child ~= localChar
            and child:FindFirstChildOfClass("Humanoid")
            and child:FindFirstChild("HumanoidRootPart") then
            table.insert(list, child)
        end
    end
    return list
end

-- Apply visibility for the whole floor based on which row the camera is on.
local function applyRowVisibility(cameraRow)
    if cameraRow == nil then
        for _, model in ipairs(getAllDancers()) do
            setModelFade(model, false)
        end
        return 0, nil
    end

    local hidden = 0
    for _, model in ipairs(getAllDancers()) do
        local dancerRow = getModelRow(model)
        if dancerRow ~= nil and isInFrontOfCameraRow(dancerRow, cameraRow) then
            setModelFade(model, true)
            hidden += 1
        else
            setModelFade(model, false)
        end
    end
    return hidden, cameraRow
end

local function setCameraRow(cameraRow)
    currentCameraRow = cameraRow
    return applyRowVisibility(cameraRow)
end

local function notifyServerFades(focusRoot)
    if not cameraFocusEvent then return end
    if not focusRoot or not focusRoot.Parent then
        pcall(function() cameraFocusEvent:FireServer("", -1) end)
        return
    end
    local row  = getModelRow(focusRoot.Parent)
    local name = focusRoot.Parent.Name
    pcall(function() cameraFocusEvent:FireServer(name, row or -1) end)
end

local function clearAllFades()
    currentCameraRow = nil
    applyRowVisibility(nil)
    notifyServerFades(nil)
end

-- Re-apply every frame so late-loading accessories still fade.
RunService:BindToRenderStep("RowFade", Enum.RenderPriority.Last.Value, function()
    if currentCameraRow == nil then return end
    applyRowVisibility(currentCameraRow)
end)

-- ── Camera ─────────────────────────────────────────────────

local function getTargetCFrame(rootPart)
    local pos    = rootPart.Position
    local focus  = pos + Vector3.new(0, FOCUS_HEIGHT, 0)
    local camPos = pos + Vector3.new(CAM_SIDE, CAM_HEIGHT, CAM_DISTANCE)
    local forward = (focus - camPos).Unit
    local right   = forward:Cross(Vector3.new(0, 1, 0)).Unit
    local up      = right:Cross(forward).Unit
    return CFrame.fromMatrix(camPos, right, up, -forward)
end

local panFromCFrame = nil
local panStartTime  = 0
local panTargetRoot = nil

local tweenTo

local function onCameraLocked(rootPart)
    if not rootPart or not rootPart.Parent then return end
    lastLockTime = tick()

    local cameraRow = getModelRow(rootPart.Parent)
    local hidden, _ = setCameraRow(cameraRow)
    notifyServerFades(rootPart)

    local camLetter = rowLabel(cameraRow)
    print("[Fade] Camera on row " .. camLetter
        .. " (" .. rootPart.Parent.Name .. ") — hid "
        .. hidden .. " dancer(s) in rows in front of " .. camLetter)

    if cameraReadyEvent then
        pcall(function() cameraReadyEvent:FireServer() end)
    end

    if pendingFocus and pendingFocus.Parent and pendingFocus ~= rootPart then
        local next = pendingFocus
        pendingFocus = nil
        task.defer(function()
            if next and next.Parent then tweenTo(next) end
        end)
    else
        pendingFocus = nil
    end
end

tweenTo = function(rootPart)
    if not rootPart or not rootPart.Parent then return end

    currentTarget  = rootPart
    isTweening     = true
    tweenStartTime = tick()
    panStartTime   = tweenStartTime
    panFromCFrame  = camera.CFrame
    panTargetRoot  = rootPart
    pendingFocus   = nil

    -- Hide blockers for the destination row immediately (don't reset everyone visible).
    local cameraRow = getModelRow(rootPart.Parent)
    setCameraRow(cameraRow)
    notifyServerFades(rootPart)
end

local function requestFocus(rootPart)
    if not rootPart or not rootPart.Parent then return end
    if isTweening then
        pendingFocus = rootPart
        return
    end
    tweenTo(rootPart)
end

local function removePart(target)
    for i, p in ipairs(activeParts) do
        if p == target then
            table.remove(activeParts, i)
            cycleIndex = math.clamp(cycleIndex, 1, math.max(1, #activeParts))
            break
        end
    end
end

if despawnEvent then
    despawnEvent.OnClientEvent:Connect(function(username)
        for i = #activeParts, 1, -1 do
            local root = activeParts[i]
            if root and root.Parent and root.Parent.Name == username then
                if currentTarget == root then currentTarget = nil end
                if pendingFocus == root then pendingFocus = nil end
                rootRows[root] = nil
                table.remove(activeParts, i)
                cycleIndex = math.clamp(cycleIndex, 1, math.max(1, #activeParts))
                break
            end
        end
    end)
end

if queueStatusEvent then
    queueStatusEvent.OnClientEvent:Connect(function(hasItems)
        queueHasItems = hasItems
    end)
end

if focusEvent then
    focusEvent.OnClientEvent:Connect(function(model, spawnRow)
        if not model or not model.Parent then return end
        local rootPart = model:WaitForChild("HumanoidRootPart", 5)
        if not rootPart then return end

        if typeof(spawnRow) == "number" then
            rootRows[rootPart] = spawnRow
        end

        local alreadyTracked = false
        for _, p in ipairs(activeParts) do
            if p == rootPart then alreadyTracked = true break end
        end

        if not alreadyTracked then
            table.insert(activeParts, rootPart)
            rootPart.AncestryChanged:Connect(function()
                if not rootPart.Parent then
                    removePart(rootPart)
                    rootRows[rootPart] = nil
                    if currentTarget == rootPart then currentTarget = nil end
                    if pendingFocus == rootPart then pendingFocus = nil end
                    if #activeParts == 0 then clearAllFades() end
                end
            end)
        end

        for i, p in ipairs(activeParts) do
            if p == rootPart then cycleIndex = i break end
        end
        requestFocus(rootPart)
        print("[Camera] → " .. model.Name .. " (row " .. rowLabel(getModelRow(model)) .. ")")
    end)
end

task.spawn(function()
    while true do
        task.wait(1)

        for i = #activeParts, 1, -1 do
            if not activeParts[i] or not activeParts[i].Parent then
                table.remove(activeParts, i)
            end
        end

        if #activeParts == 0 then
            clearAllFades()
            currentTarget = nil
            isTweening = false
            lastLockTime = 0
            continue
        end

        cycleIndex = math.clamp(cycleIndex, 1, #activeParts)

        if isTweening and (tick() - tweenStartTime) > TWEEN_DURATION + 1 then
            warn("[Camera] Pan stuck — forcing lock")
            isTweening = false
            local stuck = panTargetRoot or currentTarget
            panTargetRoot = nil
            if stuck and stuck.Parent then
                currentTarget = stuck
                camera.CFrame = getTargetCFrame(stuck)
                onCameraLocked(stuck)
            end
        end

        if not isTweening and not pendingFocus and lastLockTime > 0
            and (tick() - lastLockTime) >= CYCLE_INTERVAL
            and not queueHasItems then

            local currentIdx = 1
            for i, p in ipairs(activeParts) do
                if p == currentTarget then currentIdx = i break end
            end

            if currentTarget == nil or not currentTarget.Parent then
                cycleIndex = math.random(1, #activeParts)
                local target = activeParts[cycleIndex]
                if target and target.Parent then
                    tweenTo(target)
                    print("[Camera] Recover → " .. target.Parent.Name)
                end
            elseif #activeParts > 1 then
                local nextIndex = currentIdx
                repeat
                    nextIndex = math.random(1, #activeParts)
                until nextIndex ~= currentIdx
                cycleIndex = nextIndex
                local target = activeParts[cycleIndex]
                if target and target.Parent then
                    tweenTo(target)
                    print("[Camera] Cycle → " .. target.Parent.Name
                        .. " [" .. cycleIndex .. "/" .. #activeParts .. "]")
                end
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if camera.CameraType ~= Enum.CameraType.Scriptable then
        camera.CameraType = Enum.CameraType.Scriptable
    end

    if isTweening and panTargetRoot and panTargetRoot.Parent then
        local elapsed = tick() - panStartTime
        local t = math.clamp(elapsed / TWEEN_DURATION, 0, 1)
        t = 0.5 - 0.5 * math.cos(t * math.pi)
        local goal = getTargetCFrame(panTargetRoot)
        camera.CFrame = panFromCFrame:Lerp(goal, t)
        if elapsed >= TWEEN_DURATION then
            isTweening = false
            local lockedRoot = panTargetRoot
            panTargetRoot = nil
            if lockedRoot and lockedRoot.Parent then
                currentTarget = lockedRoot
                camera.CFrame = getTargetCFrame(lockedRoot)
                onCameraLocked(lockedRoot)
            end
        end
        return
    end

    if not currentTarget or not currentTarget.Parent then return end
    camera.CFrame = camera.CFrame:Lerp(getTargetCFrame(currentTarget), FOLLOW_ALPHA)
end)

if focusEvent then
    print("[Camera] Ready — connected to SpawnScript")
else
    warn("[Camera] Running without SpawnScript — camera will show the floor but no spawns will arrive")
end
