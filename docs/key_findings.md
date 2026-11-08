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

### Follow-Behind Camera & Continuous 360° WASD Steering
- The camera continuously tracks behind the character's back (`rotation.y`) with critically damped rotational lag ($\lambda = 10.0\,\text{s}^{-1}$), eliminating orientation disorientation.
- WASD input enables continuous 360° steering and natural curvilinear navigation without requiring mouse input:
  - `W`: Runs forward in the settler's facing direction (`-global_transform.basis.z`).
  - `S`: Walks backward smoothly (backpedal at $2.6\,\text{m/s}$) while keeping forward posture.
  - `A` / `D`: Continuously steers character yaw left and right ($3.2\,\text{rad/s}$, allowing full 360° rotation purely with keys).
  - `W + A` / `W + D`: Carves smooth, natural circular arcs around trees and terrain.
  - Holding Right Mouse Button or aiming the bow enables lateral strafe mode for tactical precision.

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

---

## 19. Kinematic Character Movement Physics & Locomotion Feel

### The Problem: Instant Velocity Snapping and Floatiness
Initial player movement assigned velocities instantaneously (`velocity.x = direction.x * speed`). Releasing movement keys abruptly zeroed velocity without accounting for frame delta. Air movement permitted instant 180° reversals, and jumping failed if the Spacebar was pressed even a single frame prior to touching the floor.

### Technical Implementation (`settler_controller.gd`)
1. **Ground Inertia & Friction Model:**
   - Implemented separate ground acceleration ($a_{\text{accel}} = 15.0\,\text{m/s}^2$) and friction deceleration ($a_{\text{decel}} = 24.0\,\text{m/s}^2$).
   - **Active Direction Reversal Braking:** When the dot product between current horizontal velocity and target input is negative ($\vec{v}_{\text{curr}} \cdot \vec{v}_{\text{targ}} < -0.2$), a heightened braking rate ($a_{\text{brake}} = 34.0\,\text{m/s}^2$) engages, preventing ice-skating drift while feeling physically grounded.
2. **Coyote Time & Jump Input Buffering:**
   - **Coyote Time:** Grace window ($\tau_{\text{coyote}} = 0.12\,\text{s}$) allowing jumps after walking off wharves, cliffs, or stair ledges.
   - **Jump Input Buffering:** Pre-touchdown window ($\tau_{\text{buffer}} = 0.14\,\text{s}$) capturing jump input slightly before ground touchdown.
3. **Variable Gravity & Air Momentum:**
   - Snappier falling gravity curve ($g_{\text{fall}} = 1.35 \times g_{\text{default}}$) producing crisp, physical jump arcs.
   - Air steering acceleration limited to $5.0\,\text{m/s}^2$, preserving jumping momentum.
4. **Slope Traversal & Anti-Snagging:**
   - Floor snapping (`floor_snap_length = 0.35`, `floor_constant_speed = true`, `floor_max_angle = 48^\circ`) eliminates micro-bouncing down hillsides.
   - Speed modulates according to floor incline angle $\theta$: uphill movement experiences up to $35\%$ speed penalty, while downhill traversal provides gentle natural acceleration.

---

## 20. Procedural Locomotion Animation, Torso Banking & Weight Simulation

### Technical Implementation (`box_man_model.gd` & `settler_controller.gd`)
1. **Dynamic Torso Banking:**
   - Calculates character turning angular velocity $\omega_{\text{yaw}} = \Delta \theta / \Delta t$.
   - Applies roll tilt ($\phi \in [-8^\circ, +8^\circ]$) into the curve:
     $$\phi_{\text{roll}} = \text{clamp}(-0.22\,\omega_{\text{yaw}}, -8^\circ, +8^\circ)$$
2. **Acceleration & Sprint Forward Pitch Lean:**
   - Leans the torso forward ($\theta_{\text{pitch}} \approx +8^\circ$) during sprints and brisk movement.
   - Gaze stabilization: head counters torso pitch and roll ($-\theta_{\text{pitch}} \times 0.35$ and $-\phi_{\text{roll}} \times 0.45$) to keep player eyes level on the horizon.
3. **Stride Cadence & Foot-Plant Matching:**
   - Dynamically scales leg swing phase cycle with true ground velocity:
     $$\Delta \text{stride} = \Delta t \times \text{clamp}(v_{\text{horiz}} \times 2.2, 4.0, 15.0)$$
     Eliminates visual foot-sliding across flat wharves and steep slopes alike.
4. **Touchdown Landing Squash & Knee Flare:**
   - Senses vertical touchdown velocity on the transition from airborne to grounded:
     $$y_{\text{squash}} = \text{clamp}(|v_{\text{fall}}| \times 0.018, 0.035, 0.12\,\text{m})$$
   - Torso and head depress vertically while knees flare outward ($\pm y_{\text{squash}} \times 0.35\,\text{rad}$), smoothly recovering via a spring-damper ($\lambda = 11.0$).
5. **Camera Sprint FOV Expansion:**
   - Camera dynamically expands field of view ($75^\circ \to 79^\circ$) during sprinting, amplifying the sensation of speed.

---

## 21. Realistic WebGL 2.0 Fjord Water Shader Architecture

### Technical Implementation (`shaders/fjord_water.gdshader` & `bergen_terrain_generator.gd`)
1. **Multi-Harmonic Gerstner Wave Displacement:**
   - Combines three directional sine waves in the vertex stage: primary Atlantic swell (ENE drift), secondary cross-swell, and coastal chop.
   - Recalculates analytic surface normal derivatives directly from spatial wave gradients $\partial w / \partial x$ and $\partial w / \partial z$, producing crisp sunlight specular highlights.
   - Water mesh subdivision increased from $16 \times 16$ to $128 \times 128$ quads for smooth wave curvature at $< 32\text{k}$ triangles.
2. **Beer-Lambert Depth Color Absorption:**
   - Reconstructs linear eye depth using `hint_depth_texture` and `INV_PROJECTION_MATRIX`.
   - Transitions smoothly from shallow coastal turquoise (`#1F6670`) showing seabed gravel to deep cold Byfjorden Atlantic navy (`#081729`).
3. **Shoreline Contact Foam & Wave Crest White-Caps:**
   - Softstep contact foam band where water surface intersects shore terrain and Bryggen wooden stilts.
   - Dynamic white-cap crest foam on wave peaks exceeding $55\%$ maximum amplitude.
4. **Dual Scrolling Micro-Ripple Normal Maps:**
   - Procedurally generated seamless normal maps (`NoiseTexture2D` with simplex noise) scrolling in opposing diagonal directions, creating rich water surface micro-turbulence.
5. **Schlick Fresnel Grazing Sheen:**
   - Grazing angles reflect atmospheric sky tones, preserving depth clarity when looking directly downward.

---

## 22. Water-Settler Interaction, Wading Physics & Wave-Synchronized Buoyancy

### Technical Implementation
1. **Three-Tier Water State Machine:**
   - **Dry Land:** Full unrestricted ground locomotion.
   - **Shallow Wading ($0.08\,\text{m} < \text{submergence} < 1.05\,\text{m}$):** Settler remains on the seabed; progressive water drag scales velocity down to $55\%$ at chest depth. Cold water steadily increases survival wetness.
   - **Deep Swimming ($\text{submergence} \ge 1.05\,\text{m}$):** Buoyancy engages, floating the settler atop the undulating wave surface.
2. **Synchronized GDScript Wave Sampling (`sample_water_height`):**
   - Implemented an exact analytical mathematical clone of the shader's Gerstner wave displacement on `BergenTerrainGenerator`.
   - Character buoyancy and floating props sample the dynamic wave height in real time, bobbing in frame-perfect sync with visual wave peaks and troughs.
3. **Procedural Water Surface Ripples & Wake FX:**
   - `_spawn_water_ripple(pos)` instantiates lightweight torus ring meshes that expand ($0.5\,\text{m} \to 3.2\,\text{m}$) and fade to alpha 0 over $0.65\,\text{s}$ via tweens whenever the settler takes wading steps or swimming strokes.
   - WebGL 2.0 draw call overhead is strictly bounded through automatic queue-free recycling.

---

## 23. Piece-by-Piece Procedural Building Architecture, Valley Plain Placement & Dense MultiMesh Vegetation

### 1. Piece-by-Piece Modular Building Construction (`scripts/architecture/building_assembler.gd`)
Rather than spawning buildings out of monolithic boxes, all city and farmstead structures are assembled piece-by-piece from discrete medieval Scandinavian timber elements and committed into material-streamed `ArrayMesh` surfaces (`_commit_piece_streams()`):
- **Foundations (`_append_foundation_pieces`):** Corner stone piers (*steinkjeller*), perimeter dry-stone plinths (*grunnmur*), heavy tarred timber sill beams (*svill*), floor joists, and individual floor planks.
- **Lafteverk Notched Log Walls (`_append_lafteverk_wall_courses`):** 8 horizontal log courses with alternating protruding corner notch ends (*lafteknuter / nov*). Log courses dynamically split into left and right segments around any door or window aperture.
- **Grindverk Stave & Trestle Framing (`_append_grindverk_wall_face`):** Corner & bay stave posts (*stav*), top wall plates (*stavline*), transverse tie beams (*bete*), angled diagonal wind braces (*skråbånd*), and vertical overlapping plank cladding (*stående kledning*).
- **Framed Doors & Recessed Mullioned Windows (`_append_door_piece`, `_append_window_piece`):** Heavy timber jambs, lintels, walkable stone thresholds ($0.14\,\text{m}$ high for smooth `SettlerController` step-up), recessed crown-glass panes with wooden crossbar mullions (*sprosser*), and open wooden storm shutters (*vinduslemmer*) with wrought-iron hinge straps.
- **Roofs (`_append_roof_assembly`):** Heavy ridge beam (*mønsås*), side purlins (*åser*), individual exposed rafters (*sperrer*), birch bark or dark plank underlayment, 5 stepped courses of sod turf or wooden shingles (angled at $-\text{sign}_x \cdot \theta_{\text{pitch}}$ to meet cleanly at the central ridge crest cap), gable bargeboards (*vindski*), and optional Hanseatic cargo hoist beams (*heisebjelke*) with iron pulley and rope.

### 2. Glacial Valley Plain Site Solver (`scripts/terrain/bergen_terrain_generator.gd`)
- **Expanded Glacial Valleys:** Added broad flat valley corridors across Sandviken Dal, Bryggen Valley, Markov Valley, and Lungegård Plain.
- **9-Point Flatness Evaluation (`_find_flattest_valley_spot`):** Evaluates candidate sites within each valley search radius to minimize height variance ($\Delta y < 1.2\,\text{m}$) and slope ($< 10^\circ$) at elevations $3.0\,\text{m} \le y \le 24.0\,\text{m}$.
- **Smooth Pad Leveling & Sub-Structure Clamping:** Smoothly blends each settlement pad (`inner_r`, `outer_r`) into the surrounding valley floor and clamps each individual farmstead building (*Årestue*, *Fjøs* barn, *Stabbur*, well, crop beds, *Skigard* fence posts) to its exact `(x, z)` terrain elevation.

### 3. Dense Multi-Layer Forests & Understory (`scripts/environment/vegetation_manager.gd`)
- **3-Species Procedural Forest:** Multi-tier Norway Spruce (*Gran*), Scots Pine (*Furu*), and Nordic White Birch (*Bjørk*).
- **3-Layer Understory:** Woodland ferns (*Bregner*), juniper & blooming heather shrubs (*Einer og Lyng*), and riparian valley meadow reeds (* Siv og Enggress*).
- **Hybrid Choppable + MultiMesh Architecture:** Spawns 95 interactive `HarvestableTree` nodes near valley settlement margins for axe woodcutting while instancing **6,522** trees and understory plants across 6 `MultiMeshInstance3D` batches—keeping total scene `MeshInstance3D` count at **454** ($< 500$ budget) and total frame draw calls at **157**.

---

## 24. Performance & Bug Audit Optimizations

1. **Roof Gable Slope Orientation & Empty SurfaceTool Stream Guard (`building_assembler.gd`):**
   - Corrected roof Z-axis pitch sign to $-\text{sign}_x \cdot \theta_{\text{pitch}}$ so left and right roof slopes meet at a central ridge peak with a sealing ridge crest cap (*Mønskam*).
   - Guarded conditional `SurfaceTool` stream creation (`birch_bark`, `shutter_wood`, `iron_hardware`) so `generate_tangents()` is never invoked on a zero-vertex stream.
2. **Cached Unit Primitive Meshes in Procedural Building Assembly (`building_assembler.gd`):**
   - Replaced per-piece `BoxMesh.new()` and `CylinderMesh.new()` instantiation with cached unit primitives (`_shared_unit_box`, `_shared_unit_cyl`) scaled via `Transform3D(basis.scaled(size), pos)`. This eliminates **3,500+ temporary heap allocations** and redundant primitive vertex generation passes during world load.
3. **Understory Shadow Culling & Distance Visibility Range (`vegetation_manager.gd`):**
   - Disabled directional shadow map rasterization (`SHADOW_CASTING_SETTING_OFF`) and configured `visibility_range_end = 260.0` on the 3 micro-foliage understory `MultiMeshInstance3D` batches (~4,100 ferns, shrubs, and reeds) while preserving full shadows on the 3 forest tree batches—eliminating ~150,000 shadow-pass triangles per frame.
4. **On-Demand Process Activation for Interactive Trees (`harvestable_tree.gd`):**
   - Disabled `_process` and `_physics_process` by default on all 95 `HarvestableTree` instances at startup, enabling `_process` only when focused/chopped and `_physics_process` only during the topple animation—saving **190 idle GDScript virtual calls per frame**.
5. **HUD Label Cache & AI Group Scan Throttling (`hud_clock_calendar.gd`, `wolf_ai.gd`):**
   - Cached `_last_hour` and `_last_minute` in `HUDClockCalendar` to avoid 60 Hz string formatting and UI layout thrashing when the clock minute has not changed.
   - Throttled `_scan_for_fire()` in `wolf_ai.gd` from 60 Hz to 5 Hz (`0.20s`), eliminating 92% of per-frame `get_nodes_in_group()` array allocations.

---

## 25. Third-Person Follow-Behind Camera Architecture & Continuous 360° WASD Steering

### 1. Problem Context & Architectural Flaw of Decoupled Orbit
In early revisions of the third-person camera, camera yaw (`cam_yaw`) was decoupled from character heading (`rotation.y`), driven solely by mouse horizontal delta (`cam_yaw -= relative.x * sens`). Movement direction was calculated in camera space (`direction = cam_right * input.x - cam_forward * input.y`), which created severe gameplay and orientation issues:
- **Disorienting Screen-Facing Inversion:** Pressing `S` (move backward) caused the character to rotate 180° and run directly toward the camera, exposing their face and blinding the player to forward terrain, wolves, or obstacles.
- **Inability to Steer with Keyboard Alone:** Pressing `A` or `D` translated the character sideways in camera space across the screen in a straight line. The player could not rotate, steer around obstacles, or navigate 360° without dragging the mouse.

### 2. Follow-Behind Camera Dynamics & Mathematical Specification
The updated architecture establishes a true **Follow-Behind Camera** with critically damped tracking, terrain elevation smoothing, and asymmetric obstacle avoidance:
1. **Critically Damped Yaw Lag:**
   - Target yaw is rigidly anchored to the settler's facing direction:
     $$\theta_{\text{target}} = \text{rotation.y}$$
   - Angular lag is filtered using smooth angle interpolation:
     $$\theta_{\text{cam}, t} = \text{lerp\_angle}(\theta_{\text{cam}, t-1}, \theta_{\text{target}}, \Delta t \times \lambda_{\text{yaw}})$$
     with $\lambda_{\text{yaw}} = 10.0\,\text{s}^{-1}$. This eliminates jarring camera snaps while preventing disorientation.
2. **Vertical Elevation Low-Pass Filtering:**
   - Rugged terrain, rock crags, and wooden building thresholds introduce sharp vertical steps. Rigidly locking camera Y to settler Y causes jarring vertical jitter.
   - The camera pivot Y tracks settler elevation using an exponential low-pass filter:
     $$y_{\text{pivot}, t} = \text{lerpf}(y_{\text{pivot}, t-1}, y_{\text{settler}} + 1.45\,\text{m}, \Delta t \times 14.0)$$
     This absorbs micro-steps and rock bumps while tracking hills and cliff climbs with zero perceptible latency.
3. **Asymmetric Occlusion & Anti-Clipping:**
   - Evaluates a raycast query from `pivot_pos` to the desired camera offset, excluding the player's `CharacterBody3D`.
   - When an obstacle (mountain cliff, boulder, or cabin wall) is struck at distance $d_{\text{hit}}$, target safe distance is clamped:
     $$d_{\text{safe}} = \max(0.45\,\text{m}, d_{\text{hit}} - 0.25\,\text{m})$$
   - Uses asymmetric spring damping: rapid pull-in ($\lambda_{\text{in}} = 22.0$) prevents geometry clipping, while gentle push-out ($\lambda_{\text{out}} = 8.0$) avoids jarring snaps when clearing obstacles.
   - Lateral shoulder offset and height offset scale proportionally with the safe distance ratio $\frac{d_{\text{safe}}}{d_{\text{target}}}$.

### 3. Continuous 360° WASD Steering & Kinematics
1. **Direct Angular Steering (A / D Keys):**
   - Axis input: $\alpha_{\text{steer}} = \text{Input.get\_axis}(\text{"move\_right"}, \text{"move\_left"})$ ($+1.0$ for `A` / left, $-1.0$ for `D` / right).
   - Steering integration:
     $$\text{rotation.y}_{t} = \text{rotation.y}_{t-1} + \alpha_{\text{steer}} \times \omega_{\text{steer}} \times \Delta t$$
     with $\omega_{\text{steer}} = 3.2\,\text{rad/s}$ (~$183^\circ/\text{s}$). Holding `A` or `D` continuously rotates the character a full 360° without limits.
2. **Linear Drive (W / S Keys):**
   - Forward vector: $\hat{f} = -\text{global\_transform.basis.z}$.
   - Pressing `W` drives forward along $\hat{f}$ at `walk_speed` ($4.2\,\text{m/s}$) or `sprint_speed` ($7.0\,\text{m/s}$).
   - Pressing `S` drives backward along $-\hat{f}$ at dedicated `reverse_speed` ($2.6\,\text{m/s}$) while the character maintains forward posture and the camera remains behind.
3. **Curvilinear Steering Arcs (W + A / W + D):**
   - Combining forward drive and angular steering executes smooth, continuous circular arcs with turning radius $R = v / \omega \approx 1.31\,\text{m}$, allowing players to effortlessly carve paths around trees, fences, and wharves.
4. **Tactical Strafe Mode:**
   - Holding Right Mouse Button (RMB) or aiming the recurve bow enables strafing, switching `A`/`D` to lateral translation ($\pm \hat{r}$) while mouse yaw controls aiming orientation.

### 4. Procedural Locomotion Animation Integration (`box_man_model.gd`)
1. **In-Place 360° Turn Step Shuffle:**
   - Measures real-time body yaw rate: $\omega_{\text{yaw}} = \frac{\Delta \theta_{\text{global}}}{\Delta t}$.
   - When grounded and stationary ($v_{\text{horiz}} \le 0.15\,\text{m/s}$) with $|\omega_{\text{yaw}}| > 0.35\,\text{rad/s}$, triggers an alternating foot-shuffle animation:
     $$\Delta \text{turn} = \Delta t \times 7.5, \quad \theta_{\text{leg}} = \pm \sin(\text{turn\_cycle}) \times 0.22\,\text{rad} \times \text{sign}(\omega_{\text{yaw}})$$
     Eliminates "ice-skate sliding" when rotating in place 360°.
2. **Reversed Stride Cadence for Backward Walking:**
   - Computes velocity alignment with forward heading: $d = \hat{v} \cdot \hat{f}$.
   - When $d < -0.2$, the stride animation phase cycle runs in reverse ($\Delta \text{walk} = \Delta t \times \text{anim\_rate} \times (-1)$), stepping backward realistically.
3. **Curvilinear Torso Banking:**
   - Torso rolls into turning curves ($\phi_{\text{roll}} = \text{clamp}(-0.22\,\omega_{\text{yaw}}, -8^\circ, +8^\circ)$) while the head counter-stabilizes to keep gaze level with the horizon.

### 5. Automated Headless Verification Pipeline
- Verified with automated test script in Godot 4.3 using Xvfb with Mesa OpenGL3:
  - Full 360° rotation completed in 120 frames ($6.40\,\text{rad} \ge 2\pi$).
  - Camera yaw synchronized behind character back ($|\Delta\text{yaw}| < 0.001\,\text{rad}$).
  - Forward velocity ($4.17\,\text{m/s}$) and reverse velocity ($2.60\,\text{m/s}$) confirmed.
  - Camera pivot distance ($3.23\,\text{m}$) verified without collapse.

---

## 26. High-Performance Multi-Tier Grass System & Biotic Grazing Architecture

### 1. Ingestion & Decimation of High-Poly 3D Model (`grass clump 3d model.glb`)
- **Raw Asset Constraints:** The imported GLB model contained 18,955 triangles, 22,709 vertices, and uncompressed $4096 \times 4096$ textures, totaling $9.91\,\text{MB}$. Instancing this raw mesh would exceed WebGL draw and vertex budgets within seconds.
- **Automated Decimation Pipeline (`scripts/terrain/optimize_grass_model.py`):**
  - **LOD0 High-Fidelity 3D Model (`grass_clump_lod0.glb`):** Filtered 2,700+ micro-noise polygon fragments, retaining the top 65 major stalks, and decimated via quadric error to **439 triangles** (a $97.7\%$ reduction) with nearest-neighbor KDTree UV interpolation and ground plane re-anchoring ($y_{\min} = 0.0$).
  - **LOD1 Crossed-Quad Graphic (`grass_clump_lod1.glb`):** 3 intersecting vertical double-sided planes (**6 triangles**) textured with a baked alpha cutout billboard (`grass_billboard.png`).
  - **Texture Compression:** Resized textures to $512 \times 512$ high-quality JPEGs ($104\,\text{KB}$ albedo, $96\,\text{KB}$ normal, $58\,\text{KB}$ PBR roughness), reducing asset footprint from $9.9\,\text{MB}$ to **$279\,\text{KB}$**.

### 2. Physically-Based Cantilever Wind Shader (`shaders/grass_wind.gdshader`)
- **Root-Lock Invariant:** Vertex displacement scales quadratically with height above ground:
  $$w_{\text{bend}} = \left(\text{clamp}\left(\frac{V_y}{H_{\text{blade}}}, 0.0, 1.0\right)\right)^2$$
  ensuring roots ($y = 0.0$) experience strictly $0.000\,\text{m}$ deflection while tips sway freely.
- **Wave Synthesis:** Blends continuous low-frequency fjord breeze with positive pulsed traveling gusts and high-frequency micro-blade flutter.
- **Length Conservation:** Clamps and computes $V_y = \sqrt{\max(0.0, V_{y,\text{orig}}^2 - \|\Delta V_{xz}\|^2)}$, preventing unnatural blade stretching during heavy gusts.

### 3. Biotic Grazing & Terrain-Aware Height Solver (`scripts/environment/grass_manager.gd`)
- **Sheep Grazing Pastures:** Queries `_settlement_pads` where `is_farm == true` (sheep pasture center located at $fc + (18.0, 0, 0)$ with $20\,\text{m}$ grazing radius). Grass within grazing pastures is cropped down to **$0.18\,\text{m} - 0.35\,\text{m}$** (grazed turf lawn).
- **Valley Meadows:** Medium lush grass at elevations $2.0\,\text{m} \le y \le 25.0\,\text{m}$ outside pastures (**$0.50\,\text{m} - 0.75\,\text{m}$**).
- **Wilderness & Mountain Foothills:** Far-away wild grass on valley outskirts and slopes ($25.0\,\text{m} < y \le 90.0\,\text{m}$) scales up to **$0.95\,\text{m} - 1.40\,\text{m}$** with golden wild rye tints.
- **Building Exclusions:** Suppresses grass completely inside settlement building footprints and wharves.

### 4. Distance LOD & WebGL 2.0 Profiling Results
- **Sector Dimension Optimization for Node Budgets:**
  - A fine-grained $42\,\text{m} \times 42\,\text{m}$ grid created 185 spatial sectors across the valley ($185 \times 2 = 370$ `MultiMeshInstance3D` nodes), which would have pushed the scene node count to 824 and exceeded the 500-node WebGL ceiling.
  - Sizing sectors to $110\,\text{m} \times 110\,\text{m}$ macro-cells consolidated the valley into **28 active sectors** (56 MultiMesh nodes), keeping total scene `MeshInstance3D` count at **454** (safely below the 500 WebGL ceiling).
- **Benchmark Metrics:**
  - Scene `MeshInstance3D` count: **454** ($< 490$ target budget, strictly below 500 WebGL ceiling).
  - Active grass clumps: **4,255** across 28 sectors.
  - Static engine memory: **$121.2\,\text{MB}$** (well below $350\,\text{MB}$ limit).
  - Web export bundle: `web/public/index.pck` grew from $46.4\,\text{MB}$ to $47.6\,\text{MB}$ (delta $+1.19\,\text{MB}$).

### 5. Critical Technical Findings & Architectural Pitfalls

#### A. Godot 4 Headless Dummy Renderer vs. OpenGL3 MultiMesh Buffers
- **Symptom:** In automated headless tests (`--headless`), `mm.get_instance_transform(i)` returned `(0, 0, 0)` and `mm.buffer` had a size of 0 despite successful `set_instance_transform()` calls.
- **Root Cause:** In headless mode without a display server, Godot initializes `RendererDummy`, which deliberately bypasses GPU buffer allocation and drops MultiMesh transform buffer storage to conserve memory.
- **Solution:** Execute automated spatial distribution and render tests under Xvfb with the explicit OpenGL3 rendering driver:
  ```bash
  xvfb-run -a /tmp/godot --rendering-driver opengl3 --script scripts/tests/test_grass_distribution.gd
  ```
  This instantiates the real Mesa Compatibility OpenGL3 backend (`llvmpipe`), accurately populating the MultiMesh instance float buffer (`PackedFloat32Array` of size $16 \times N$) and returning true world-space transforms.

#### B. Raw Asset PCK Bloat Prevention via `exclude_filter`
- **Symptom:** Initial web export generated a $75.7\,\text{MB}$ `.pck` bundle (a $+29.3\,\text{MB}$ bloat).
- **Root Cause:** In `export_presets.cfg`, `export_filter="all_resources"` exports every recognized asset in `res://`. When Godot imported `3dmodels/grass clump 3d model.glb`, it generated uncompressed $4096 \times 4096$ and $2048 \times 2048$ `.ctex` textures in `.godot/imported/` and packed the raw $9.91\,\text{MB}$ GLB.
- **Solution:** Configured `exclude_filter` in `export_presets.cfg`:
  ```ini
  exclude_filter="web/*, scratch/*, 3dmodels/*"
  ```
  The raw source models in `3dmodels/` remain available for authoring and tooling but are cleanly excluded from the web bundle, while only the optimized assets in `assets/terrain/` ($279\,\text{KB}$) are packaged into `index.pck`.

#### C. Phase-by-Phase Automated Gate Matrix
| Gate | Target System | Verification Command | Pass/Fail Criteria | Result |
| :--- | :--- | :--- | :--- | :--- |
| **Gate 1** | Asset Decimation | `python3 scripts/terrain/verify_grass_assets.py` | LOD0 $\le 500$ tris, total size $\le 450\,\text{KB}$ | **PASSED** (439 tris, $279\,\text{KB}$) |
| **Gate 2** | Wind Shader | `/tmp/godot --headless --script scripts/tests/test_grass_shader.gd` | 0 GL errors, root $\Delta V \equiv 0.0\,\text{m}$, tip $\le 0.42\,\text{m}$ | **PASSED** ($\Delta V_{\text{root}} = 0.000\,\text{m}$) |
| **Gate 3** | Grazing Distribution | `xvfb-run -a /tmp/godot --rendering-driver opengl3 --script scripts/tests/test_grass_distribution.gd` | Pasture height $\le 0.35\,\text{m}$, wilderness $\ge 0.85\,\text{m}$ | **PASSED** (0 height violations) |
| **Gate 4** | WebGL Profiler | `xvfb-run -a /tmp/godot --rendering-driver opengl3 --script scripts/tests/profile_grass_performance.gd` | Meshes $\le 490$, memory $\le 350\,\text{MB}$, render valid | **PASSED** (454 meshes, $121\,\text{MB}$) |
| **Gate 5** | Web Export & Vite | `npm run build && git status` | `dist/index.html` built, clean working tree | **PASSED** (Vite built in 85ms) |




