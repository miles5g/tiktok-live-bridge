# TikTok Live → Roblox Dance Floor

> **@milkywizard's autonomous live stream engine.**  
> Viewers type their Roblox username in TikTok chat → their 3D character spawns on a neon dance floor → they dance → the next person loads in. Endless loop. Gift-senders skip the line.

---

## How It Works

```
TikTok Live Chat  →  Node.js Queue  →  ngrok Tunnel  →  Roblox Client  →  TikTok Live Studio
```

1. **Node.js** (`server.js`) listens to your TikTok live chat using `tiktok-live-connector`.
2. Valid Roblox usernames get queued (max 20 on screen, no duplicates on the floor at once).
3. **Roblox** polls the server every 2 seconds via ngrok and spawns the next character.
4. Camera cycles randomly between all on-screen characters (5s each). Front-row characters fade transparent when the camera focuses on back-row ones.
5. After 60 seconds a character expires — unless the camera is currently on them or they're in the most recent 5 (KEEP_RECENT).
6. Gift-senders are bumped to a **VIP priority queue** automatically.

---

## Stack

- **Node.js + Express** — local HTTP server and TikTok chat listener
- **tiktok-live-connector** — reads TikTok live chat & gifts in real-time
- **ngrok** — tunnels localhost:3000 to a public HTTPS URL Roblox can reach
- **Roblox + Luau** — renders 3D avatars, animations, camera, transparency effects
- **VB-Audio Virtual Cable** — routes background music silently to TikTok stream

---

## Project Structure

```
live_roblox/
├── server.js              ← Node.js backend (TikTok listener + REST API)
├── start_stream.ps1       ← ONE-CLICK launcher (run this every stream)
├── SpawnScript.lua        ← Roblox ServerScriptService script
├── CameraScript.lua       ← Roblox StarterPlayerScripts LocalScript
├── AnimateScript.lua      ← Roblox StarterPlayerScripts LocalScript
├── HideHUDScript.lua      ← Roblox StarterPlayerScripts LocalScript
├── HideHostScript.lua     ← Roblox StarterCharacterScripts LocalScript
├── BuildDanceFloor.lua    ← One-time floor builder (run once, then remove)
├── test_spawn.js          ← Manual queue injection for testing
├── package.json
├── MISSION.md             ← Dev rules and architecture reference
└── README.md
```

---

## Key Features

- **Sky-drop spawn** — new characters fall from above onto their tile (smooth Quad ease, 0.6s)
- **Checkerboard fill** — first 10 characters spread across the whole floor before gaps fill in
- **Row-based transparency** — rows closer to camera fade out when camera focuses on a back row
- **Featured rotation** — 30 famous Roblox accounts cycle in every 60s when viewer queue is empty
- **Camera gate** — new characters only spawn after the camera has fully landed on the previous one
- **Fade keeper** — transparency re-applies every 0.3s while camera is settled (bulletproof)
- **VIP queue** — gift senders skip the line automatically

---

## Every-Stream Startup (3 steps)

### 1. Run the launcher script
Right-click `start_stream.ps1` → **Run with PowerShell**

It automatically:
- Kills any leftover node/ngrok processes
- Starts `node server.js`
- Starts ngrok tunnel
- Patches `SpawnScript.lua` with the new ngrok URL
- Prints the status and reminds you to republish

### 2. Republish Roblox
Open **Roblox Studio** → `Ctrl+Shift+Alt+P` (Publish to Roblox)  
Then close Roblox Player and reopen your published game.

### 3. Go live
- Start your music (route through **CABLE Input** so it's silent on your end)
- Open **TikTok Live Studio** → screen capture Roblox → Go Live

---

## First-Time Setup

### Prerequisites
- Node.js v24+
- ngrok installed and authenticated (`ngrok config add-authtoken YOUR_TOKEN`)
- VB-Audio Virtual Cable installed (for silent music routing)
- Roblox Studio with **Allow HTTP Requests** enabled (File → Game Settings → Security)
- TikTok account with Live access

### Install dependencies
```bash
npm install
```

### Roblox Script Placement
| Script | Location |
|---|---|
| `SpawnScript.lua` | ServerScriptService → Script |
| `CameraScript.lua` | StarterPlayer → StarterPlayerScripts → LocalScript |
| `AnimateScript.lua` | StarterPlayer → StarterPlayerScripts → LocalScript |
| `HideHUDScript.lua` | StarterPlayer → StarterPlayerScripts → LocalScript |
| `HideHostScript.lua` | StarterPlayer → StarterCharacterScripts → LocalScript |

### TikTok Authentication
Add your session cookies to `server.js` (never committed to git):
```js
const TIKTOK_SESSION_ID = 'your_sessionid_cookie';
const TIKTOK_TARGET_IDC = 'your_tt-target-idc_cookie'; // e.g. useast5
```
Get these from Chrome → F12 → Application → Cookies → tiktok.com

---

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/api/queue/next` | GET | Next username to spawn + heartbeat |
| `/api/queue/done` | POST | Mark user as done, free their slot |
| `/api/reset` | POST | Clear stale session on Roblox startup |
| `/api/test/inject` | POST | Manually inject a username for testing |
| `/api/status` | GET | Live dashboard — queues, active users |

---

## Monetization

- **Regular viewers** type their username → join the queue
- **Gift senders** → automatically skip to the front (VIP queue)
- The more gifts = the faster you appear on stream

---

## Anti-Ban / Stability

- Camera always moves (never a static screen) — TikTok won't flag it as inactive
- `builderman` + `Roblox` auto-spawn at startup so the floor is never empty
- Heartbeat monitor: if Roblox stops polling for 15s, server clears active list automatically
- `game:BindToClose()` destroys all NPC models on server shutdown
- Set Windows **Power Settings → Never Sleep** for unattended streams
- Install **Chrome Remote Desktop** or **AnyDesk** to monitor from your phone

---

## Music (Silent to You, Audible on Stream)

1. Play royalty-free music in Chrome (Lofi Girl stream-safe, Pretzel, etc.)
2. In Windows Volume Mixer → set Chrome output to **CABLE Input**
3. In TikTok Studio → set audio input to **CABLE Output**
4. Music goes to stream only — nothing plays through your speakers

---

## License

MIT — do whatever you want with it.
