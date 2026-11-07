---
name: game-bug-and-performance-profiler
description: Audit, detect, diagnose, and solve bugs and performance bottlenecks in Godot 3D web games, including WebGL draw call budgets, MeshInstance pooling, shader compilation, physics ticks, memory leaks, and runtime script errors.
---

# Game Bug & Performance Profiler Skill

Use this skill when diagnosing low framerates, visual artifacting, missing 3D meshes, WebGL memory exhaustion, or script runtime exceptions in Godot 3D web builds.

---

## 1. WebGL 2.0 / Compatibility Renderer Constraints

In Godot 4.x running in WebAssembly with the Compatibility (WebGL 2.0 / OpenGL ES 3.0) renderer, specific architectural constraints must be adhered to:

### A. Mesh Instance & Draw Call Budget
- **Symptom**: 3D world disappears completely; only procedural sky dome and 2D canvas layers render.
- **Root Cause**: The WebGL Compatibility backend cannot handle unbounded individual `MeshInstance3D` nodes in a single frame (>1,000–1,200 nodes). The command buffer drops draw calls silently without throwing a fatal JavaScript error.
- **Mitigation & Fixes**:
  1. **Compound Geometry**: Merge individual sub-meshes (e.g. log walls, fence rails) into unified meshes or use `MultiMeshInstance3D` for repeated geometry.
  2. **Lazy Node Instantiation**: Never pre-instantiate UI indicators, target arcs, or interaction widgets across hundreds of world objects. Instantiate or add to tree lazily when the player is within interaction range.
  3. **Culling & Distance LOD**: Use `VisibilityRange` or distance culling for dense props and fauna.

### B. Dynamic Script Compilation Ban
- **Symptom**: `GDScript.new()` or `script.source_code = ...` fails silently or throws compilation errors in Web export builds.
- **Root Cause**: Web export templates strip the Godot script compiler and parser by default for security and binary size reasons.
- **Fix**: Never use dynamic `GDScript.new()` compilation in runtime code. Always write concrete static `.gd` script files and attach them via `preload()` or `load()`.

### C. Safe Spatial Orientations
- **Symptom**: `look_at failed to find valid up vector` or crash in animal AI / character controllers.
- **Root Cause**: Calling `look_at()` or `Basis.looking_at()` when target direction vector length is near zero (`dir.length() < 0.001`) or parallel to `Vector3.UP`.
- **Fix**: Always guard with horizontal length check:
  ```gdscript
  if Vector2(dir.x, dir.z).length() > 0.1:
      rotation.y = atan2(-dir.x, -dir.z)
  ```

### D. Audio & Pointer Lock Gestures
- **Symptom**: `DOMException: A user gesture is required to request Pointer Lock` or audio context stays suspended.
- **Fix**: Defer pointer lock and audio playback until the player clicks or presses a key on the game canvas.

---

## 2. Profiling & Diagnostics Procedure

### Step 1: Run WebGL Budget Audit
Run the automated environment and budget audit:
```bash
node .agents/skills/game-bug-and-performance-profiler/scripts/audit_game_budget.js
```
Examine:
- Renderer & vendor (`WebKit WebGL`, ANGLE implementation)
- Max uniform vectors and texture sizes
- Heap memory allocation (`totalJSHeapSizeMB`, `usedJSHeapSizeMB`)
- Context loss indicators (`isContextLost: false`)

### Step 2: Mesh Count Audit
Run an automated node audit in Godot to count active `MeshInstance3D` nodes by parent group:
```gdscript
func audit_scene_meshes(root: Node) -> Dictionary:
    var counts := {}
    for node in root.find_children("*", "MeshInstance3D", true, false):
        var grp := "ungrouped"
        var p := node.get_parent()
        while p and p != root:
            if not p.get_groups().is_empty():
                grp = p.get_groups()[0]
                break
            p = p.get_parent()
        counts[grp] = counts.get(grp, 0) + 1
    return counts
```
Target total scene `MeshInstance3D` count for smooth 60 FPS in WebGL: **< 500 total instances**.

### Step 3: Material & Shader Optimization
- In Compatibility mode, keep shader texture lookups minimal.
- Avoid real-time shadow casting from DirectionalLight3D on low-end hardware (`shadow_enabled = false` for web builds, relying on ambient lighting and baked/vertex color contrast).
- Ensure vertex winding order is counter-clockwise (CCW) with upward pointing normals for terrain and custom `SurfaceTool` meshes.

### Step 4: Verification & Sign-off
After identifying and patching performance bottlenecks:
1. Re-run `game-verification` skill.
2. Confirm FPS > 50 FPS and draw call / mesh count stays within budget.
3. Confirm zero console errors.
