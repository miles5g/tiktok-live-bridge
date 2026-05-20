-- ============================================================
-- SpawnScript  |  ServerScriptService > Script
-- Polls the Node.js backend and spawns viewer avatars.
-- ============================================================
-- WHERE TO PUT THIS:
--   Roblox Studio → Explorer → ServerScriptService
--   Right-click → Insert Object → Script → paste this in
--
-- ⚠️  This is the SERVER script. Do NOT paste CameraScript.lua here.
--     CameraScript uses RenderStepped and will crash if run on the server.
-- ============================================================

local RunService        = game:GetService("RunService")
if RunService:IsClient() then
    error("[SpawnScript] Wrong place — use ServerScriptService > Script, not a LocalScript.")
end

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService       = game:GetService("TextService")
local TweenService      = game:GetService("TweenService")

-- ── Config ────────────────────────────────────────────────
local SERVER_URL      = "https://ricotta-mounted-extortion.ngrok-free.dev"
local POLL_INTERVAL   = 1    -- seconds between queue checks
local SPAWN_COOLDOWN  = 5    -- minimum seconds between spawns (each character gets 5s spotlight)
local DANCE_DURATION  = 60   -- seconds before a character expires
local KEEP_RECENT     = 5    -- always keep the most recent N characters alive
local MAX_ON_SCREEN   = 20
local GRID_COLS       = 5    -- characters per row on the floor
local GRID_SPACING    = 5    -- studs between characters

local SEED_USERS = {
    "builderman", "Roblox", "Stickmasterluke", "Merely",
    "Seranok", "Asimo3089", "Brighteyes", "Litozinnamon",
    "DenisDaily", "Poke",
}

-- Featured rotation: popular Roblox accounts cycled in every 60s
-- when real-viewer queue is empty and the floor has room.
-- Ordered roughly by follower count / fame.
local FEATURED_ROTATION = {
    "Roblox", "builderman", "Stickmasterluke", "Merely",
    "Seranok", "Asimo3089", "Brighteyes", "Litozinnamon",
    "DenisDaily", "Poke", "Tofuu", "Hyper", "Coeptus",
    "BadccVoid", "CloneTrooper1019", "OrbitalOwen", "Nolan",
    "Lilly_S", "Berezaa", "OFish", "Kikuxz", "Creeperslayer100",
    "Rukiryo", "Defaultio", "Quenty", "ScriptOn", "Explode1",
    "xSuperMarioFan", "Digiitaal", "Linkmon99",
}
local featuredIndex = 1

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

print("[Server] SpawnScript loading — creating RemoteEvents…")

-- RemoteEvent: camera follows newest character
local focusEvent = Instance.new("RemoteEvent")
focusEvent.Name   = "FocusOnCharacter"
focusEvent.Parent = ReplicatedStorage

-- RemoteEvent: client plays dance animation on spawned model
-- MUST be client-side — server-side animation fails with serverplaceid=0 in Studio
local animateEvent = Instance.new("RemoteEvent")
animateEvent.Name   = "AnimateCharacter"
animateEvent.Parent = ReplicatedStorage

-- RemoteEvent: tells CameraScript whether the queue has pending users.
-- Prevents camera from cycling backwards while a new spawn is incoming.
local queueStatusEvent = Instance.new("RemoteEvent")
queueStatusEvent.Name   = "QueueStatus"
queueStatusEvent.Parent = ReplicatedStorage

-- RemoteEvent: tells CameraScript to drop a character from tracking
-- BEFORE the model is destroyed server-side, eliminating replication lag.
local despawnEvent = Instance.new("RemoteEvent")
despawnEvent.Name   = "DespawnCharacter"
despawnEvent.Parent = ReplicatedStorage

-- RemoteEvent: CameraScript fires this (client → server) whenever the
-- camera lands on a new character, so the server knows who is on-screen.
local cameraFocusEvent = Instance.new("RemoteEvent")
cameraFocusEvent.Name   = "CameraFocus"
cameraFocusEvent.Parent = ReplicatedStorage

print("[Server] RemoteEvents ready (AnimateCharacter, FocusOnCharacter, …)")

-- Row letters (must match CameraScript): A=back, D=front (closest to camera).
local ROW_LABELS = { "A", "B", "C", "D" }

local cameraFocusName  = ""
local currentCameraRow = nil   -- 0=A … 3=D; which row the camera is filming
local spawnedNPCs      = {}

local function rowLabel(row)
    if typeof(row) == "number" and row >= 0 and row < #ROW_LABELS then
        return ROW_LABELS[row + 1]
    end
    return "?"
end

local function isInFrontOfCameraRow(dancerRow, cameraRow)
    return typeof(dancerRow) == "number" and typeof(cameraRow) == "number"
        and dancerRow > cameraRow
end

local function setNPCHidden(model, hide)
    if not model or not model.Parent then return end
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
            desc.Transparency = hide and 1 or 0
        elseif desc:IsA("Decal") or desc:IsA("Texture") then
            desc.Transparency = hide and 1 or 0
        elseif desc:IsA("SurfaceGui") then
            desc.Enabled = not hide
        end
    end
end

-- Camera on row A → hide every dancer on rows B, C, D (closer to camera).
local function applyRowVisibility(cameraRow)
    currentCameraRow = cameraRow
    for _, model in ipairs(spawnedNPCs) do
        if model and model.Parent then
            local dancerRow = model:GetAttribute("SpawnRow")
            if cameraRow == nil then
                setNPCHidden(model, false)
            elseif isInFrontOfCameraRow(dancerRow, cameraRow) then
                setNPCHidden(model, true)
            else
                setNPCHidden(model, false)
            end
        end
    end
end

local function trackNPC(model)
    table.insert(spawnedNPCs, model)
    model.DescendantAdded:Connect(function(desc)
        if not desc:IsA("BasePart") then return end
        if desc.Name == "HumanoidRootPart" then return end
        if currentCameraRow ~= nil then
            local dancerRow = model:GetAttribute("SpawnRow")
            if isInFrontOfCameraRow(dancerRow, currentCameraRow) then
                desc.Transparency = 1
            end
        end
    end)
end

local function untrackNPC(model)
    for i, m in ipairs(spawnedNPCs) do
        if m == model then
            table.remove(spawnedNPCs, i)
            break
        end
    end
end

cameraFocusEvent.OnServerEvent:Connect(function(_, username, cameraRow)
    cameraFocusName = username or ""
    if typeof(cameraRow) == "number" and cameraRow >= 0 then
        applyRowVisibility(cameraRow)
        print("[Fade] Server: camera row " .. rowLabel(cameraRow)
            .. " — hiding rows in front of " .. rowLabel(cameraRow))
    elseif username == "" or cameraRow == nil or cameraRow < 0 then
        applyRowVisibility(nil)
    else
        local model = workspace:FindFirstChild(username)
        if model then
            local row = model:GetAttribute("SpawnRow")
            if typeof(row) == "number" then applyRowVisibility(row) end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        if currentCameraRow ~= nil then
            applyRowVisibility(currentCameraRow)
        end
    end
end)

-- RemoteEvent: CameraScript fires this (client → server) once its tween
-- has finished landing on a character. The poll loop waits for this signal
-- before requesting the next spawn, so characters only load after the camera
-- has fully locked onto the current one.
local cameraReadyEvent = Instance.new("RemoteEvent")
cameraReadyEvent.Name   = "CameraReady"
cameraReadyEvent.Parent = ReplicatedStorage

local cameraIsReady   = true   -- open at startup so seeds can spawn freely
local cameraReadyTime = tick() -- tracks when gate was last closed (for timeout)

cameraReadyEvent.OnServerEvent:Connect(function(_player)
    cameraIsReady   = true
    cameraReadyTime = tick()
    print("[Gate] Camera locked — ready for next spawn")
end)


-- Reference point — name this Part "SpawnLocation" in your map
local spawnAnchor = workspace:WaitForChild("SpawnLocation")

-- Build slots in S-shaped order across the grid:
--   Row 0 (back):  col 0 → 4  (left to right)
--   Row 1:         col 4 → 0  (right to left)
--   Row 2:         col 0 → 4  (left to right)
--   Row 3 (front): col 4 → 0  (right to left)
-- New spawns always continue from where the pointer left off.
local function buildSpawnSlots()
    local GRID_ROWS = math.floor(MAX_ON_SCREEN / GRID_COLS)

    -- Build a flat grid of all positions, tagged with (row, col)
    local grid = {}
    for row = 0, GRID_ROWS - 1 do
        for col = 0, GRID_COLS - 1 do
            table.insert(grid, { row = row, col = col })
        end
    end

    -- Checkerboard-first ordering:
    --   Pass 1 → cells where (row+col) is EVEN  (spread across whole floor)
    --   Pass 2 → cells where (row+col) is ODD   (fill the gaps)
    -- Within each pass, preserve the S-route direction per row.
    local function buildPass(parity)
        local pass = {}
        for row = 0, GRID_ROWS - 1 do
            local leftToRight = (row % 2 == 0)
            for step = 0, GRID_COLS - 1 do
                local col = leftToRight and step or (GRID_COLS - 1 - step)
                if (row + col) % 2 == parity then
                    table.insert(pass, { row = row, col = col })
                end
            end
        end
        return pass
    end

    local ordered = {}
    for _, cell in ipairs(buildPass(0)) do table.insert(ordered, cell) end
    for _, cell in ipairs(buildPass(1)) do table.insert(ordered, cell) end

    -- Convert to slot objects (store row so client can do row-based fading)
    local slots = {}
    for _, cell in ipairs(ordered) do
        local offset = Vector3.new(
            (cell.col - math.floor(GRID_COLS / 2)) * GRID_SPACING,
            spawnAnchor.Size.Y / 2 + CHAR_ROOT_HEIGHT,
            cell.row * GRID_SPACING
        )
        table.insert(slots, {
            position = spawnAnchor.Position + offset,
            occupied = false,
            row      = cell.row,   -- 0=A (back) … 3=D (front, near camera)
        })
    end
    return slots
end

local spawnSlots  = buildSpawnSlots()
local sNextIndex  = 1   -- S-route pointer — advances with each spawn, wraps around

local function claimSlot()
    -- Walk forward from sNextIndex in S-order; skip occupied slots
    local count = #spawnSlots
    for attempt = 0, count - 1 do
        local idx = ((sNextIndex - 1 + attempt) % count) + 1
        if not spawnSlots[idx].occupied then
            spawnSlots[idx].occupied = true
            sNextIndex = (idx % count) + 1   -- pointer moves past this slot
            return spawnSlots[idx]
        end
    end
    return nil
end

local function releaseSlot(slot)
    if slot then slot.occupied = false end
end

-- ── Helpers ───────────────────────────────────────────────

-- Animation is handled entirely by AnimateScript (LocalScript, client-side).
-- Cycles through DANCE_ANIMS in order (no random) to avoid repeat-error patterns.
local animIndex = 0
local function getNextAnimId()
    animIndex = (animIndex % #DANCE_ANIMS) + 1
    return DANCE_ANIMS[animIndex]
end

-- Track spawn order so we can protect the most recent KEEP_RECENT characters
local recentModels = {}   -- [1] = oldest ... [n] = newest

local function removeFromRecent(model)
    for i, m in ipairs(recentModels) do
        if m == model then table.remove(recentModels, i) break end
    end
end

local function isProtected(model)
    -- True if model is one of the KEEP_RECENT most recently spawned still alive
    local start = math.max(1, #recentModels - (KEEP_RECENT - 1))
    for i = start, #recentModels do
        if recentModels[i] == model then return true end
    end
    return false
end

local function hardDestroy(model, slot)
    removeFromRecent(model)
    untrackNPC(model)
    -- Notify clients BEFORE destroying so CameraScript drops this character
    -- from activeParts immediately — no waiting for replication lag.
    pcall(function() despawnEvent:FireAllClients(model.Name) end)
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

local spawningNow   = {}  -- usernames currently mid-spawn (locks out duplicates)
local lastSpawnTime = 0   -- tick() of the most recent spawn start

-- Reopen the spawn gate immediately when a spawn fails.
-- Without this, any failed username (bad Roblox name, API error, duplicate)
-- would stall the queue for the full 10s safety timeout.
local function reopenGate()
    cameraIsReady   = true
    cameraReadyTime = tick()
end

local function spawnCharacter(username)
    -- 0a. Lock: block if already being spawned by another concurrent call
    if spawningNow[username] then
        warn("[Spawn] " .. username .. " is already being spawned — skipping")
        notifyDone(username)
        reopenGate()
        return
    end
    spawningNow[username] = true
    lastSpawnTime = tick()   -- start the 5s cooldown clock

    -- Small yield so the API isn't hammered back-to-back
    task.wait(0.5)

    -- 0b. Skip if an NPC with this username is already on the floor.
    -- Ignore the host player's own character (same name but it's a real Player, not an NPC).
    local existingModel = workspace:FindFirstChild(username)
    if existingModel then
        local playerObj = Players:FindFirstChild(username)
        local isHostCharacter = playerObj and playerObj.Character == existingModel
        if not isHostCharacter then
            warn("[Spawn] " .. username .. " is already on the floor — skipping duplicate")
            spawningNow[username] = nil
            notifyDone(username)
            reopenGate()
            return
        end
    end

    -- 1. Validate username exists on Roblox
    local ok1, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if not ok1 or not userId then
        warn("[Spawn] GetUserIdFromNameAsync failed for '" .. username .. "': " .. tostring(userId))
        spawningNow[username] = nil
        notifyDone(username)
        reopenGate()
        return
    end
    print("[Spawn] Got userId " .. tostring(userId) .. " for " .. username)

    -- 2. Fetch their avatar description
    local ok2, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not ok2 or not desc then
        warn("[Spawn] GetHumanoidDescriptionFromUserId failed for '" .. username .. "': " .. tostring(desc))
        spawningNow[username] = nil
        notifyDone(username)
        reopenGate()
        return
    end

    -- 3. Build the 3D rig
    local ok3, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not ok3 or not model then
        warn("[Spawn] CreateHumanoidModelFromDescription failed for '" .. username .. "': " .. tostring(model))
        spawningNow[username] = nil
        notifyDone(username)
        reopenGate()
        return
    end

    -- 4. Claim a slot and position the character
    local slot = claimSlot()
    if not slot then
        warn("[Spawn] No slots — should not happen if server is correct")
        spawningNow[username] = nil
        model:Destroy()
        notifyDone(username)
        reopenGate()
        return
    end

    -- Character is committed to the floor — release the spawn lock
    spawningNow[username] = nil
    model.Name = username
    model:SetAttribute("SpawnRow", slot.row)
    model:SetAttribute("SpawnRowLetter", ROW_LABELS[slot.row + 1])
    trackNPC(model)
    -- Ensure PrimaryPart is set (CreateHumanoidModelFromDescription should do this,
    -- but we guard against edge cases)
    if not model.PrimaryPart then
        model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
    end
    -- Start 40 studs above the floor, then tween down with a bounce
    -- so the character visibly drops from the sky onto their tile.
    local finalCFrame = CFrame.new(slot.position) * CFrame.Angles(0, math.pi, 0)
    local dropCFrame  = CFrame.new(slot.position + Vector3.new(0, 40, 0)) * CFrame.Angles(0, math.pi, 0)
    model:SetPrimaryPartCFrame(dropCFrame)
    model.Parent = workspace

    -- Anchor root during drop so physics doesn't fight the tween
    local root = model:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = true
        local dropTween = TweenService:Create(
            root,
            TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { CFrame = finalCFrame }
        )
        dropTween:Play()
        dropTween.Completed:Connect(function()
            root.Anchored = false  -- re-enable physics after landing
            -- Fire camera focus AFTER landing so the camera isn't
            -- aimed at the sky while the character is mid-drop.
            focusEvent:FireAllClients(model, slot.row)
        end)
    else
        -- No root found — fire focus immediately as fallback
        focusEvent:FireAllClients(model, slot.row)
    end

    -- Spawn effects are triggered by CameraScript AFTER the camera tween
    -- arrives at this character, so the effects play while the camera is
    -- already looking at them. spawnEffectEvent is fired from the client.

    -- 4b. Name plaque — vertical sign standing in front of character, facing camera
    -- Measure text width so the black background hugs the username tightly
    local PIXELS_PER_STUD = 100
    local PLAQUE_H        = 0.6   -- stud height
    local fontPx          = math.floor(PLAQUE_H * PIXELS_PER_STUD * 0.75)
    local textBounds      = TextService:GetTextSize(
        "@" .. username, fontPx, Enum.Font.GothamBold, Vector2.new(2000, 200))
    local plaqueWidth     = math.max(1.2, textBounds.X / PIXELS_PER_STUD + 0.4)  -- 0.4 padding

    local plaque = Instance.new("Part")
    plaque.Name       = "NamePlaque_" .. username
    plaque.Size       = Vector3.new(plaqueWidth, PLAQUE_H, 0.08)
    plaque.CFrame     = CFrame.new(slot.position.X, 2.6, slot.position.Z + 2.3)
    plaque.Color      = Color3.fromRGB(0, 0, 0)
    plaque.Material   = Enum.Material.SmoothPlastic
    plaque.Anchored   = true
    plaque.CanCollide = false
    plaque.CastShadow = false
    plaque.Parent     = model   -- destroyed automatically with the character

    local sg = Instance.new("SurfaceGui")
    sg.Face          = Enum.NormalId.Back   -- +Z face, visible to camera at positive Z
    sg.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
    sg.PixelsPerStud = 100
    sg.Parent        = plaque

    local tl = Instance.new("TextLabel")
    tl.Size                   = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 0.35
    tl.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    tl.TextColor3             = Color3.fromRGB(0, 230, 255)   -- neon cyan
    tl.Text                   = "@" .. username
    tl.TextScaled             = true
    tl.Font                   = Enum.Font.GothamBold
    tl.Parent                 = sg

    -- 5. Tell clients to play a dance animation on this model (client-side loading)
	local animId = getNextAnimId()
    animateEvent:FireAllClients(model, animId)

    -- Register in spawn order for protection logic
    table.insert(recentModels, model)

    -- Hard failsafe: Debris removes after 10 min no matter what
    Debris:AddItem(model, 600)

    -- 7. Schedule removal after DANCE_DURATION, but protect the most recent KEEP_RECENT
    local function tryExpire()
        if not model or not model.Parent then return end  -- already gone

        -- Always protect the most recent KEEP_RECENT characters
        if isProtected(model) then
            task.delay(15, tryExpire)
            return
        end

        -- Never yank a character while the camera is actively showing them —
        -- wait 5 more seconds and re-check so the viewer always has something to watch.
        if cameraFocusName == username then
            task.delay(5, tryExpire)
            return
        end

        -- If nobody is queued, keep everyone alive indefinitely
        local hasQueue = false
        pcall(function()
            local raw  = HttpService:GetAsync(SERVER_URL .. "/api/status", true)
            local data = HttpService:JSONDecode(raw)
            hasQueue   = (data.regularQueueLength + data.vipQueueLength) > 0
        end)

        if not hasQueue then
            -- Empty queue — keep this character, check again in 15s
            task.delay(15, tryExpire)
        else
            -- People are waiting — free up the slot
            hardDestroy(model, slot)
            notifyDone(username)
            print("[Done] " .. username .. " expired — making room for queue.")
        end
    end
    task.delay(DANCE_DURATION, tryExpire)

    print("[Spawn] " .. username .. " on the floor! (" .. (slot.occupied and "slot OK" or "?") .. ")")
end

-- ── Startup Reset ─────────────────────────────────────────
-- Tell the server this is a fresh session so stale activeOnScreen is cleared.
-- This fires every time you hit Play in Studio or the game server starts.

-- Clean up any leftover spawned character models from previous sessions
-- (these accumulate if the place was saved during Play mode by accident)
local playerCharNames = {}
for _, p in ipairs(Players:GetPlayers()) do
    if p.Character then playerCharNames[p.Character.Name] = true end
end
for _, obj in ipairs(workspace:GetChildren()) do
    if obj:IsA("Model")
        and obj:FindFirstChildOfClass("Humanoid")
        and not playerCharNames[obj.Name]
        and obj.Name ~= "Camera" then
        obj:Destroy()
    end
end
print("[Server] Cleared leftover character models from workspace.")

print("[Server] SpawnScript starting — sending reset signal...")
pcall(function()
    HttpService:PostAsync(
        SERVER_URL .. "/api/reset",
        "{}",
        Enum.HttpContentType.ApplicationJson
    )
end)
print("[Server] Reset sent. Starting poll loop.")

-- ── Seed Players ──────────────────────────────────────────
-- Spawn 2 placeholder characters immediately so the floor isn't empty at stream start.
-- Stagger them by 3s so they don't all hit the Roblox API at once.
for i, seedName in ipairs(SEED_USERS) do
    task.delay((i - 1) * 3, function()
        print("[Seed] Auto-spawning " .. seedName)
        spawnCharacter(seedName)
    end)
end

-- ── Featured Rotation Loop ─────────────────────────────────
-- Every 60s, if the viewer queue is empty and the floor has open slots,
-- inject the next featured account so the floor stays populated.
task.spawn(function()
    task.wait(90)  -- give seeds time to load first
    while true do
        task.wait(60)
        local ok, raw = pcall(function()
            return HttpService:GetAsync(SERVER_URL .. "/api/status", true)
        end)
        if ok and raw then
            local parsed, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if parsed and data then
                local queueEmpty  = (data.regularQueueLength + data.vipQueueLength) == 0
                local hasRoom     = data.activeCount < MAX_ON_SCREEN
                if queueEmpty and hasRoom then
                    local name = FEATURED_ROTATION[featuredIndex]
                    featuredIndex = (featuredIndex % #FEATURED_ROTATION) + 1
                    print("[Featured] Cycling in " .. name)
                    task.spawn(spawnCharacter, name)
                end
            end
        end
    end
end)

-- ── Main Poll Loop ─────────────────────────────────────────

print("[Server] SpawnScript running — polling " .. SERVER_URL)

while true do
    task.wait(POLL_INTERVAL)

    -- Wait until the camera has finished tweening to the current character
    -- before loading the next one. CameraScript fires CameraReady when its
    -- tween.Completed fires, so this gate is event-driven, not timer-based.
    -- Safety: auto-open after 10s in case the signal is ever missed.
    local gateTimedOut = (tick() - cameraReadyTime) > 6
    if not cameraIsReady and not gateTimedOut then continue end
    if gateTimedOut and not cameraIsReady then
        warn("[Gate] CameraReady timeout — auto-opening gate")
        cameraIsReady = true
    end

    local ok, raw = pcall(function()
        return HttpService:GetAsync(SERVER_URL .. "/api/queue/next", true)
    end)

    if not ok or not raw then
        warn("[Poll] Cannot reach Node.js server. Is `node server.js` running?")
    else
        local parseOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if parseOk and data then
            -- Tell clients whether the queue is occupied so the camera
            -- knows not to cycle backwards while a new spawn is incoming.
            local hasQueue = (data.status == "spawn" or data.status == "bump")
            queueStatusEvent:FireAllClients(hasQueue)

            if data.status == "spawn" and data.username then
                print("[Poll] Spawning " .. data.username .. " [" .. (data.type or "Regular") .. "]")
                cameraIsReady   = false   -- close gate until camera locks on
                cameraReadyTime = tick()  -- start timeout clock
                task.spawn(spawnCharacter, data.username)

            elseif data.status == "bump" and data.evict and data.username then
                -- Evict the oldest character to make room, then spawn the new one
                print("[Bump] Evicting " .. data.evict .. " → Spawning " .. data.username)
                cameraIsReady   = false
                cameraReadyTime = tick()
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

-- ── Cleanup on Stop ────────────────────────────────────────
-- Fires when the server shuts down (Play → Stop in Studio, or server closes).
-- Destroys all spawned NPC models so they don't persist in the saved file.
game:BindToClose(function()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
            local playerObj = Players:FindFirstChild(obj.Name)
            if not (playerObj and playerObj.Character == obj) then
                pcall(function() obj:Destroy() end)
            end
        end
    end
    print("[Server] Cleaned up all NPC models on shutdown.")
end)
