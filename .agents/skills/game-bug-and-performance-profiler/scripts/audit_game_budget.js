import fs from 'fs';

async function auditBudget() {
  const host = '127.0.0.1';
  const cdpPort = 9222;
  const webPort = 8080;

  console.log(`[AUDIT] Connecting to Chromium on port ${cdpPort}...`);
  let pages;
  try {
    const listRes = await fetch(`http://${host}:${cdpPort}/json/list`);
    pages = await listRes.json();
  } catch (err) {
    console.error(`[AUDIT ERROR] Could not reach Chromium on port ${cdpPort}: ${err.message}`);
    process.exit(1);
  }

  const page = pages.find(p => p.type === 'page' && p.url.includes(String(webPort)));
  if (!page) {
    console.error(`[AUDIT ERROR] No tab found for port ${webPort}.`);
    process.exit(1);
  }

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let idCounter = 1;
  const pending = new Map();

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
      }
    } catch (e) {}
  };

  ws.onopen = async () => {
    try {
      await send('Runtime.enable');

      // Sample WebGL parameters & memory metrics
      const auditRes = await send('Runtime.evaluate', {
        expression: `
          (() => {
            const canvas = document.getElementById('canvas');
            if (!canvas) return { error: 'No canvas found' };
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
            if (!gl) return { error: 'WebGL context not available' };

            const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
            const renderer = debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : 'Unknown';
            const vendor = debugInfo ? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL) : 'Unknown';

            return {
              renderer,
              vendor,
              maxTextureSize: gl.getParameter(gl.MAX_TEXTURE_SIZE),
              maxVertexAttribs: gl.getParameter(gl.MAX_VERTEX_ATTRIBS),
              maxFragmentUniformVectors: gl.getParameter(gl.MAX_FRAGMENT_UNIFORM_VECTORS),
              canvasResolution: [canvas.width, canvas.height],
              isContextLost: gl.isContextLost(),
              jsMemory: window.performance && window.performance.memory ? {
                totalJSHeapSizeMB: (window.performance.memory.totalJSHeapSize / 1048576).toFixed(2),
                usedJSHeapSizeMB: (window.performance.memory.usedJSHeapSize / 1048576).toFixed(2),
                jsHeapSizeLimitMB: (window.performance.memory.jsHeapSizeLimit / 1048576).toFixed(2)
              } : 'Performance memory API unavailable'
            };
          })()
        `,
        returnByValue: true
      });

      console.log('=== WEBGL ENVIRONMENT & BUDGET AUDIT ===');
      console.log(JSON.stringify(auditRes.result ? auditRes.result.value : auditRes, null, 2));

      ws.close();
      process.exit(0);
    } catch (err) {
      console.error('[AUDIT FAILED]', err);
      ws.close();
      process.exit(1);
    }
  };
}

auditBudget();
