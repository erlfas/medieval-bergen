# Modular 3D Pieces Guide for Medieval Bergen 1360

This directory holds your reusable 3D models (`.gltf`, `.glb`, `.obj`, `.blend`, or `.tscn`).

## How to Replace Placeholders with Your 3D Models

1. **Drop your model files into this directory** (or any subfolder, e.g. `assets/modular_pieces/farmhouse/`).
2. Open or reference the piece recipe in [`scripts/construction/player_builder.gd`](res://scripts/construction/player_builder.gd):
   ```gdscript
   r_lafte_wall.custom_scene = preload("res://assets/modular_pieces/lafteverk_wall.gltf")
   ```
   *That's literally it.* Once assigned, the engine automatically:
   - Uses your 3D mesh for the translucent ghost placement preview.
   - Instantiates your 3D model into the world when the settler clicks to build.
   - Applies the appropriate collision and building logic.

---

## Recommended Modeling Conventions

To ensure pieces snap together seamlessly:

1. **Scale / Units:**
   - 1 unit in Godot = 1 meter.
   - Standard wall bay width: **4.0 meters** (or 2.0m / 3.0m).
   - Standard wall story height: **2.2 to 2.5 meters**.
   - Standard log thickness: **0.3 to 0.4 meters**.
2. **Pivot Point (Origin):**
   - Bottom-center of the piece (`(0, 0, 0)` at ground level or bottom connecting face).
   - For walls: centered along thickness and width at the bottom base.
   - For roof rafters: centered at bottom resting points on top of the walls.
3. **Collision:**
   - You can include simple `-col` collision meshes directly in your `.gltf` (e.g. `mesh_name-col`), or let Godot auto-generate collision from the mesh.
4. **Textures / Materials:**
   - Materials using PBR (Albedo, Normal, Roughness) work seamlessly with the Forward+ and Compatibility renderers in Godot 4.
