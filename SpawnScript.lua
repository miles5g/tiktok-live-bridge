-- ============================================================
-- SpawnScript  |  ServerScriptService > Script
-- Polls the Node.js backend and spawns viewer avatars.
-- ============================================================
-- WHERE TO PUT THIS:
--   Roblox Studio → Explorer → ServerScriptService
--   Right-click → Insert Object → Script → paste this in
-- ============================================================

local HttpService    = game:GetService("HttpService")
local Players        = game:GetService("Players")
local Debris         = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Config ────────────────────────────────────────────────
local SERVER_URL      = "http://localhost:3000"
local POLL_INTERVAL   = 2    -- seconds between queue checks
local DANCE_DURATION  = 600  -- safety failsafe max (10 min) — floor bumps before this
local MAX_ON_SCREEN   = 20
local GRID_COLS       = 5    -- characters per row on the floor
local GRID_SPACING    = 5    -- studs between characters

-- R15 HumanoidRootPart sits ~3 studs above the character's feet.
-- We add this so characters land ON the floor rather than through it.
local CHAR_ROOT_HEIGHT = 3

-- Dance animation IDs — loaded CLIENT-SIDE.
-- Studio Play mode has a serverplaceid=0 restriction that blocks most external assets.
-- ONLY IDs pre-cached in Roblox Studio's local bundle load reliably here.
-- Verified working in Studio (tested ✅):
-- These 4 are confirmed to load from Studio's local asset cache.
-- All others fail with serverplaceid=0 in Studio Play mode.
-- To unlock 50+ dances: stream the published Roblox CLIENT (not Studio).
local DANCE_ANIMS = {
    "507771019",  -- Robot      ✅ confirmed
    "507776043",  -- Dance 2    ✅ confirmed
    "507770453",  -- Breakdance ✅ confirmed
    "507771955",  -- Shufflin   ✅ confirmed
}

-- ── Setup ─────────────────────────────────────────────────

-- RemoteEvent: camera follows newest character
local focusEvent = Instance.new("RemoteEvent")
focusEvent.Name   = "FocusOnCharacter"
focusEvent.Parent = ReplicatedStorage

-- RemoteEvent: client plays dance animation on spawned model
-- MUST be client-side — server-side animation fails with serverplaceid=0 in Studio
local animateEvent = Instance.new("RemoteEvent")
animateEvent.Name   = "AnimateCharacter"
animateEvent.Parent = ReplicatedStorage

-- Reference point — name this Part "SpawnLocation" in your map
local spawnAnchor = workspace:WaitForChild("SpawnLocation")

-- Fixed grid of 20 spawn positions around the anchor
local function buildSpawnSlots()
    local slots = {}
    for i = 0, MAX_ON_SCREEN - 1 do
        local col = i % GRID_COLS
        local row = math.floor(i / GRID_COLS)
        local offset = Vector3.new(
            (col - math.floor(GRID_COLS / 2)) * GRID_SPACING,
            spawnAnchor.Size.Y / 2 + CHAR_ROOT_HEIGHT,
            row * GRID_SPACING
        )
        slots[i + 1] = {
            position = spawnAnchor.Position + offset,
            occupied = false,
        }
    end
    return slots
end

local spawnSlots = buildSpawnSlots()

local function claimSlot()
    for _, slot in ipairs(spawnSlots) do
        if not slot.occupied then
            slot.occupied = true
            return slot
        end
    end
    return nil
end

local function releaseSlot(slot)
    if slot then slot.occupied = false end
end

-- ── Helpers ───────────────────────────────────────────────

-- Animation is handled entirely by AnimateScript (LocalScript, client-side).
-- We just pick a random ID here and send it over the wire.
local function getRandomAnimId()
    return DANCE_ANIMS[math.random(#DANCE_ANIMS)]
end

local function hardDestroy(model, slot)
    pcall(function()
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum then hum:UnequipTools() end
        model.Parent = nil
        model:Destroy()
    end)
    releaseSlot(slot)
end

local function notifyDone(username)
    pcall(function()
        HttpService:PostAsync(
            SERVER_URL .. "/api/queue/done",
            HttpService:JSONEncode({ username = username }),
            Enum.HttpContentType.ApplicationJson
        )
    end)
end

-- ── Spawn ─────────────────────────────────────────────────

local function spawnCharacter(username)
    -- Small yield so the API isn't hammered back-to-back
    task.wait(0.5)

    -- 1. Validate username exists on Roblox
    local ok1, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if not ok1 or not userId then
        warn("[Spawn] GetUserIdFromNameAsync failed for '" .. username .. "': " .. tostring(userId))
        notifyDone(username)
        return
    end
    print("[Spawn] Got userId " .. tostring(userId) .. " for " .. username)

    -- 2. Fetch their avatar description
    local ok2, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not ok2 or not desc then
        warn("[Spawn] GetHumanoidDescriptionFromUserId failed for '" .. username .. "': " .. tostring(desc))
        notifyDone(username)
        return
    end

    -- 3. Build the 3D rig
    local ok3, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not ok3 or not model then
        warn("[Spawn] CreateHumanoidModelFromDescription failed for '" .. username .. "': " .. tostring(model))
        notifyDone(username)
        return
    end

    -- 4. Claim a slot and position the character
    local slot = claimSlot()
    if not slot then
        warn("[Spawn] No slots — should not happen if server is correct")
        model:Destroy()
        notifyDone(username)
        return
    end

    model.Name = username
    -- Ensure PrimaryPart is set (CreateHumanoidModelFromDescription should do this,
    -- but we guard against edge cases)
    if not model.PrimaryPart then
        model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
    end
    model.Parent = workspace
    -- Rotate 180° so characters face the camera (positive Z direction)
    model:SetPrimaryPartCFrame(CFrame.new(slot.position) * CFrame.Angles(0, math.pi, 0))

    -- 5. Tell clients to play a dance animation on this model (client-side loading)
    local animId = getRandomAnimId()
    animateEvent:FireAllClients(model, animId)

    -- 6. Tell the camera to swing to this character.
    -- Pass the MODEL (not PrimaryPart) — PrimaryPart can be nil immediately after spawn.
    -- CameraScript will find HumanoidRootPart itself.
    focusEvent:FireAllClients(model)

    -- Safety fallback: Debris auto-removes if the task.delay ever hangs
    Debris:AddItem(model, DANCE_DURATION + 10)

    -- 7. Schedule clean removal after DANCE_DURATION seconds
    task.delay(DANCE_DURATION, function()
        hardDestroy(model, slot)
        notifyDone(username)
        print("[Done] " .. username .. " left the floor.")
    end)

    print("[Spawn] " .. username .. " on the floor! (" .. (slot.occupied and "slot OK" or "?") .. ")")
end

-- ── Startup Reset ─────────────────────────────────────────
-- Tell the server this is a fresh session so stale activeOnScreen is cleared.
-- This fires every time you hit Play in Studio or the game server starts.

print("[Server] SpawnScript starting — sending reset signal...")
pcall(function()
    HttpService:PostAsync(
        SERVER_URL .. "/api/reset",
        "{}",
        Enum.HttpContentType.ApplicationJson
    )
end)
print("[Server] Reset sent. Starting poll loop.")

-- ── Main Poll Loop ─────────────────────────────────────────

print("[Server] SpawnScript running — polling " .. SERVER_URL)

while true do
    task.wait(POLL_INTERVAL)

    local ok, raw = pcall(function()
        return HttpService:GetAsync(SERVER_URL .. "/api/queue/next", true)
    end)

    if not ok or not raw then
        warn("[Poll] Cannot reach Node.js server. Is `node server.js` running?")
    else
        local parseOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if parseOk and data then
            if data.status == "spawn" and data.username then
                print("[Poll] Spawning " .. data.username .. " [" .. (data.type or "Regular") .. "]")
                task.spawn(spawnCharacter, data.username)

            elseif data.status == "bump" and data.evict and data.username then
                -- Evict the oldest character to make room, then spawn the new one
                print("[Bump] Evicting " .. data.evict .. " → Spawning " .. data.username)
                local evictModel = workspace:FindFirstChild(data.evict)
                if evictModel then
                    local hum = evictModel:FindFirstChildOfClass("Humanoid")
                    if hum then pcall(function() hum:UnequipTools() end) end
                    -- Release that character's slot
                    for _, slot in ipairs(spawnSlots) do
                        if slot.occupied then
                            -- Match by position proximity
                            local root = evictModel:FindFirstChild("HumanoidRootPart")
                            if root then
                                local dist = (root.Position - slot.position).Magnitude
                                if dist < GRID_SPACING then
                                    slot.occupied = false
                                    break
                                end
                            end
                        end
                    end
                    pcall(function()
                        evictModel.Parent = nil
                        evictModel:Destroy()
                    end)
                end
                task.spawn(spawnCharacter, data.username)
            end
        end
    end
end
