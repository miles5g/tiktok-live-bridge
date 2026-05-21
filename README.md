# TikTok Live Bridge

> **Autonomous live-stream engine:** viewers type a Roblox username in TikTok chat → their avatar spawns on a neon dance floor → camera cycles → gift-senders skip the queue.

**Portfolio angle:** Real-time event ingestion, queueing, VIP prioritization, cross-platform HTTP bridge (Node ↔ Roblox), and one-click ops scripts for repeatable live sessions.

---

## How it works

```
TikTok Live Chat  →  Node.js Queue  →  ngrok Tunnel  →  Roblox Client  →  TikTok Live Studio
```

1. **Node.js** (`server.js`) listens to TikTok live chat via `tiktok-live-connector`.
2. Valid Roblox usernames enter a queue (max 20 on screen, no duplicate floor slots).
3. **Roblox** polls the server every 2s over ngrok and spawns the next character.
4. Camera cycles across characters (5s each); front-row fades when focusing on back row.
5. Characters expire after 60s unless featured or in the “keep recent” set.
6. Gift-senders join a **VIP priority queue** automatically.

---

## Stack

- **Node.js + Express** — HTTP API and TikTok listener
- **tiktok-live-connector** — live chat and gifts
- **ngrok** — public HTTPS tunnel to localhost
- **Roblox / Luau** — avatars, animations, camera, transparency
- **VB-Audio Virtual Cable** — silent music routing into TikTok Studio

---

## Project structure

```
live_roblox/
├── server.js              # TikTok listener + REST API
├── start_stream.ps1       # One-click launcher
├── SpawnScript.lua        # ServerScriptService
├── CameraScript.lua       # StarterPlayerScripts
├── AnimateScript.lua
├── HideHUDScript.lua
├── HideHostScript.lua
├── BuildDanceFloor.lua    # One-time floor setup
├── test_spawn.js          # Manual queue injection
└── MISSION.md             # Architecture notes
```

---

## Key features

- Sky-drop spawn with checkerboard floor fill
- Row-based transparency tied to camera focus
- Featured rotation when the viewer queue is empty
- Camera gate so spawns wait for settle
- VIP queue for gift senders
- Heartbeat monitor if Roblox stops polling

---

## Every-stream startup

### 1. Run the launcher

Right-click `start_stream.ps1` → **Run with PowerShell**

### 2. Republish Roblox

Roblox Studio → **Publish to Roblox** → reopen the published experience.

### 3. Go live

Route music through **CABLE Input**; capture Roblox in TikTok Live Studio.

---

## First-time setup

**Prerequisites:** Node.js 24+, ngrok (authenticated), VB-Audio Virtual Cable, Roblox Studio with **Allow HTTP Requests**, TikTok Live access.

```bash
npm install
```

| Script | Roblox location |
|--------|-----------------|
| `SpawnScript.lua` | ServerScriptService |
| `CameraScript.lua` | StarterPlayerScripts |
| `AnimateScript.lua` | StarterPlayerScripts |
| `HideHUDScript.lua` | StarterPlayerScripts |
| `HideHostScript.lua` | StarterCharacterScripts |

TikTok session cookies go in `server.js` (never commit — use env or local overrides).

---

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/queue/next` | GET | Next username + heartbeat |
| `/api/queue/done` | POST | Mark spawn complete |
| `/api/reset` | POST | Clear session on startup |
| `/api/test/inject` | POST | Inject username for testing |
| `/api/status` | GET | Queue dashboard |

---

## Stability notes

- Keep camera moving to avoid inactive-stream flags
- Power settings: never sleep during unattended streams
- Music via virtual cable can stall on focus changes — see README section in repo for VB-Audio troubleshooting

---

## License

MIT
