-- ============================================================
-- BuildDanceFloor.lua  |  ONE-TIME SETUP SCRIPT
-- ============================================================
-- HOW TO RUN:
--   Roblox Studio → View (top menu) → Command Bar
--   Copy-paste this ENTIRE script into the Command Bar → Enter
--   The full neon dance floor will be built instantly.
--   Run it again at any time to tear down and rebuild cleanly.
-- ============================================================

local Lighting  = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- ── Tear down any existing build ──────────────────────────
local old = Workspace:FindFirstChild("DanceFloor")
if old then old:Destroy() end
local oldAtmo = Workspace.Terrain:FindFirstChildOfClass("Atmosphere")
if oldAtmo then oldAtmo:Destroy() end

local folder = Instance.new("Folder")
folder.Name   = "DanceFloor"
folder.Parent = Workspace

-- ── Color palette ─────────────────────────────────────────
local C_FLOOR  = Color3.fromRGB(12,  10,  22)   -- near-black base
local C_CYAN   = Color3.fromRGB(0,   230, 255)  -- neon cyan
local C_PINK   = Color3.fromRGB(255, 0,   160)  -- hot pink
local C_PURPLE = Color3.fromRGB(140, 0,   255)  -- neon purple
local C_WHITE  = Color3.fromRGB(255, 255, 255)
local C_DARK_A = Color3.fromRGB(20,  10,  45)   -- dark purple tile
local C_DARK_B = Color3.fromRGB(10,  20,  45)   -- dark blue tile
local C_METAL  = Color3.fromRGB(35,  35,  40)

-- ── Layout constants ──────────────────────────────────────
--
-- Grid: 5 columns × 4 rows, 5-stud spacing (matches SpawnScript)
--   X: -10  -5   0  +5  +10
--   Z:   0   5  10   15
--
-- Floor top surface sits at Y = 2.
-- SpawnLocation anchor at (0, 2.1, 0).
-- Characters' HumanoidRootPart will be placed at Y = 5.1
--   (3 studs above anchor = feet land right on the floor).
--
local FLOOR_TOP = 2    -- world Y of the floor surface
local FX, FZ    = 0, 7.5  -- floor plate center (Z centered over the grid)

-- ── Part helpers ──────────────────────────────────────────
local function part(size, pos, color, mat, trans, collide)
    local p = Instance.new("Part")
    p.Size         = size
    p.Position     = pos
    p.Color        = color
    p.Material     = mat or Enum.Material.SmoothPlastic
    p.Transparency = trans   or 0
    p.CanCollide   = (collide == nil) and true or collide
    p.Anchored     = true
    p.CastShadow   = false
    p.Parent       = folder
    return p
end

local function neon(size, pos, color, trans)
    return part(size, pos, color, Enum.Material.Neon, trans or 0, false)
end

local function spotlight(parent, color, brightness, range, angle)
    local s = Instance.new("SpotLight")
    s.Color      = color
    s.Brightness = brightness
    s.Range      = range
    s.Angle      = angle
    s.Face       = Enum.NormalId.Bottom
    s.Parent     = parent
end

local function pointlight(parent, color, brightness, range)
    local l = Instance.new("PointLight")
    l.Color      = color
    l.Brightness = brightness
    l.Range      = range
    l.Parent     = parent
end

-- ── 1. Floor slab ─────────────────────────────────────────
local floor = part(
    Vector3.new(32, 2, 28),
    Vector3.new(FX, FLOOR_TOP - 1, FZ),
    C_FLOOR
)
floor.Name = "FloorSlab"

-- ── 2. Neon perimeter border ──────────────────────────────
local B = 0.25  -- border thickness
-- Front / back
neon(Vector3.new(32, B, B), Vector3.new(FX, FLOOR_TOP, FZ + 14), C_CYAN)
neon(Vector3.new(32, B, B), Vector3.new(FX, FLOOR_TOP, FZ - 14), C_CYAN)
-- Left / right
neon(Vector3.new(B, B, 28), Vector3.new(FX - 16, FLOOR_TOP, FZ), C_CYAN)
neon(Vector3.new(B, B, 28), Vector3.new(FX + 16, FLOOR_TOP, FZ), C_CYAN)

-- ── 3. Dance grid tiles (5 col × 4 row) ───────────────────
local TILE = 4.7   -- tile size (slightly < 5 to leave gap for grid lines)
local TH   = 0.12
for row = 0, 3 do
    for col = 0, 4 do
        local tx = (col - 2) * 5
        local tz = row * 5
        local color = ((row + col) % 2 == 0) and C_DARK_A or C_DARK_B
        local t = part(
            Vector3.new(TILE, TH, TILE),
            Vector3.new(tx, FLOOR_TOP + TH / 2, tz),
            color, nil, 0, false
        )
        t.Name = string.format("Tile_%d_%d", row, col)
    end
end

-- ── 4. Neon grid lines ────────────────────────────────────
local LW, LH = 0.14, 0.08
-- Column dividers (run along Z axis, between X columns)
for col = 0, 5 do
    local lx = (col - 2) * 5 - 2.5
    neon(Vector3.new(LW, LH, 20), Vector3.new(lx, FLOOR_TOP + LH / 2, 7.5), C_PINK)
end
-- Row dividers (run along X axis, between Z rows)
for row = 0, 4 do
    local lz = row * 5 - 2.5
    neon(Vector3.new(25, LH, LW), Vector3.new(0, FLOOR_TOP + LH / 2, lz), C_PINK)
end

-- ── 5. SpawnLocation anchor ───────────────────────────────
-- Named exactly "SpawnLocation" — SpawnScript looks for this.
-- Placed at the back of the grid (row 0).
-- Y = FLOOR_TOP + 0.1 → spawn math puts HumanoidRootPart at Y≈5 (on the floor).
local spawnLoc = part(
    Vector3.new(4, 0.2, 4),
    Vector3.new(0, FLOOR_TOP + 0.1, 0),
    C_CYAN, Enum.Material.Neon, 0.75, false
)
spawnLoc.Name = "SpawnLocation"
-- Subtle pulse indicator so you can find it in Studio
local si = Instance.new("SelectionBox")
si.Adornee = spawnLoc
si.Color3   = C_CYAN
si.LineThickness = 0.04
si.Parent   = spawnLoc

-- ── 6. Corner light poles ─────────────────────────────────
local POLE_H = 22
local POLE_Y = FLOOR_TOP + POLE_H / 2

local poles = {
    { pos = Vector3.new(-15, POLE_Y, -5), pColor = C_CYAN,   lColor = C_WHITE },
    { pos = Vector3.new( 15, POLE_Y, -5), pColor = C_PINK,   lColor = Color3.fromRGB(255, 200, 255) },
    { pos = Vector3.new(-15, POLE_Y, 20), pColor = C_PURPLE, lColor = Color3.fromRGB(200, 200, 255) },
    { pos = Vector3.new( 15, POLE_Y, 20), pColor = C_CYAN,   lColor = C_WHITE },
}

for i, pd in ipairs(poles) do
    local pole = neon(Vector3.new(0.5, POLE_H, 0.5), pd.pos, pd.pColor)
    pole.Name = "Pole_" .. i

    -- Light head cap at top of pole
    local cap = neon(
        Vector3.new(1.4, 1, 1.4),
        pd.pos + Vector3.new(0, POLE_H / 2, 0),
        pd.pColor
    )
    cap.Name = "PoleHead_" .. i
    spotlight(cap, pd.lColor, 5, 65, 45)
end

-- ── 7. Overhead truss lighting rig ────────────────────────
local trussY = FLOOR_TOP + 20
local truss = part(
    Vector3.new(24, 0.5, 0.5),
    Vector3.new(FX, trussY, FZ),
    C_METAL, Enum.Material.Metal
)
truss.Name = "Truss"

local trussHeads = {
    { x = -9,  color = C_PINK   },
    { x = -4,  color = C_WHITE  },
    { x =  0,  color = C_CYAN   },
    { x =  4,  color = C_WHITE  },
    { x =  9,  color = C_PURPLE },
}
for _, th in ipairs(trussHeads) do
    local head = neon(
        Vector3.new(1, 1.2, 1),
        Vector3.new(th.x, trussY - 0.85, FZ),
        th.color
    )
    head.Name = "TrussHead"
    spotlight(head, th.color, 4, 55, 38)
end

-- Support wires from truss to poles (thin dark rods)
local wireData = {
    { x = -15, pz = -5  },
    { x =  15, pz = -5  },
    { x = -15, pz = 20  },
    { x =  15, pz = 20  },
}
for _, wd in ipairs(wireData) do
    local wireStart = Vector3.new(wd.x, FLOOR_TOP + POLE_H, wd.pz)
    local wireEnd   = Vector3.new(
        (wd.x < 0) and -12 or 12,
        trussY,
        FZ
    )
    local mid = (wireStart + wireEnd) / 2
    local len = (wireEnd - wireStart).Magnitude
    local wire = part(
        Vector3.new(0.1, len, 0.1),
        mid,
        C_METAL, Enum.Material.Metal, 0, false
    )
    wire.CFrame = CFrame.lookAt(mid, wireEnd) * CFrame.Angles(math.pi/2, 0, 0)
    wire.Name   = "Wire"
end

-- ── 8. Floating ambient orbs (fill lighting) ──────────────
local orbs = {
    { pos = Vector3.new(-9, FLOOR_TOP + 9, 3),  color = C_PURPLE, br = 2.5, r = 28 },
    { pos = Vector3.new( 9, FLOOR_TOP + 9, 12), color = C_PINK,   br = 2.5, r = 28 },
    { pos = Vector3.new( 0, FLOOR_TOP + 12, 7), color = C_CYAN,   br = 3,   r = 35 },
    { pos = Vector3.new(-8, FLOOR_TOP + 7, 13), color = C_CYAN,   br = 2,   r = 22 },
    { pos = Vector3.new( 8, FLOOR_TOP + 7, 2),  color = C_PURPLE, br = 2,   r = 22 },
}
for _, od in ipairs(orbs) do
    local orb = neon(Vector3.new(0.7, 0.7, 0.7), od.pos, od.color)
    orb.Shape = Enum.PartType.Ball
    orb.Name  = "AmbientOrb"
    pointlight(orb, od.color, od.br, od.r)
end

-- ── 9. Backdrop wall ──────────────────────────────────────
-- A dark rear wall behind the grid so the stream never shows
-- the Roblox skybox through the back of the stage.
local wall = part(
    Vector3.new(32, 26, 1),
    Vector3.new(FX, FLOOR_TOP + 12, -6),
    C_FLOOR
)
wall.Name = "BackdropWall"

-- Neon "JOIN THE FLOOR" sign strips on the wall
local signStrips = {
    { sz = Vector3.new(18, 0.3, 0.3), y = FLOOR_TOP + 22, color = C_CYAN  },
    { sz = Vector3.new(14, 0.3, 0.3), y = FLOOR_TOP + 21, color = C_PINK  },
    { sz = Vector3.new(10, 0.3, 0.3), y = FLOOR_TOP + 20, color = C_CYAN  },
}
for _, ss in ipairs(signStrips) do
    neon(ss.sz, Vector3.new(FX, ss.y, -5.4), ss.color)
end

-- Side wall accent strips
for i = 0, 3 do
    local stripZ = i * 5
    neon(
        Vector3.new(0.2, 18, 0.2),
        Vector3.new(-16, FLOOR_TOP + 9, stripZ),
        (i % 2 == 0) and C_CYAN or C_PURPLE
    )
    neon(
        Vector3.new(0.2, 18, 0.2),
        Vector3.new(16, FLOOR_TOP + 9, stripZ),
        (i % 2 == 0) and C_PINK or C_CYAN
    )
end

-- ── 10. Lighting & Atmosphere ─────────────────────────────
Lighting.Ambient        = Color3.fromRGB(8,  4,  20)
Lighting.OutdoorAmbient = Color3.fromRGB(4,  0,  12)
Lighting.Brightness     = 0
Lighting.ClockTime      = 0   -- midnight
Lighting.FogEnd         = 500
Lighting.FogColor       = Color3.fromRGB(5, 0, 15)

-- Bloom for the neon glow effect
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
    or Instance.new("BloomEffect")
bloom.Intensity   = 0.35  -- reduced: prevents blowout on bright avatars
bloom.Size        = 14
bloom.Threshold   = 0.98  -- higher = harder to trigger, less overexposure
bloom.Name        = "NeonBloom"
bloom.Parent      = Lighting

-- Color correction for the cinematic dark feel
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    or Instance.new("ColorCorrectionEffect")
cc.Brightness  = -0.04
cc.Contrast    = 0.12
cc.Saturation  = 0.15
cc.TintColor   = Color3.fromRGB(210, 210, 255)
cc.Name        = "CinematicGrade"
cc.Parent      = Lighting

-- Atmosphere (dark void feel)
local atmo = Instance.new("Atmosphere")
atmo.Density  = 0.25
atmo.Haze     = 0
atmo.Glare    = 0.4
atmo.Color    = Color3.fromRGB(8, 4, 20)
atmo.Decay    = Color3.fromRGB(4, 0, 12)
atmo.Parent   = Workspace.Terrain

-- ── Done ──────────────────────────────────────────────────
print("╔══════════════════════════════════════╗")
print("║   Dance floor built successfully!   ║")
print("╠══════════════════════════════════════╣")
print("║  SpawnLocation is at (0, 2.1, 0)    ║")
print("║  Grid: 5 cols × 4 rows, 5-stud gap  ║")
print("║  Next: paste SpawnScript.lua into   ║")
print("║  ServerScriptService → Script       ║")
print("╚══════════════════════════════════════╝")
