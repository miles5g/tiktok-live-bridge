const express = require('express');
const { WebcastPushConnection } = require('tiktok-live-connector');

const app = express();
app.use(express.json());

// --- Configuration ---
const TIKTOK_USERNAME = 'milkywizard'; // Your TikTok handle (no @)
const PORT = 3000;
const MAX_ON_SCREEN = 20;

// --- State Memory ---
let regularQueue = [];   // Usernames waiting their turn
let vipQueue = [];       // Gift senders — always go to the front
let activeOnScreen = []; // Usernames currently spawned in Roblox

// --- Helpers ---

// Valid Roblox usernames: 3–20 chars, letters/numbers/underscores only
const isValidRobloxUsername = (username) => {
    const regex = /^[a-zA-Z0-9_]{3,20}$/;
    return regex.test(username);
};

// Block duplicates anywhere in the pipeline
const isUserInSystem = (username) => {
    const lower = username.toLowerCase();
    return (
        regularQueue.some(u => u.toLowerCase() === lower) ||
        vipQueue.some(u => u.toLowerCase() === lower) ||
        activeOnScreen.some(u => u.toLowerCase() === lower)
    );
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

    if (isValidRobloxUsername(text) && !isUserInSystem(text)) {
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
app.get('/api/queue/next', (req, res) => {
    if (activeOnScreen.length >= MAX_ON_SCREEN) {
        return res.json({ status: 'full' });
    }

    // VIPs always go first
    if (vipQueue.length > 0) {
        const next = vipQueue.shift();
        activeOnScreen.push(next);
        console.log(`[Spawn] VIP: ${next} (on screen: ${activeOnScreen.length})`);
        return res.json({ status: 'spawn', username: next, type: 'VIP' });
    }

    if (regularQueue.length > 0) {
        const next = regularQueue.shift();
        activeOnScreen.push(next);
        console.log(`[Spawn] Regular: ${next} (on screen: ${activeOnScreen.length})`);
        return res.json({ status: 'spawn', username: next, type: 'Regular' });
    }

    return res.json({ status: 'empty' });
});

// POST /api/queue/done — Roblox signals a character finished their 60s dance
app.post('/api/queue/done', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'Missing username' });

    activeOnScreen = activeOnScreen.filter(u => u.toLowerCase() !== username.toLowerCase());
    console.log(`[Done] ${username} left the floor. Open slots: ${MAX_ON_SCREEN - activeOnScreen.length}`);

    return res.json({ status: 'success' });
});

// POST /api/test/inject — manually push a username into the queue (testing only)
app.post('/api/test/inject', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'Missing username' });

    if (!isValidRobloxUsername(username)) {
        return res.status(400).json({ error: 'Invalid Roblox username format' });
    }

    if (isUserInSystem(username)) {
        return res.json({ status: 'already_in_system', username });
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
