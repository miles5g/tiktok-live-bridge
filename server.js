const express = require('express');
const { WebcastPushConnection } = require('tiktok-live-connector');

const app = express();
app.use(express.json());

// --- Configuration ---
const TIKTOK_USERNAME = 'milkywizard'; // Your TikTok handle (no @)
const PORT = 3000;
const MAX_ON_SCREEN = 12;  // Safe for Studio 60 FPS. Raise to 20 when streaming Roblox client.

// --- State Memory ---
let regularQueue = [];   // Usernames waiting their turn
let vipQueue = [];       // Gift senders — always go to the front
let activeOnScreen = []; // Usernames currently spawned in Roblox
let lastHeartbeat = Date.now(); // Tracks when Roblox last checked in

// If Roblox Studio stops or crashes, clear activeOnScreen after 15 seconds
// so the floor doesn't stay permanently "full"
setInterval(() => {
    const secondsSinceHeartbeat = (Date.now() - lastHeartbeat) / 1000;
    if (secondsSinceHeartbeat > 15 && activeOnScreen.length > 0) {
        console.warn(`[Heartbeat] No contact from Roblox for ${Math.round(secondsSinceHeartbeat)}s — clearing active list.`);
        activeOnScreen = [];
    }
}, 5000);

// --- Helpers ---

// Valid Roblox usernames: 3–20 chars, letters/numbers/underscores only
const isValidRobloxUsername = (username) => {
    const regex = /^[a-zA-Z0-9_]{3,20}$/;
    return regex.test(username);
};

// Only block if the user is currently visible on the dance floor.
// Queue duplicates are allowed — same person can queue multiple times
// and will get another turn once their current spawn finishes.
const isAlreadyOnScreen = (username) => {
    const lower = username.toLowerCase();
    return activeOnScreen.some(u => u.toLowerCase() === lower);
};

// --- TikTok Connection ---
let tiktokConnection = new WebcastPushConnection(TIKTOK_USERNAME);

function connectToTikTok() {
    console.log(`[TikTok] Connecting to @${TIKTOK_USERNAME}...`);

    tiktokConnection.connect()
        .then(state => {
            console.log(`[TikTok] Connected! Room ID: ${state.roomId}`);
        })
        .catch(err => {
            console.error('[TikTok] Connection failed. Retrying in 10 seconds...', err.message);
            setTimeout(connectToTikTok, 10000);
        });
}

// --- TikTok Event Listeners ---

// Chat message → try to add as regular queue entry
tiktokConnection.on('chat', (data) => {
    const text = data.comment.trim();

    if (isValidRobloxUsername(text) && !isAlreadyOnScreen(text)) {
        regularQueue.push(text);
        console.log(`[Queue] +${text} (queue: ${regularQueue.length})`);
    }
});

// Gift received → bump sender to VIP queue
tiktokConnection.on('gift', (data) => {
    const username = data.uniqueId;
    console.log(`[Gift] ${username} sent gift ID: ${data.giftId}`);

    if (isValidRobloxUsername(username)) {
        // Pull out of regular queue if they were already waiting
        regularQueue = regularQueue.filter(u => u.toLowerCase() !== username.toLowerCase());

        // Add to VIP if not currently on the floor
        if (!activeOnScreen.some(u => u.toLowerCase() === username.toLowerCase())) {
            vipQueue.push(username);
            console.log(`[VIP] ${username} upgraded to priority queue!`);
        }
    }
});

// Auto-reconnect on disconnect
tiktokConnection.on('disconnected', () => {
    console.warn('[TikTok] Disconnected. Auto-reconnecting in 5 seconds...');
    setTimeout(connectToTikTok, 5000);
});

tiktokConnection.on('error', (err) => {
    console.error('[TikTok] Stream error:', err.message);
});

// --- REST Endpoints for Roblox ---

// GET /api/queue/next — Roblox asks "who do I spawn next?"
// Also serves as the heartbeat — every poll resets the timer.
//
// Responses:
//   { status: 'spawn', username, type }        — floor has room, spawn normally
//   { status: 'bump',  evict, username, type } — floor full, evict oldest first
//   { status: 'empty' }                        — nothing queued right now
app.get('/api/queue/next', (req, res) => {
    lastHeartbeat = Date.now();

    // Find next eligible person (VIP first, then regular)
    let nextUser = null;
    let nextType = null;

    while (vipQueue.length > 0) {
        const candidate = vipQueue.shift();
        if (!isAlreadyOnScreen(candidate)) { nextUser = candidate; nextType = 'VIP'; break; }
    }
    if (!nextUser) {
        while (regularQueue.length > 0) {
            const candidate = regularQueue.shift();
            if (!isAlreadyOnScreen(candidate)) { nextUser = candidate; nextType = 'Regular'; break; }
        }
    }

    if (!nextUser) return res.json({ status: 'empty' });

    // Floor has room — spawn normally
    if (activeOnScreen.length < MAX_ON_SCREEN) {
        activeOnScreen.push(nextUser);
        console.log(`[Spawn] ${nextType}: ${nextUser} (${activeOnScreen.length}/${MAX_ON_SCREEN})`);
        return res.json({ status: 'spawn', username: nextUser, type: nextType });
    }

    // Floor is full — bump oldest to make room for next person
    const evict = activeOnScreen.shift();
    activeOnScreen.push(nextUser);
    console.log(`[Bump] Evicting ${evict} → Spawning ${nextUser} [${nextType}] (${activeOnScreen.length}/${MAX_ON_SCREEN})`);
    return res.json({ status: 'bump', evict, username: nextUser, type: nextType });
});

// POST /api/queue/done — Roblox signals a character finished their 60s dance
app.post('/api/queue/done', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'Missing username' });

    activeOnScreen = activeOnScreen.filter(u => u.toLowerCase() !== username.toLowerCase());
    console.log(`[Done] ${username} left the floor. Open slots: ${MAX_ON_SCREEN - activeOnScreen.length}`);

    return res.json({ status: 'success' });
});

// POST /api/reset — called by SpawnScript on startup to wipe stale session state
app.post('/api/reset', (req, res) => {
    const prev = activeOnScreen.length;
    activeOnScreen = [];
    console.log(`[Reset] Roblox session started — cleared ${prev} stale active user(s).`);
    return res.json({ status: 'ok' });
});

// POST /api/test/inject — manually push a username into the queue (testing only)
app.post('/api/test/inject', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'Missing username' });

    if (!isValidRobloxUsername(username)) {
        return res.status(400).json({ error: 'Invalid Roblox username format' });
    }

    if (isAlreadyOnScreen(username)) {
        return res.json({ status: 'already_on_screen', username });
    }

    regularQueue.push(username);
    console.log(`[Test] Manually injected: ${username} (queue: ${regularQueue.length})`);
    return res.json({ status: 'injected', username });
});

// GET /api/status — quick health check you can open in a browser
app.get('/api/status', (req, res) => {
    res.json({
        activeOnScreen,
        activeCount: activeOnScreen.length,
        regularQueueLength: regularQueue.length,
        vipQueueLength: vipQueue.length,
        capacity: MAX_ON_SCREEN,
    });
});

// --- Start ---
app.listen(PORT, () => {
    console.log(`[Server] Running at http://localhost:${PORT}`);
    console.log(`[Server] Health check: http://localhost:${PORT}/api/status`);
    connectToTikTok();
});
