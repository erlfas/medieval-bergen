# Blender-to-Godot Procedural *Laftehytte* Pipeline — Key Findings

This document summarizes the architectural, mathematical, and performance findings from building the 14th-century Bergen **Laftehytte (*Årestue*)** modular 3D kit in headless **Blender (`bpy` 5.0 + `bmesh`)** and assembling all *Laftehytte* cabins across the world piece-by-piece in **Godot 4.3 (WebGL 2.0 Compatibility Renderer)**.

---

## 1. Coordinate System & Basis Mapping (`bpy` Z-Up $\leftrightarrow$ glTF / Godot Y-Up)

### Finding
Blender uses a right-handed **Z-up** coordinate system (`+X` right, `+Y` forward/back, `+Z` up), whereas glTF 2.0 and Godot 4 use a right-handed **Y-up** coordinate system (`+X` right, `+Y` up, `+Z` back/south). When exporting with `bpy.ops.export_scene.gltf(..., export_yup=True)`, Blender applies the orthogonal basis transformation:

$$\begin{bmatrix} x_{\text{godot}} \\ y_{\text{godot}} \\ z_{\text{godot}} \end{bmatrix} = \begin{bmatrix} x_{\text{blender}} \\ z_{\text{blender}} \\ -y_{\text{blender}} \end{bmatrix}$$

### Solution in [`generate_laftehytte_modules_blender.py`](scripts/architecture/generate_laftehytte_modules_blender.py)
Rather than authoring geometry in Blender coordinates and compensating with root-node rotations in Godot, we author all architectural dimensions directly in **Godot local coordinates** `(gx, gy, gz)` and map them into `bmesh` via the exact inverse transformation $C$:

$$C = \begin{bmatrix} 1 & 0 & 0 \\ 0 & 0 & -1 \\ 0 & 1 & 0 \end{bmatrix}, \quad C^{-1} = C^T = \begin{bmatrix} 1 & 0 & 0 \\ 0 & 0 & 1 \\ 0 & -1 & 0 \end{bmatrix}$$

- **Position mapping (`g_pos`):**
  ```python
  def g_pos(gx: float, gy: float, gz: float) -> Vector:
      return Vector((gx, -gz, gy))
  ```
- **Orientation / Basis mapping (`g_mat`):**
  For any rotation or scale matrix $M_{\text{godot}}$ defined in Godot space (such as roof pitch rotations $\pm\theta$ or open door/shutter hinge angles), its Blender `bmesh` equivalent is the similarity transform:
  $$M_{\text{blender}} = C \cdot M_{\text{godot}} \cdot C^{-1}$$

This guarantees **1-to-1 spatial alignment** between every exported `.glb` module and [`BuildingAssembler`](scripts/architecture/building_assembler.gd)'s procedural sockets, collision shapes, and terrain pads.

---

## 2. Procedural `bmesh` Vernacular Geometry & Historical Detailing

All 16 `.glb` modules in [`assets/modular_pieces/laftehytte/`](assets/modular_pieces/laftehytte/) are constructed purely with `bmesh` in [`scripts/architecture/generate_laftehytte_modules_blender.py`](scripts/architecture/generate_laftehytte_modules_blender.py):

1. **Hand-Hewn Octagonal Logs (`_add_hewn_log_Y`):**
   - Uses an 8-sided chamfered cross-section with a `0.92` vertical flattening ratio (`flat-sided` broadaxe finish) and subtle deterministic organic wobble (`sin`/`cos` phase per course) so stacked logs never look like sterile cylinders.
   - Includes tapered *laftehode* beveled end-grains (`end_taper=0.76`) and recessed dark-tarred saddle notches (*nov / lafteknute*) at every corner intersection.
2. **Half-Course Interlocking Wall Stacking:**
   - Standard wall bays (`laft_wall_solid.glb`, `laft_wall_window.glb`, `laft_wall_doorway.glb`) span a `4.0m` clear bay (`4.6m` total log length including `0.30m` *laftehode* overhangs).
   - In [`BuildingAssembler._append_laftehytte_wall_modules()`](scripts/architecture/building_assembler.gd), East/West walls are elevated by half a log course (`+0.16m`, i.e., `0.5 * LOG_STEP`) relative to North/South walls so the projecting corner heads physically interlock at every corner.
3. **Walkable Stepped Entrance Threshold:**
   - The doorway module (`laft_wall_doorway.glb`) replaces a tall sill barrier with a 2-tier stepped flagstone welcome stone (`0.08m` and `0.16m` rises, each $\le 0.10\text{m}$ step delta) so `CharacterBody3D` settlers walk seamlessly through the open `1.20m` portal without jumping.
4. **Multi-Layer *Torvtak* Sod Roof (`torvtak_roof_slope.glb` & `ljore_smoke_vent.glb`):**
   - Models the full historical cross-section: exposed interior spruce rafters (*sperrer*), horizontal purlins (*åser*), overlapping white birch-bark waterproof sheets (*never*) overhanging the eaves, dark-tarred *torvhald* wooden hook brackets pinning the *torvvol* eaves retaining log, stepped courses of living meadow turf (*torvtak*), crossed gable bargeboards (*vindski*), and the rooftop *ljore* smoke-vent skylight.

---

## 3. Multi-Material glTF Surface Preservation & Godot PBR Binding

### Finding
When a single Blender `Mesh` object contains faces assigned to multiple `bpy.data.materials` slots, Blender's glTF 2.0 exporter splits the mesh into one glTF primitive (Godot `ArrayMesh` surface) per material and preserves the exact Blender material name on `mesh.surface_get_material(surface_idx).resource_name`.

### Solution
Each `.glb` module uses up to 9 named architectural materials:
- `wood_spruce` — Heartwood spruce logs, rafters, and floorboards
- `wood_dark` — Pine-tarred sill beams (*svill*), *lafteknute* notches, *torvhald* hooks, and charwood
- `wood_weathered` — Weathered exterior trim, door planks, and benches
- `stone_foundation` — Bergen gneiss & slate foundation piers, rubble plinth, and *åre* hearth curb
- `sod_roof` — Living grassy meadow turf (*torvtak*)
- `birch_bark` — White *never* birch-bark roof underlayment sheets
- `iron_hardware` — Wrought-iron strap hinges, door rings, and kettle trivet
- `window_glass` — Translucent green-tinted medieval crown glass
- `shutter_wood` — Ocher/red painted storm shutters (*vinduslemmer*)

When [`BuildingAssembler.get_laftehytte_module_mesh()`](scripts/architecture/building_assembler.gd) loads each `.glb` `PackedScene`, it caches the extracted `ArrayMesh` in `_laftehytte_module_meshes` and maps each surface's `resource_name` via `_resolve_blender_surface_material()` to the game's shared procedural noise-bumped `StandardMaterial3D` instances. This keeps GPU shader state uniform across the entire world and avoids duplicate material allocations.

---

## 4. WebGL 2.0 Draw-Call Batching (`SurfaceTool.append_from`)

### Finding
In Godot 4.3's `gl_compatibility` (WebGL 2.0) renderer, instancing 11 *Laftehytte* buildings across the world out of unmerged child `MeshInstance3D` nodes (foundation piers + plinths + floor bays + 4 walls + 2 gables + 2 roof slopes + ljore + hearth + benches $\approx 25\text{–}35$ nodes per building) would add $>300$ extra `MeshInstance3D` draw calls and push the scene past the `< 500 MeshInstance3D` WebGL performance budget.

### Solution
[`BuildingAssembler._append_blender_module()`](scripts/architecture/building_assembler.gd) uses `SurfaceTool.append_from(mesh, surface_idx, Transform3D)` to stamp each `.glb` module's surfaces directly into a per-building, per-material `SurfaceTool` dictionary (`st_by_mat`):

```gdscript
for s in range(mesh.get_surface_count()):
    var mat := _resolve_blender_surface_material(mesh, s, override_mat)
    var st := _get_mat_st(st_by_mat, mat)
    st.append_from(mesh, s, xform)
```

Once all foundation, wall, gable, roof, and interior modules for a building are stamped with their respective `Transform3D` placements (including arbitrary footprint scaling `w / 5.0`, `d / 5.0` and per-farmstead window/bench variations), `_commit_mat_sts()` commits all surfaces into **a single `MeshInstance3D` with a multi-surface `ArrayMesh`** per building.

### Verified Metrics
| Metric | Result | Target Budget |
|---|---|---|
| Blender `.glb` modules generated & imported | **16 / 16** (`1.66 MB` total) | 16 modules |
| Piece-built *Laftehytte* buildings in world | **11 structures** (4 Farmstead *Årestuer*, 4 *Stabbur*, 3 Outlying Cabins) | All world *Laftehytte* |
| Player Builder recipes wired to Blender `.glb` | **14 / 14** (Complete, 4 Stages, 9 Modular Pieces) | 100% coverage |
| Total active scene `MeshInstance3D` count | **456** | `< 500` |
| Runtime script / shader / WebGL errors | **0** | `0` |

---

## 5. Build, Import & Web Export Operational Notes

1. **Importing New `.glb` Assets in Headless Godot:**
   - Run `xvfb-run -a godot --headless --editor --quit` to generate `.glb.import` sidecar files and `.godot/imported/*.scn` caches before running `--export-release "Web"`.
   - Keep `3dmodels/.gdignore` present during `--editor --quit` if raw unimported third-party models exist in `3dmodels/`, preventing Godot from extracting untracked textures into `3dmodels/`.
2. **Godot CLI `--script` Requirement:**
   - Godot's `--script` flag requires a filesystem path (`res://...` or `/tmp/*.gd`) and does not accept `-` (stdin).
3. **Web Export `index.pck` Size Synchronization:**
   - After exporting `web/public/index.pck`, always update `GODOT_CONFIG.fileSizes["index.pck"]` in both [`web/index.html`](web/index.html) and [`web/public/index.html`](web/public/index.html) to match the exact byte count (`stat -c%s web/public/index.pck`) so the WebAssembly preloader progress bar and buffer allocation succeed.
