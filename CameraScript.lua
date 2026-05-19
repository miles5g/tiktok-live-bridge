-- ============================================================
-- CameraScript  |  StarterPlayerScripts > LocalScript
-- Portrait-optimized cinematic camera for TikTok 9:16.
--
-- Behavior:
--   1. New character spawns → camera immediately tweens to them
--   2. After CYCLE_INTERVAL seconds → moves to next character
--   3. Cycles from newest → progressively older → oldest
--   4. After oldest is featured → wraps back to newest on floor
--   5. When characters despawn, they're removed from the cycle
-- ============================================================
-- WHERE TO PUT THIS:
--   Roblox Studio → StarterPlayer → StarterPlayerScripts → LocalScript
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

-- Re-enforce every frame — Roblox's default PlayerModule can override this on load
RunService.RenderStepped:Connect(function()
    if camera.CameraType ~= Enum.CameraType.Scriptable then
        camera.CameraType = Enum.CameraType.Scriptable
    end
end)

-- ── Config ────────────────────────────────────────────────

local CAM_DISTANCE     = 28    -- studs behind target
local CAM_HEIGHT       = 14    -- studs above floor
local CAM_SIDE         = 2     -- slight 3/4 angle
local FOCUS_HEIGHT     = 3     -- aim at chest height
local TWEEN_DURATION   = 2.2   -- seconds per camera swing
local FOLLOW_ALPHA     = 0.04  -- drift smoothness while locked
local CYCLE_INTERVAL   = 5     -- seconds before moving to next character

-- ── State ─────────────────────────────────────────────────

-- Ordered list: [1] = oldest on floor, [#] = newest
-- cycleIndex counts DOWN from newest to oldest, then wraps
local activeParts  = {}
local cycleIndex   = 1
local currentTarget = nil
local isTweening   = false
local lastCycleTime = 0

-- ── Helpers ───────────────────────────────────────────────

local function getTargetCFrame(rootPart)
    local pos   = rootPart.Position
    local focus = pos + Vector3.new(0, FOCUS_HEIGHT, 0)
    local camPos = pos + Vector3.new(CAM_SIDE, CAM_HEIGHT, CAM_DISTANCE)
    return CFrame.lookAt(camPos, focus)
end

local function tweenTo(rootPart)
    if not rootPart or not rootPart.Parent then return end
    currentTarget = rootPart
    isTweening    = true

    local goal = getTargetCFrame(rootPart)
    local info  = TweenInfo.new(
        TWEEN_DURATION,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut
    )
    local tween = TweenService:Create(camera, info, { CFrame = goal })
    tween.Completed:Connect(function() isTweening = false end)
    tween:Play()
end

-- Remove a PrimaryPart from the active list and adjust cycleIndex
local function removePart(target)
    for i, p in ipairs(activeParts) do
        if p == target then
            table.remove(activeParts, i)
            -- Keep cycleIndex in bounds
            if #activeParts == 0 then
                cycleIndex = 1
            else
                cycleIndex = math.clamp(cycleIndex, 1, #activeParts)
            end
            break
        end
    end
end

-- ── Event: new character spawned ──────────────────────────

local focusEvent = ReplicatedStorage:WaitForChild("FocusOnCharacter", 30)

focusEvent.OnClientEvent:Connect(function(model)
    print("[Camera] FocusOnCharacter received for model: " .. tostring(model))
    if not model or not model.Parent then
        warn("[Camera] model is nil or has no parent — skipping")
        return
    end

    -- Wait briefly for the HumanoidRootPart to exist after replication
    local rootPart = model:WaitForChild("HumanoidRootPart", 5)
    if not rootPart then
        warn("[Camera] HumanoidRootPart not found on: " .. model.Name)
        return
    end

    -- Avoid duplicates
    for _, p in ipairs(activeParts) do
        if p == rootPart then return end
    end

    -- Insert at end = newest
    table.insert(activeParts, rootPart)
    cycleIndex = #activeParts  -- feature this new character first

    -- Auto-remove when character despawns
    rootPart.AncestryChanged:Connect(function()
        if not rootPart.Parent then
            removePart(rootPart)
            if currentTarget == rootPart and #activeParts > 0 then
                local safeIndex = math.clamp(cycleIndex, 1, #activeParts)
                tweenTo(activeParts[safeIndex])
                lastCycleTime = tick()
            end
        end
    end)

    -- Swing to new character and reset cycle timer
    tweenTo(rootPart)
    lastCycleTime = tick()

    print("[Camera] Tweening to: " .. model.Name
        .. " | Active on floor: " .. #activeParts
        .. " | CameraType: " .. tostring(camera.CameraType))
end)

-- ── Cycle loop ────────────────────────────────────────────
-- Runs every frame; advances to next character when timer expires.

RunService.Heartbeat:Connect(function()
    -- Prune any destroyed parts
    for i = #activeParts, 1, -1 do
        if not activeParts[i] or not activeParts[i].Parent then
            table.remove(activeParts, i)
        end
    end

    if #activeParts == 0 then return end

    -- Clamp cycleIndex
    cycleIndex = math.clamp(cycleIndex, 1, #activeParts)

    -- Time to move to next character?
    if not isTweening and (tick() - lastCycleTime) >= CYCLE_INTERVAL then
        -- Count DOWN: newest → progressively older → oldest → wrap to newest
        cycleIndex = cycleIndex - 1
        if cycleIndex < 1 then
            cycleIndex = #activeParts  -- wrap back to newest
        end

        local target = activeParts[cycleIndex]
        if target and target.Parent then
            tweenTo(target)
            lastCycleTime = tick()
            print("[Camera] Cycling to: " .. (target.Parent and target.Parent.Name or "?")
                .. " [" .. cycleIndex .. "/" .. #activeParts .. "]")
        end
    end
end)

-- ── Drift follow while locked on target ───────────────────

RunService.RenderStepped:Connect(function()
    if isTweening then return end
    if not currentTarget or not currentTarget.Parent then return end
    local desired = getTargetCFrame(currentTarget)
    camera.CFrame  = camera.CFrame:Lerp(desired, FOLLOW_ALPHA)
end)

-- ── Default idle position (empty floor) ───────────────────

local STAGE_CENTER = Vector3.new(0, 5, 7.5)
local idleCamPos   = STAGE_CENTER + Vector3.new(CAM_SIDE, CAM_HEIGHT, CAM_DISTANCE)
camera.CFrame      = CFrame.lookAt(idleCamPos, STAGE_CENTER)

print("[Camera] Ready — cycles every " .. CYCLE_INTERVAL .. "s | Portrait 9:16")
