# Medieval Bergen 1360 — Key Technical Findings & Architecture

This document summarizes the core technical findings, architectural patterns, and solutions established while developing **Medieval Bergen 1360**, a medieval Norwegian settler survival and building simulation built in Godot 4.3 and deployed to the web via Vite + WebAssembly.

---

## 1. Project Overview & Design Philosophy

- **Historical Setting:** Bergen, Norway, March 1, 1360.
- **Engine & Target:** Godot 4.3 (GL Compatibility / WebGL 2.0), Vite web wrapper, WebAssembly, deployed to Netlify.
- **Pure Procedural Foundation (No Blender Initially):**
  - All 3D assets (settler model, backpack, wildlife, trees, livestock, tools, farmsteads, and modular log cabins) are generated procedurally in GDScript using geometric primitives (`BoxMesh`, `CylinderMesh`, `CapsuleMesh`, `PlaneMesh`) and standard materials.
  - Every procedural asset has clear pivot points, naming conventions, and transform hierarchies, serving as drop-in replacement sockets for custom 3D models imported later.

---

## 2. Procedural Topography & Collision Engineering

### Terrain Geometry & Triangle Winding Order
In Godot 4 3D, triangle face normals and culling are governed by clockwise (CW) front-face winding when looking down from above (+Y towards -Y) in the right-handed coordinate system (+X East, +Z South, -Z North):
- **Root Cause of Invisible Ground:**
  - A Counter-Clockwise (CCW) vertex ordering on screen (`v0 -> v2 -> v1` and `v1 -> v2 -> v3`) treated upward surfaces as backfaces in Godot 3D.
  - When the terrain used `render_mode cull_back`, the entire top surface of the terrain mesh was culled (invisible), causing the settler to appear to stand directly on the sea water plane, while distant mountains displayed inverted underside geometry.
- **Solution (Clockwise Front-Facing Winding):**
  - Standardized on front-facing Clockwise (CW) winding order for every quad on the X-Z grid:
    - **Triangle 1:** `(v0 -> v1 -> v2)`
    - **Triangle 2:** `(v1 -> v3 -> v2)`
  - True upward normal cross product:
    `var normal := tangent_z.cross(tangent_x).normalized()`
    Because $Z \times X = +Y$, this yields a natural $+Y$ normal pointing upward along the terrain gradient $(-dy/dx, 1, -dy/dz)$, ensuring accurate slope lighting and preventing self-shadow artifacts.
  - **Tangent Generation:** Added `st.generate_tangents()` before committing the mesh with `SurfaceTool`. This supplies valid tangent and binormal vectors required for PBR normal mapping.

### Collision Hardening & Floor Safety Clamping
- **Trimesh Backface Collision:** Enabled `trimesh.backface_collision = true` on `ConcavePolygonShape3D` so collision detection prevents tunneling even under steep falls or physics lag spikes.
- **Surface Clamping:** In `settler_controller.gd`:
  - Dynamically snaps vertical spawn position in `_ready()` to `sample_height(x, z) + 0.1`.
  - In `_physics_process()`, if `global_position.y < ground_y`, clamps position and resets downward velocity (`velocity.y = maxf(0.0, velocity.y)`).

### Atmospheric Shading & Normal Map Calibration
- **The Problem:** 2048x2048m terrain with steep 60°–80° mountain crags caused texture stretching, while assigning PBR normal maps without mesh tangents produced blown-out, speckled white specular noise across Mount Fløyen.
- **The Solution:** Custom GL Compatibility shader (`shaders/bergen_terrain.gdshader`):
  - **Slope-Based Triplanar Rock:** Mountain cliffs (> 40° slope) project triplanar world-space rock textures, eliminating vertical stretching on Mount Fløyen & Sandviksfjellet.
  - **Dual-Octave Rotated Grass Sampling:** Blends meadow grass at two different rotation angles and scales to break up repetitive tiling in the valley.
  - **Elevation & Slope Biomes:** Smoothly transitions between fjord shoreline pebbles, lush meadow grass, scree talus slopes, steep granite cliffs, and high fell summits.
  - **Calibrated PBR Depth:** Calibrated `NORMAL_MAP_DEPTH` to `0.75` with generated tangents to render fine 3D micro-relief on grass turf and rock crags without specular noise or shading artifacts.

---

## 3. WebAssembly Export & Static Web Hosting (Netlify / Vite)

### Critical Cross-Origin Isolation (COOP / COEP)
Godot 4 Web exports utilize multi-threading and web audio worklets that depend on `SharedArrayBuffer`. Browsers strictly block `SharedArrayBuffer` unless cross-origin isolation headers are present.
- **Solution (`netlify.toml`):**
  ```toml
  [[headers]]
    for = "/*"
    [headers.values]
      Cross-Origin-Opener-Policy = "same-origin"
      Cross-Origin-Embedder-Policy = "require-corp"
      Access-Control-Allow-Origin = "*"
      X-Content-Type-Options = "nosniff"
  ```
- **Vite Configuration (`web/vite.config.js`):**
  - Set `assetsInlineLimit: 0` to prevent Vite from base64-encoding large `.wasm` (34MB) and `.pck` (44MB) binaries.
  - Configured dev server with matching COOP/COEP headers for local testing.

### Headless CLI Export Pipeline
- Headless command:
  ```bash
  godot --headless --export-release "Web" web/public/index.html
  ```
- Headless dummy renderer note: Godot headless outputs `ERROR: Parameter "m" is null at: mesh_get_surface_count`. This is expected in headless mode due to the dummy rendering server and has zero effect on runtime WebGL execution.

---

## 4. Locomotion, Swimming, & Mountain Climbing

### Decoupled WASD Turning & Camera Orbit
- The mouse look orbits freely around the settler pivot (`head` height 1.45m) at all times without fighting player input or snapping back.
- WASD input steers the character body to face the intended direction of travel relative to the camera gaze:
  - `W`: Runs forward away from camera.
  - `S`: Turns 180° around and runs toward camera.
  - `A` / `D`: Turns 90° left or right.

### Water Swimming Physics
- Automatically detects water entry (`global_position.y <= sea_level + 0.2`).
- Buoyant upward force counters gravity at the water surface with gentle sinusoidal wave bobbing.
- Water drag cushions momentum, and `box_man_model.gd` switches to a prone front-crawl paddle stroke with flutter kicks when swimming, transitioning to treading water when stationary.

### Mountain Climbing (Freeform Hands + Deployable Rope)
- **Hand Climbing:** Approaching rock walls (> 50° slope) allows the settler to scale cliff faces in 2D (`W`/`S` up/down, `A`/`D` lateral traverse) using handholds, consuming stamina.
- **Climbing Rope Tool (`climbing_rope.gd`):** Pressing `[T]` anchors a braided hemp rope with iron pitons on cliff edges. The settler can grab the rope with `[E]` to climb up or rappel down steep mountains safely without stamina fatigue, and retrieve it with `[R]`.

---

## 5. Tree Chopping, Fall Prediction, & Physical Timber

### 10-Chop System & Visual Progress Tracker
- Trees require exactly 10 axe strikes (`chop_hits_required = 10`).
- Looking at or striking a tree activates a 3D billboarded progress tracker (`[Chops: X/10]`) with a dynamic fill bar and a physical cut notch in the trunk that deepens with each blow.

### Real-Time Fall Direction & Landing Target
- Dynamically computes fall direction away from the settler's strike angle.
- Displays:
  1. A segmented ground corridor arrow pointing in the fall vector.
  2. A parabolic 3D trajectory arc tracing the path from treetop to ground impact.
  3. A ground hazard ring with crosshairs marking the predicted impact zone.
- On the 10th chop: Disables trunk collision, executes realistic rotational topple physics ($\tau = M g \frac{L}{2} \sin\theta$), leaves a cut stump, and spawns physical `CarryableLog` instances along the fall line.

---

## 6. Physical Log Carrying & Dropping Anywhere

- **Log Interaction:** Walk up to any felled log and press `[E]` to hoist it.
- **Holding Pose:** `box_man_model.gd` mounts a horizontal timber log across the settler's chest with both arms wrapping forward and inward around it. Limbs bob naturally with walking inertia.
- **Drop Anywhere:** Pressing `[E]` or `[G]` drops the log back onto the ground in front of the settler.
- **Direct Construction Integration:** Holding a log in your arms and opening Build Mode (`[B]`) automatically consumes the carried log directly into the building foundation (-1 timber log cost).

---

## 7. Equipment Hotbar & Ballistic Archery

### Hotbar Slots (`[1]`–`[5]`)
Managed by `scripts/player/equipment_manager.gd`:
- `[1]` **Woodcutter's Axe:** Tree chopping and heavy melee strikes.
- `[2]` **Drinking Horn / Bottle:** Restores thirst on the go from the backpack reservoir (1.5L capacity; refillable at freshwater streams).
- `[3]` **Hunting Knife:** Fast agile slashes for close-quarters wolf defense and game harvesting.
- `[4]` **Bow & Arrow:** Hold Left-Click to draw recurve bow (charging tension with dynamic camera zoom); release to fire.
- `[5]` **Pine-Tar Torch:** Warmth, illumination, and wolf deterrence.

### Ballistic Arrow Physics (`arrow_projectile.gd`)
- Realistic physics simulation with parabolic gravity arc, velocity-aligned rotation, continuous raycast detection (preventing tunneling through fast-moving entities), and impact sticking into terrain/targets.

---

## 8. Medieval Bergen Farms & Ecosystem Distribution

### Farmsteads & Working Farmers
- Three historically accurate farmsteads (*gårder*) on fertile lower shelves:
  1. **Sandviken Gård** (Northern shelf near Byfjorden)
  2. **Bryggen Hinterland Gård** (Terrace east of Bryggen)
  3. **Southern Valley Gård** (Alluvial shelf near Store Lungegårdsvann)
- Structures: Timber *årestuer* with turf roofs and glowing central stone hearths, elevated *stabbur* on rodent-capped stilts, stone freshwater wells, tilled crop beds (cabbage, barley, turnips), and split-rail *skigard* fences.
- Working Farmers (`farmer_ai.gd`): Autonomous chore routines (tending crop plots, chopping firewood, hauling hay, warming by hearth) with authentic medieval Norwegian greetings.

### Wildlife Distribution
- **Mountain Wolves (`wolf_ai.gd`):** Strictly restricted to high altitudes ($\ge 80\text{m}$) on Mount Fløyen and Sandviksfjellet. Retain fire avoidance behavior and retreat uphill if pushed into lowlands.
- **Norwegian Red Cattle (`cow_ai.gd`):** Graze peacefully in farm pastures with interactive milking (`[E]`) that satisfies hunger and thirst.
- **Old Norwegian Sheep / Villsau (`sheep_ai.gd`):** Roam hillside meadows with interactive shearing (`[E]`) yielding wool fleece (fleeces regrow after grazing).
- **Wild Hares (`rabbit_ai.gd`):** Fast, alert hares in perimeter brush that bolt when predators or footsteps approach.

---

## 9. Modular Log Cabin Architecture (Laftehytte)

- **Lafteverk Construction (`building_assembler.gd`):**
  - 5.0m × 5.0m cabin with 4 corner stone footings (*grunnmur*).
  - Interlocking horizontal spruce timber log courses with notched corner joints (*nov*).
  - Full walk-in doorframe (1.1m wide, 1.95m high) with solid wall collisions allowing the settler to walk inside.
  - Traditional sod roof (*torvtak*): heavy ridge beam (*mønsås*), birch bark underlayer, turf roof tiles, eaves retaining logs (*torvvol*), and roof smoke vent (*ljore*).
  - Central stone hearth (*åre*) emitting 360° radiant warmth and crackling firelight, registered in group `"hearth"` for 100% shelter detection by `ShelterDetector`.

---

## 10. Reusable Skills & Automation

The procedures developed and refined during this project have been formalized into permanent reusable skills:
1. **`godot-web-pipeline`**:
   - **Scope:** Headless Godot 4 Web PCK package export, asset import & `.godot/` script class cache bootstrapping (`--editor --quit`), byte-exact PCK file size synchronization in `index.html` loader, and offscreen headless rendering validation using Xvfb with Mesa OpenGL3/llvmpipe.
2. **`godot-web-deploy`**:
   - **Scope:** Web export packaging, Vite bundling, Cross-Origin Isolation (`COOP`/`COEP`) headers for SharedArrayBuffer / WebAssembly threads, and static deployment configurations for Netlify, Vercel, and GitHub Pages.
3. **`game-verification`**:
   - **Scope:** Automated verification pipeline using headless Chromium via Chrome DevTools Protocol (CDP) to boot WebGL games, inspect runtime exceptions, check for WebGL context loss, and capture visual proof screenshots.
4. **`game-bug-and-performance-profiler`**:
   - **Scope:** WebGL resource budgeting, checking GPU draw calls, MeshInstance counts, JS heap memory pressure, and canvas rendering states.
5. **`procedural-terrain-pbr-pipeline`**:
   - **Scope:** Procedural seamless spectral fractal ($1/f^\beta$ FFT) texture synthesis for organic terrain PBR materials, WebGL 2.0-compliant spatial shader authoring, and SurfaceTool tangent space configuration.

---

## 11. Kinematic Climbing & Collision Contact Invariants

### The Mid-Air Climbing Exploit
In open-world games featuring freeform climbing, decoupling climbing mechanics from physical contact checks creates severe exploits where characters ascend infinitely into mid-air:
- **Root Cause Analysis:**
  1. **Unbounded Terrain Slope Sampling:** Direct heightmap checks (`sample_height(x, z)`) test if a slope is steep ($> 50^\circ$), but if they do not verify vertical altitude difference ($\lvert y_{\text{player}} - y_{\text{terrain}}\rvert < 1.8\text{m}$), the slope calculation evaluates to `true` even when airborne 100 meters above the mountain.
  2. **Missing Disengage Loop:** While climbing (`is_climbing == true`), if the character traverses over a ledge crest or turns away from the cliff face, failure to continuously test contact results in retaining the last known wall normal, disabling gravity indefinitely.
  3. **Instant Re-Latching on Release:** When a player presses jump to disengage from a cliff, the jump impulse moves them slightly, but on the subsequent frame the forward raycast immediately detects the wall again and re-engages climbing before the character can clear the wall.
- **Architectural Solution:**
  - **Arm's Reach Distance Bounds:** Constrain forward raycasts to realistic reach ($1.05\text{m}$–$1.1\text{m}$).
  - **Altitude Proximity Guard:** Guard terrain slope sampling with `absf(global_position.y - h_center) < 1.8`.
  - **Continuous Contact Loop:** Check `_check_steep_cliff()` every physics frame during climbing. If contact is lost, immediately set `is_climbing = false` and apply downward velocity (`velocity.y = -2.0`).
  - **State Transition Cooldown:** Introduce `_climb_cooldown` (e.g. $0.35\text{s}$–$0.45\text{s}$) upon manual disengage or jump-off to guarantee crisp separation before allowing re-engagement.

---

## 12. Ground Surface Grounding & WebGL 2.0 PBR Texturing

### The "Floating in Green Void" Problem
In 3D terrain rendering, displaying unshaded vertex colors or flat fallback materials robs the player of visual depth, motion parallax, and contact shadows, making the character feel as if they are floating in mid-air over a cartoon void:
- **Root Cause:**
  - Setting `fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED` completely bypasses all directional lighting, specular reflection, normal map perturbations, and contact shadows.
- **Spectral Fractal Texture Synthesis ($1/f^\beta$ FFT):**
  - Standard periodic sinusoidal noise often creates visible grid/diamond wallpaper artifacts.
  - Using **2D Fast Fourier Transform (FFT) spectral synthesis** with power-law filtering $S(u, v) \propto (u^2 + v^2)^{-\beta / 2}$ generates 100% seamless, mathematically isotropic fractional Brownian motion (fBm).
  - Combining multiple spectral octaves ($\beta = 2.3$ macro moisture, $\beta = 1.8$ turf clumping, $\beta = 1.1$ grass blade strokes, $\beta = 0.8$ soil pebble grain) yields organic Norwegian turf, granite crags, and scree gravel.
  - Generating normal maps via seamless Sobel operator on the composite height field provides rich micro-relief that catches directional sunlight.
- **Godot 4 WebGL 2.0 / Compatibility Shader Rules:**
  - **Diffuse Mode:** Use `render_mode cull_back, diffuse_lambert;`. Avoid `diffuse_burley` which is only supported in Mobile / Forward+ renderers.
  - **Tangent-Space Normal Mapping:** Always call `SurfaceTool.generate_tangents()` when building the mesh. The spatial shader's `NORMAL_MAP` expects tangent-space normal vectors in $[0.0, 1.0]$.
  - **Multi-Octave Rotation:** Rotate the secondary grass sampling octave by $45^\circ$ at scale $0.51$ to completely eliminate noticeable tiling across large plains.

---

## 13. WebGL MeshInstance Budget & Stability

- **Mesh Instance Budget:** WebGL 2.0 running inside browser sandboxes suffers severe driver stutter or context loss if scene node count exceeds $\sim 2000$ active `MeshInstance3D` nodes.
- **Optimization Strategy:**
  - Farmstead fences, cabins, and tree assets must consolidate geometric primitives into single compound meshes or use MultiMeshInstance3D where possible.
  - Keep total scene `MeshInstance3D` count $< 500$ to maintain a steady 60 FPS and prevent WebGL context destruction.

---

## 14. Compound Primitive Batching Architecture

### The Problem: Node Explosion from Procedural Primitives
When generating 3D assets procedurally without external glTF models, building structures out of discrete `MeshInstance3D` nodes (logs, corner posts, rails, roof planks, shingles, stone foundations) rapidly bloats the Godot scene tree to $> 1500$ nodes. In WebGL 2.0 / WebAssembly:
- Each discrete `MeshInstance3D` incurs distinct transform update overhead, culling calculations, and separate WebGL draw calls.
- Total scene `MeshInstance3D` count initially reached 585 nodes, pushing draw calls toward browser driver limits.

### The Solution: SurfaceTool Primitive Compounding
Consolidate repeated geometric primitives of the same material into a single `ArrayMesh` via `SurfaceTool`:
1. **Single-Material Batching:**
   ```gdscript
   var st := SurfaceTool.new()
   st.begin(Mesh.PRIMITIVE_TRIANGLES)
   st.set_material(mat)
   var box := BoxMesh.new()
   box.size = Vector3(w, h, d)
   for x_pos in positions:
       st.append_from(box, 0, Transform3D(basis, Vector3(x_pos, y, z)))
   st.generate_tangents()
   var compound_mesh := st.commit()
   ```
2. **Multi-Material Compound Assemblies:**
   For composite structures (e.g., stone foundations, tarred wall logs, sod turf roofs), chain multiple `SurfaceTool` commits onto a single shared `ArrayMesh` using `st.commit(shared_array_mesh)`.
3. **Verified Results:**
   - Reduced scene `MeshInstance3D` nodes from **585 to 369** (a **37% reduction**).
   - Total scene draw calls capped at **285**, maintaining a stable 60 FPS in WebGL 2.0.

---

## 15. Historical Fjord Fishing & Stockfish Economy Architecture

### Cultural & Gameplay Context
In 14th-century Bergen, dried Atlantic cod (*skrei* / stockfish / *tørrfisk*) was the economic lifeblood of the city, traded through Hanseatic League merchants on the Bryggen wharves.

### Technical Implementation
- **Slot 6 Equipment (`FISHING_LINE`):**
  - Added Handline & Cod Jig to `EquipmentManager` (`KEY_6`) and the HUD Hotbar.
  - Implemented an animated wooden spool and trailing line with an iron sinker jig on `BoxManModel`, featuring rhythmic bobbing and jigging arm postures.
- **Fishing State Machine (`EquipmentManager`):**
  - `IDLE` $\rightarrow$ `WAITING_FOR_BITE` (jigging with subtle lure action) $\rightarrow$ `HOOKED` (reaction window with audio-visual bite alert) $\rightarrow$ `CATCH`.
  - Catches are weighted historically (70% Atlantic cod / *torsk*, 30% herring / *sild*).
- **Interactive Stockfish Drying Racks (`StockfishRackInteractable`):**
  - Integrated into historical drying racks along the Bryggen quayside.
  - Allows the settler to hang raw cod with `[E]`; uses a seasonal curing timer (120s) to produce `stockfish`.
- **Campfire Smoking & Hanseatic Barter:**
  - Fish can be cooked or smoked at campfires (`CampfireInteractable`) to restore hunger and health.
  - Hanseatic merchant counters (`MerchantInteractable`) barter 2 stockfish for high-tier medieval goods: 8 iron nails, 1 salt cask, and 2 rye bread loaves.

---

## 16. Traditional Norwegian Bloomery Iron Smelting (*Myrmalm & Blæsterovn*)

### Cultural & Gameplay Context
Before blast furnaces, medieval Norwegian settlers excavated bog iron ore (*myrmalm*) from wetland hollows and smelted it into workable sponge iron (*jernlupp*) in stone shaft bloomery furnaces (*blæsterovner*) fueled by charcoal and dried peat (*torv*).

### Technical Implementation
- **Wetland Bog Ore Deposits (`BogOreDeposit`):**
  - Placed along runoff hollows and boggy stream margins on the Fløyen slopes.
  - SurfaceTool compound reddish-brown limonite nodules and dark peat turf.
  - Harvested with `[E]` or pickaxe to yield `bog_iron_ore` and `peat_fuel`.
- **Campfire Charcoal Making (`CampfireInteractable`):**
  - Slow-burn carbonization transforms 2 firewood pieces into 2 `charcoal` (*trekol*).
- **Stone Bloomery Furnace & Forging Anvil (`BloomeryFurnaceInteractable`):**
  - Stationed at farmsteads: conical stone shaft furnace with clay chimney lining and flat granite forging anvil.
  - **Smelting Phase:** Consumes 2 bog iron ore + 1 charcoal/peat to smelt a porous `iron_bloom` (*jernlupp*).
  - **Forging Phase:** Smiths the hot bloom on the anvil to hammer out impurities and produce 8 `iron_nails` (*jernsøm*), closing the resource loop for advanced timber cabin construction.

---

## 17. Multi-Agent Fauna AI: Predator Pack Tactics, Herd Flocking, & Storm Sheltering

### Predator Pack Flanking & Howling (`wolf_ai.gd`)
- **Pack Role Assignment:** Dynamic assignment of tactical pursuit roles based on relative neighbor IDs: `ALPHA_LEAD`, `FLANK_LEFT` ($+45^\circ$ lateral offset), `FLANK_RIGHT` ($-45^\circ$ lateral offset), and `REAR_AMBUSH` ($+85^\circ$ encirclement).
- **Acoustic Howl Alert (`alert_pack`):** Upon detecting prey or settler, pack members emit an alert howl every 8s, summoning and orienting all wolves within a 45m radius.
- **Anti-Crowding Repulsion:** Applied continuous inverse-distance separation forces to prevent pursuit clusters from overlapping.
- **Solo Wounded Disengagement:** Injured solitary wolves ($< 20$ HP) abandon pursuit and retreat toward mountain altitudes.

### Deer Herd Panic Propagation & Boids Flocking (`deer_ai.gd`)
- **Acoustic Alarm Broadcasting:** Detection triggers `_broadcast_herd_alarm()`, alerting all herd members within 28m.
- **Flocking Steering Dynamics:** Three-component vector fusion during stampedes:
  $$\vec{v}_{\text{flock}} = 0.65\,\vec{v}_{\text{flee}} + 0.25\,\vec{v}_{\text{align}} + 0.15\,\vec{v}_{\text{separate}}$$
  Guarantees realistic stampede flight without clustering or collision clipping.

### Livestock Weather Awareness & Storm Sheltering (`cow_ai.gd` & `sheep_ai.gd`)
- **Precipitation Detection:** AI agents periodically sample `SeasonManager` for coastal drizzle, heavy Bergen rain, or winter snow.
- **Shelter Seeking:** On storm onset, cows and sheep transition to `State.SHELTERING` and navigate toward the nearest building eave or hay rack tagged in group `"shelter"`.
- **Huddle Posture:** Upon reaching shelter, livestock slow to a stop, tuck their heads, and adopt a subtle synchronized breathing posture until the storm clears.

---

## 18. WebGL 2.0 Build, Packaging, & Asset Synchronization Pipeline

### Invariants for Godot 4 Web Deployments
1. **Zero Dynamic Script Parsing:** `GDScript.new()` cannot be compiled on WebGL templates; always use `set_script(load(...))` with pre-compiled `.gdc` resources.
2. **Strict Spatial Rotation Guards:** Always guard `atan2(-dir.x, -dir.z)` against zero-length vectors (`Vector2(dir.x, dir.z).length() > 0.1`) to prevent `NaN` orientation corruption.
3. **Exact PCK Byte Size Synchronization:**
   The Web HTML loader requires the exact byte count of `index.pck` declared in `GODOT_CONFIG.fileSizes["index.pck"]` in both `web/index.html` and `web/public/index.html`. Discrepancies cause loading bar stalls or asset unpack aborts.
   ```bash
   godot --headless --export-pack "Web" web/public/index.pck
   stat -c %s web/public/index.pck
   # Update fileSizes in web/index.html and web/public/index.html
   cd web && npm run build
   ```
4. **Headless Verification Protocol:**
   - **Editor Script Validation:** `godot --headless --editor --quit` ensures clean class cache rebuild and zero parse errors.
   - **Offscreen OpenGL3 Frame Render:** Execute via `xvfb-run -a godot --rendering-driver opengl3` to measure draw calls and inspect viewport framebuffers.
   - **CDP Headless Chromium Verification:** Run headless Chromium with `--use-angle=swiftshader-webgl` and CDP monitoring to verify zero WebGL context losses and zero unhandled JavaScript exceptions.

