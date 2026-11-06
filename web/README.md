# Web Deployment Guide (Vite + Netlify)

This directory packages **Medieval Bergen 1360** for the web using **Vite** and hosts it on **Netlify** with automatic Cross-Origin Isolation (`SharedArrayBuffer`).

## Quick Start (Local Development)

```bash
cd web
npm install
npm run dev
```
Open `http://localhost:5173` in your browser.

---

## How to Export from Godot to Web

1. Open the project in **Godot 4.3**.
2. Go to **Project -> Export...**
3. Select the **Web** preset (already configured in `export_presets.cfg`).
4. Click **Export Project...**
5. Save the output to: `web/public/index.html` (this will automatically export `index.html`, `index.js`, `index.wasm`, and `index.pck`).
6. Build with Vite:
   ```bash
   cd web
   npm run build
   ```

---

## One-Click Netlify Deployment

1. Push your repository to **GitHub**.
2. Log into **Netlify** (https://app.netlify.com).
3. Click **"Add new site" -> "Import an existing project" -> "GitHub"**.
4. Select `medieval-bergen`.
5. Netlify will automatically detect [`netlify.toml`](../netlify.toml):
   - **Base directory:** `web`
   - **Publish directory:** `dist`
   - **Build command:** `npm install && npm run build`
   - **Headers:** Automatically configured for `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
6. Click **Deploy Site**!
