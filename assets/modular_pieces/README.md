# Modular 3D Pieces Guide for Medieval Bergen 1360

This directory holds your reusable Blender-generated 3D models (`.glb`, `.gltf`, `.obj`, `.blend`, or `.tscn`).

## Blender-Generated *Laftehytte* (`Årestue`) Modular Kit (`assets/modular_pieces/laftehytte/`)

All 16 *Laftehytte* modular `.glb` assets in `assets/modular_pieces/laftehytte/` are generated procedurally using **Blender Python (`bpy` + `bmesh`)** via [`scripts/architecture/generate_laftehytte_modules_blender.py`](../../scripts/architecture/generate_laftehytte_modules_blender.py):

### Atomic Architectural Modules
1. **`foundation_pier.glb`** — 3-course stacked Bergen gneiss & slate foundation pier (*Grunnmurstein*, `0.64m × 0.61m × 0.64m`).
2. **`foundation_plinth_4m.glb`** — Recessed dry-stone rubble skirt + chamfered tarred mudsill beam (*Svillstokk*, `4.0m` bay span).
3. **`floor_plank_bay.glb`** — Sub-floor transverse joists (*Gulvbjelker*) + hand-planed spruce floorboards (*Gulvbord*, `4.0m × 4.0m`).
4. **`laft_log_4m.glb`** — Single hand-hewn octagonal spruce log (*Laftestokk*) with corner saddle notches (*Nov / Lafteknute*) and beveled end-grain (*Laftehode*).
5. **`laft_wall_solid.glb`** — 8-course interlocking notched *Lafteverk* log wall (`4.0m` bay span + `0.30m` corner overhang) with moss/tar chinking seams (*Mosefar*).
6. **`laft_wall_window.glb`** — 8-course notched log wall split around a recessed medieval mullioned window (*Vinduskarm*), crown glass pane, and open storm shutters (*Vinduslemmer*) with wrought-iron strap hinges.
7. **`laft_wall_doorway.glb`** — 8-course notched log wall with carved portal jambs (*Dørstolper*), overhead lintel & rain hood (*Dørbislag*), low-profile stepped welcome stone (`<= 0.10m`), and open planked door (*Dørblad*) with wrought-iron strap hinges.
8. **`laft_gable_triangle.glb`** — 6-course tapered triangular log gable (*Gavlvegg*, `5.0m` span × `1.40m` rise) with purlin notches.
9. **`torvtak_roof_slope.glb`** — Raftered roof slope (*Sperretak*) with exposed spruce rafters, side purlin (*Ås*), white birch bark underlayment (*Never*), eaves retaining log (*Torvvol*), wooden hook brackets (*Torvhald*), and stepped living sod turf courses (*Torvtak*).
10. **`ljore_smoke_vent.glb`** — Central ridge beam (*Mønsås*), turf ridge crest (*Mønskam*), crossed gable bargeboards (*Vindski*), and rooftop smoke-vent skylight frame (*Ljore*).
11. **`are_central_hearth.glb`** — Raised 12-stone slate curb ring (*Åre Ildsted*), dark ash bed, crossed charwood logs, and wrought-iron kettle trivet.
12. **`langbenk_sleeping_bench.glb`** — Interior wall-mounted spruce sleeping bench (*Langbenk / Bris*) with carved trestles and headrest bolster.

### Composite Stage Modules (5.0m × 5.0m Standard Footprint)
13. **`stage_1_foundation.glb`** — Complete Stage 1 Foundation & Floor (*Grunnmur*).
14. **`stage_2_walls.glb`** — Complete Stage 2 Interlocking Log Walls, Windows & Hinged Door (*Veggløft*).
15. **`stage_3_roof.glb`** — Complete Stage 3 Gables, Rafters, Sod Roof & Ljore Smoke Hole (*Torvtak*).
16. **`stage_4_hearth.glb`** — Complete Stage 4 Central *Åre* Hearth & *Langbenk* Bench (*Åre Ildsted*).

---

## How Piece-by-Piece Procedural Assembly Works in the World

[`BuildingAssembler`](../../scripts/architecture/building_assembler.gd) loads and caches the `ArrayMesh` surfaces from `res://assets/modular_pieces/laftehytte/*.glb` and stamps them piece-by-piece (`_append_blender_module`) into unified multi-surface meshes for:
- All 4 Valley Farmstead *Årestuer* and elevated *Stabbur* storehouses in [`FarmsteadGenerator`](../../scripts/architecture/farmstead_generator.gd).
- Outlying Pioneer, Coastal Fisherman, and Mountain Woodcutter *Laftehytte* cabins in [`BergenTerrainGenerator`](../../scripts/terrain/bergen_terrain_generator.gd).
- Player-built complete cabins, 4-stage constructions, ghost previews, and individual modular pieces in [`PlayerBuilder`](../../scripts/construction/player_builder.gd).

To regenerate all `.glb` modules after editing the Blender script:
```bash
python3 scripts/architecture/generate_laftehytte_modules_blender.py
```

For full technical details on the coordinate mapping, `bmesh` geometry generation, material surface binding, and `SurfaceTool` draw-call batching, see [`BLENDER_LAFTEHYTTE_PIPELINE.md`](../../BLENDER_LAFTEHYTTE_PIPELINE.md).

