-- ============================================================
-- AnimateScript  |  StarterPlayerScripts > LocalScript
-- Receives AnimateCharacter events from the server and plays
-- dance animations client-side (avoids serverplaceid=0 error).
-- Cycles through ALL dances — 2 loops per animation before switching.
-- ============================================================
-- WHERE TO PUT THIS:
--   Roblox Studio → Explorer → StarterPlayer → StarterPlayerScripts
--   Right-click → Insert Object → LocalScript → paste this in
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Must match SpawnScript's DANCE_ANIMS list
local DANCE_ANIMS = {
    "507771019",  -- Robot
    "507776043",  -- Dance 2
    "507770453",  -- Breakdance
    "507771955",  -- Shufflin
}

local LOOPS_PER_ANIM = 1   -- how many loops before switching to next dance

local function waitForRemote(name, timeoutSec)
    local deadline = tick() + (timeoutSec or 60)
    while tick() < deadline do
        local ev = ReplicatedStorage:FindFirstChild(name)
        if ev then return ev end
        task.wait(0.25)
    end
    return nil
end

local animateEvent = waitForRemote("AnimateCharacter", 60)

if not animateEvent then
    warn("[AnimateScript] AnimateCharacter not found — paste SpawnScript.lua into ServerScriptService (Script)")
    return
end

animateEvent.OnClientEvent:Connect(function(model, startAnimId)
    if not model or not model.Parent then return end

    task.wait(0.2)

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[AnimateScript] No Humanoid on " .. tostring(model.Name))
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    -- Random starting animation for each character
    local startIdx = math.random(1, #DANCE_ANIMS)

    -- Load and return a track, or nil on failure
    local function loadTrack(id)
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. tostring(id)
        local ok, track = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        if ok and track then
            track.Looped = true
            return track
        end
        return nil
    end

    -- Cycle through all dances forever, 2 loops each, until model is gone
    task.spawn(function()
        local idx = startIdx
        while model and model.Parent do
            local id    = DANCE_ANIMS[idx]
            local track = loadTrack(id)

            if not track then
                -- fallback to Robot if this one fails
                track = loadTrack("507771019")
            end

            if track then
                track:Play(0.3, 1, 0.75)
                print("[AnimateScript] " .. model.Name .. " → " .. id)

                -- Wait for LOOPS_PER_ANIM full loops
                local loops = 0
                local conn = track.DidLoop:Connect(function()
                    loops = loops + 1
                end)

                while loops < LOOPS_PER_ANIM do
                    if not model or not model.Parent then break end
                    task.wait(0.5)
                end

                conn:Disconnect()
                track:Stop(0.4)
                task.wait(0.2)  -- brief gap between dances
            else
                task.wait(3)
            end

            -- Pick a random next animation (different from current)
            local nextIdx = idx
            if #DANCE_ANIMS > 1 then
                while nextIdx == idx do
                    nextIdx = math.random(1, #DANCE_ANIMS)
                end
            end
            idx = nextIdx
        end
    end)
end)

print("[AnimateScript] Ready — 1-loop cycling mode")
