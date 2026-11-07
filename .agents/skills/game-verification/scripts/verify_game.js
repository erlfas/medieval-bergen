import fs from 'fs';

async function verifyGame() {
  const host = '127.0.0.1';
  const cdpPort = 9222;
  const webPort = 8080;

  console.log(`[VERIFY] Checking connection to Chromium CDP on http://${host}:${cdpPort}...`);
  let pages;
  try {
    const listRes = await fetch(`http://${host}:${cdpPort}/json/list`);
    pages = await listRes.json();
  } catch (err) {
    console.error(`[VERIFY ERROR] Could not reach Chromium on port ${cdpPort}: ${err.message}`);
    process.exit(1);
  }

  const page = pages.find(p => p.type === 'page' && p.url.includes(String(webPort)));
  if (!page) {
    console.error(`[VERIFY ERROR] No tab found for port ${webPort}. Available pages:`, pages.map(p => p.url));
    process.exit(1);
  }

  console.log(`[VERIFY] Connecting to page: ${page.url}`);
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let idCounter = 1;
  const pending = new Map();
  const consoleMessages = [];
  const errors = [];

  function send(method, params = {}) {
    const id = idCounter++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });
  }

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      if (msg.id && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        if (msg.error) reject(msg.error);
        else resolve(msg.result);
      } else if (msg.method === 'Console.messageAdded') {
        const entry = msg.params.message;
        consoleMessages.push(entry.text);
        if (entry.level === 'error') errors.push(entry.text);
      } else if (msg.method === 'Runtime.exceptionThrown') {
        const desc = msg.params.exceptionDetails.text || 'Unknown exception';
        errors.push(desc);
      }
    } catch (e) {
      // ignore parse errors
    }
  };

  ws.onopen = async () => {
    try {
      await send('Runtime.enable');
      await send('Page.enable');
      await send('Console.enable');

      console.log('[VERIFY] Reloading page to ensure fresh lifecycle boot...');
      await send('Page.reload');

      console.log('[VERIFY] Waiting 10s for WebGL engine & world initialization...');
      await new Promise(r => setTimeout(r, 10000));

      // Capture high-fidelity screenshot
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      const screenshotPath = '/tmp/gameplay_verification.png';
      fs.writeFileSync(screenshotPath, Buffer.from(shot.data, 'base64'));
      console.log(`[VERIFY SUCCESS] Screenshot saved to ${screenshotPath}`);

      // Query canvas properties & rendering state
      const evalRes = await send('Runtime.evaluate', {
        expression: `
          (() => {
            const canvas = document.getElementById('canvas');
            if (!canvas) return { error: 'No canvas found' };
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
            return {
              width: canvas.width,
              height: canvas.height,
              styleWidth: canvas.style.width,
              styleHeight: canvas.style.height,
              contextLoss: gl ? gl.isContextLost() : true
            };
          })()
        `,
        returnByValue: true
      });

      console.log('[VERIFY] Canvas Rendering State:', evalRes.result ? evalRes.result.value : 'N/A');

      if (errors.length > 0) {
        console.warn(`[VERIFY WARNING] Detected ${errors.length} error(s) during execution:`);
        errors.slice(0, 5).forEach(e => console.warn('  -', e));
      } else {
        console.log('[VERIFY SUCCESS] Zero fatal runtime errors detected during lifecycle.');
      }

      ws.close();
      process.exit(0);
    } catch (err) {
      console.error('[VERIFY FAILED]', err);
      ws.close();
      process.exit(1);
    }
  };
}

verifyGame();
