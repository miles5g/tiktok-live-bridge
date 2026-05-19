// ============================================================
// test_spawn.js  |  Manual spawn tester
// Injects usernames directly into the queue so you can test
// spawning without being live on TikTok.
// ============================================================
// HOW TO RUN:
//   1. Make sure node server.js is running in one terminal
//   2. Open a SECOND terminal in Cursor (click the + icon next
//      to the terminal tab) and run:
//        node test_spawn.js
// ============================================================

const http = require('http');

// ── Usernames to test with ────────────────────────────────
// Add any valid Roblox usernames here.
// "Roblox" and "builderman" are official Roblox accounts
// that always exist, so they're safe for testing.
const TEST_USERS = [
    'Roblox',
    'builderman',
    'milkywizard',   // your own account — spawns your avatar
];

// ── Helper: POST a username into the queue ─────────────────
function injectUser(username) {
    return new Promise((resolve, reject) => {
        const body = JSON.stringify({ username });
        const options = {
            hostname: 'localhost',
            port: 3000,
            path: '/api/test/inject',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(body),
            },
        };

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                console.log(`[Test] Injected "${username}" → ${data.trim()}`);
                resolve();
            });
        });

        req.on('error', (err) => {
            console.error(`[Test] Failed to inject "${username}":`, err.message);
            reject(err);
        });

        req.write(body);
        req.end();
    });
}

// ── Helper: check the live status of the server ───────────
function checkStatus() {
    return new Promise((resolve) => {
        http.get('http://localhost:3000/api/status', (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const status = JSON.parse(data);
                    console.log('\n[Status] Current server state:');
                    console.log(`  On screen:     ${status.activeCount} / ${status.capacity}`);
                    console.log(`  Regular queue: ${status.regularQueueLength}`);
                    console.log(`  VIP queue:     ${status.vipQueueLength}`);
                    console.log(`  Active users:  ${JSON.stringify(status.activeOnScreen)}\n`);
                } catch {
                    console.log('[Status] Raw:', data);
                }
                resolve();
            });
        }).on('error', () => {
            console.error('[Test] Cannot reach server — is node server.js running?');
            resolve();
        });
    });
}

// ── Run the test sequence ──────────────────────────────────
async function runTests() {
    console.log('==============================================');
    console.log('  TikTok Roblox Stream — Manual Spawn Test');
    console.log('==============================================\n');

    await checkStatus();

    console.log(`[Test] Injecting ${TEST_USERS.length} test usernames...\n`);

    for (const user of TEST_USERS) {
        await injectUser(user);
        // Small delay between injections so Roblox has time to process each one
        await new Promise(r => setTimeout(r, 3000));
    }

    console.log('\n[Test] All users injected. Checking status...');
    await new Promise(r => setTimeout(r, 2000));
    await checkStatus();

    console.log('[Test] Watch Roblox Studio — characters should be spawning on the floor!');
    console.log('[Test] They will disappear after 60 seconds automatically.');
}

runTests();
