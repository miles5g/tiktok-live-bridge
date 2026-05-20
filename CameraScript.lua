-- ============================================================
-- CameraScript  |  StarterPlayerScripts > LocalScript
-- Portrait-optimized cinematic camera for TikTok 9:16.
-- Cycles through spawned characters (oldest → newest → loop).
-- Front-row characters fade when camera focuses on back row.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

-- ── Config ────────────────────────────────────────────────

local CAM_DISTANCE   = 10    -- studs behind target (body shot distance)
local CAM_HEIGHT     = 2     -- studs above root (chest level)
local CAM_SIDE       = 0     -- dead center, head-on shot
local FOCUS_HEIGHT   = 2     -- match CAM_HEIGHT so camera looks straight ahead
local TWEEN_DURATION = 2.2   -- seconds per camera swing
local FOLLOW_ALPHA   = 0.04  -- drift smoothness
local CYCLE_INTERVAL = 5     -- seconds per character (matches spawn cadence)
local FADE_ALPHA     = 1.0   -- fully invisible when blocking the camera shot

-- ── State ─────────────────────────────────────────────────

local activeParts   = {}
local cycleIndex    = 1
local currentTarget = nil
local isTweening     = false
local tweenStartTime = 0
local lastCycleTime  = 0
local queueHasItems  = false  -- true while Node.js queue is non-empty

-- ── Fade helpers (declared BEFORE tweenTo so scoping works) ──
-- Uses LocalTransparencyModifier (the correct client-side API).
-- A periodic refresh loop re-applies fades every 0.5s to catch
-- accessories/clothing that load AFTER the initial setModelFade call.

local fadedModels = {}  -- set of models currently faded out

local function setModelFade(model, alpha)
    if not model or not model.Parent then return end
    local fading = alpha >= 1.0
    fadedModels[model] = fading or nil

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart")
            and desc.Name ~= "HumanoidRootPart"
            and not desc.Name:match("^NamePlaque_") then
            -- Set both properties: LTM is the correct client-side API,
            -- Transparency is the fallback for cases where LTM is unreliable
            -- (server never changes these after spawn so local value persists).
            desc.LocalTransparencyModifier = fading and 1 or 0
            desc.Transparency = fading and 1 or 0
        end
    end
    -- Pause/resume animations to save CPU when invisible
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            local speed = fading and 0 or 0.75
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(speed)
            end
        end
    end
end

-- Periodic refresh: re-applies fades to catch late-loading accessories/clothing
task.spawn(function()
    while true do
        task.wait(0.5)
        for model, _ in pairs(fadedModels) do
            if model and model.Parent then
                for _, desc in ipairs(model:GetDescendants()) do
                    if desc:IsA("BasePart")
                        and desc.Name ~= "HumanoidRootPart"
                        and not desc.Name:match("^NamePlaque_") then
                        desc.LocalTransparencyModifier = 1
                        desc.Transparency = 1
                    end
                end
            else
                fadedModels[model] = nil  -- clean up destroyed models
            end
        end
    end
end)

local function updateFades(focusRoot)
    if not focusRoot or not focusRoot.Parent then return end
    local focusModel = focusRoot.Parent
    local focusRow   = focusModel and focusModel:GetAttribute("SpawnRow")

    for _, root in ipairs(activeParts) do
        if root and root.Parent then
            local model    = root.Parent
            local modelRow = model:GetAttribute("SpawnRow")

            if root == focusRoot then
                setModelFade(model, 0)                    -- focused char: always visible
            elseif focusRow and modelRow and modelRow > focusRow then
                setModelFade(model, FADE_ALPHA)           -- closer to camera than focus: fade
            else
                setModelFade(model, 0)                    -- same row or behind: visible
            end
        end
    end
end

local function clearAllFades()
    for _, root in ipairs(activeParts) do
        if root and root.Parent then
            setModelFade(root.Parent, 0)
        end
    end
end

-- ── Camera helpers ─────────────────────────────────────────

local function getTargetCFrame(rootPart)
    local pos    = rootPart.Position
    local focus  = pos + Vector3.new(0, FOCUS_HEIGHT, 0)
    local camPos = pos + Vector3.new(CAM_SIDE, CAM_HEIGHT, CAM_DISTANCE)
    local forward = (focus - camPos).Unit
    local right   = forward:Cross(Vector3.new(0, 1, 0)).Unit
    local up      = right:Cross(forward).Unit
    return CFrame.fromMatrix(camPos, right, up, -forward)
end

local function tweenTo(rootPart)
    if not rootPart or not rootPart.Parent then return end
    currentTarget  = rootPart
    isTweening     = true
    tweenStartTime = tick()

    -- Clear all fades while panning so nothing disappears mid-swing.
    -- updateFades() fires on tween.Completed to fade front-row chars
    -- only once the camera has fully settled on the target.
    clearAllFades()

    local tween = TweenService:Create(
        camera,
        TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        { CFrame = getTargetCFrame(rootPart) }
    )
    tween.Completed:Connect(function(status)
        -- Ignore cancellations: when tweenTo() is called again mid-pan,
        -- the old tween fires Completed with Cancelled status. Acting on
        -- that would reopen the spawn gate and reset isTweening too early.
        if status ~= Enum.TweenStatus.Completed then return end

        isTweening = false
        if currentTarget == rootPart then
            updateFades(rootPart)
            -- Re-apply 0.4s later to catch accessories that loaded after the
            -- initial fade call (they start with LTM=0 and need a second pass).
            task.delay(0.4, function()
                if currentTarget == rootPart then
                    updateFades(rootPart)
                end
            end)
            -- Tell the server who the camera is on so it won't despawn them mid-shot.
            local modelName = rootPart.Parent and rootPart.Parent.Name or ""
            pcall(function() cameraFocusEvent:FireServer(modelName) end)
        end
        -- Signal SpawnScript: camera has fully landed, safe to load next character.
        pcall(function() cameraReadyEvent:FireServer() end)
    end)
    tween:Play()
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

-- ── Enforce Scriptable camera type ────────────────────────

RunService.RenderStepped:Connect(function()
    if camera.CameraType ~= Enum.CameraType.Scriptable then
        camera.CameraType = Enum.CameraType.Scriptable
    end
end)

-- ── Early despawn notification ─────────────────────────────
-- SpawnScript fires this BEFORE destroying a model so we drop it from
-- activeParts immediately instead of waiting for replication to arrive.

local despawnEvent = ReplicatedStorage:WaitForChild("DespawnCharacter", 30)
despawnEvent.OnClientEvent:Connect(function(username)
    for i = #activeParts, 1, -1 do
        local root = activeParts[i]
        if root and root.Parent and root.Parent.Name == username then
            local wasFocused = (currentTarget == root)
            table.remove(activeParts, i)
            cycleIndex = math.clamp(cycleIndex, 1, math.max(1, #activeParts))
            if wasFocused then
                currentTarget = nil
            end
            -- Clean up any fade state for this model
            fadedModels[root.Parent] = nil
            break
        end
    end
end)

-- ── Camera-ready gate ──────────────────────────────────────
-- Fired to the server each time the camera finishes tweening so SpawnScript
-- knows it's safe to load the next character.

local cameraReadyEvent  = ReplicatedStorage:WaitForChild("CameraReady",  30)
local cameraFocusEvent  = ReplicatedStorage:WaitForChild("CameraFocus",  30)

-- ── Queue status ───────────────────────────────────────────
-- SpawnScript fires this every poll so we know whether to hold the camera
-- or let the cycle loop advance to the next on-screen character.

local queueStatusEvent = ReplicatedStorage:WaitForChild("QueueStatus", 30)
queueStatusEvent.OnClientEvent:Connect(function(hasItems)
    queueHasItems = hasItems
end)

-- ── Event: new character spawned ──────────────────────────

local focusEvent = ReplicatedStorage:WaitForChild("FocusOnCharacter", 30)

focusEvent.OnClientEvent:Connect(function(model)
    if not model or not model.Parent then return end

    local rootPart = model:WaitForChild("HumanoidRootPart", 5)
    if not rootPart then return end

    for _, p in ipairs(activeParts) do
        if p == rootPart then return end
    end

    local wasEmpty = (#activeParts == 0)
    table.insert(activeParts, rootPart)

    rootPart.AncestryChanged:Connect(function()
        if not rootPart.Parent then
            local wasFocused = (currentTarget == rootPart)
            removePart(rootPart)

            if #activeParts == 0 then
                clearAllFades()
                currentTarget = nil
            elseif wasFocused then
                -- Don't immediately jump to another slot — that causes the
                -- "empty cell A1" glitch. If the queue has someone coming,
                -- hold position until focusEvent fires for the new arrival.
                -- If queue is empty, the cycle loop picks the next character
                -- within CYCLE_INTERVAL seconds.
                currentTarget = nil
            end
        end
    end)

    -- Pan to the new arrival and align cycleIndex to their position in the array
    -- so the next cycle() call advances forward from here, not from A1.
    for i, p in ipairs(activeParts) do
        if p == rootPart then cycleIndex = i break end
    end
    tweenTo(rootPart)
    lastCycleTime = tick()
    print("[Camera] → " .. model.Name .. " (" .. #activeParts .. " on floor)")
end)

-- ── Fade keeper ────────────────────────────────────────────
-- Re-applies correct fades every second whenever the camera is
-- settled (not tweening). Catches any missed tween.Completed
-- callbacks and fixes fades after cycle transitions.
task.spawn(function()
    while true do
        task.wait(0.3)
        if not isTweening and currentTarget and currentTarget.Parent then
            updateFades(currentTarget)
        end
    end
end)

-- ── Cycle loop ─────────────────────────────────────────────

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
            continue
        end

        cycleIndex = math.clamp(cycleIndex, 1, #activeParts)

        -- Safety: if tween has been running longer than expected, force-unlock.
        -- Also apply fades and reopen the spawn gate since tween.Completed
        -- won't fire after a force-unlock, so those would otherwise be skipped.
        if isTweening and (tick() - tweenStartTime) > TWEEN_DURATION + 1.5 then
            isTweening = false
            print("[Camera] Tween timeout — force-unlocked")
            if currentTarget and currentTarget.Parent then
                updateFades(currentTarget)
            end
            pcall(function() cameraReadyEvent:FireServer() end)
            -- Let the cycle loop pick the next character naturally.
            -- (Previously called tweenTo here which caused clearAllFades
            -- to fire immediately, wiping fades before the keeper ran.)
            lastCycleTime = 0  -- expire the timer so cycle fires next iteration
        end

        if not isTweening and (tick() - lastCycleTime) >= CYCLE_INTERVAL then
            if queueHasItems then
                -- New character incoming — hold position, don't cycle.
                -- focusEvent will move the camera as soon as they spawn.
            elseif currentTarget == nil then
                -- Previous target left; recover to a random character still present.
                cycleIndex = math.random(1, #activeParts)
                local target = activeParts[cycleIndex]
                if target and target.Parent then
                    tweenTo(target)
                    lastCycleTime = tick()
                    print("[Camera] Recover → " .. (target.Parent and target.Parent.Name or "?"))
                end
            else
                -- Pick a random character that isn't the current one.
                -- This keeps the floor feeling lively rather than sweeping
                -- predictably back to A1 after every new arrival.
                local nextIndex = cycleIndex
                if #activeParts > 1 then
                    repeat
                        nextIndex = math.random(1, #activeParts)
                    until nextIndex ~= cycleIndex
                end
                cycleIndex = nextIndex
                local target = activeParts[cycleIndex]
                if target and target.Parent then
                    tweenTo(target)
                    lastCycleTime = tick()
                    print("[Camera] Cycle → " .. (target.Parent and target.Parent.Name or "?")
                        .. " [" .. cycleIndex .. "/" .. #activeParts .. "]")
                end
            end
        end
    end
end)

-- ── Drift follow ───────────────────────────────────────────

RunService.RenderStepped:Connect(function()
    if isTweening then return end
    if not currentTarget or not currentTarget.Parent then return end
    camera.CFrame = camera.CFrame:Lerp(getTargetCFrame(currentTarget), FOLLOW_ALPHA)
end)

-- ── Default idle position (empty floor) ───────────────────

local IDLE_CAM    = Vector3.new(0, 12, 25)
local IDLE_TARGET = Vector3.new(0, 8, -6)
camera.CFrame = CFrame.lookAt(IDLE_CAM, IDLE_TARGET)

print("[Camera] Ready — " .. CYCLE_INTERVAL .. "s per character, fade-on-block enabled")
