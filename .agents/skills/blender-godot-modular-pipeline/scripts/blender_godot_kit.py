#!/usr/bin/env python3
"""
blender_godot_kit.py
====================
Reusable headless Blender (`bpy` + `bmesh`) toolkit for authoring procedural 3D
modular architecture, props, and decimated LOD assets directly in Godot 4 Y-up
coordinates (`+X` Right/East, `+Y` Up, `+Z` Back/South) and exporting WebGL 2.0
ready `.glb` files.

Usage inside any generator script:
    import sys, os
    sys.path.append(os.path.abspath(".agents/skills/blender-godot-modular-pipeline/scripts"))
    import blender_godot_kit as bgk

    bgk.reset_scene()
    palette = bgk.MaterialPalette.create_medieval_bergen_palette()
    bm = bgk.new_bmesh()
    bgk.add_box(bm, center_g=(0.0, 0.5, 0.0), size_g=(4.0, 0.25, 0.25), mat_idx=palette.idx("wood_spruce"))
    bgk.export_glb(bm, "my_beam", "assets/modular_pieces/custom", palette)
"""

import math
import os
from typing import Dict, List, Optional, Sequence, Tuple

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector


# ==============================================================================
# 1. COORDINATE & BASIS MAPPING (Godot Y-Up <-> Blender Z-Up)
# ==============================================================================
# Blender's glTF 2.0 exporter with `export_yup=True` maps:
#   (x_blender, y_blender, z_blender) -> (x_godot, z_godot, -y_godot)
# Therefore, the exact inverse mapping from Godot (gx, gy, gz) to Blender is:
#   (x_blender, y_blender, z_blender) = (gx, -gz, gy)

C_G2B = Matrix((
    (1.0, 0.0,  0.0),
    (0.0, 0.0, -1.0),
    (0.0, 1.0,  0.0),
))
C_B2G = C_G2B.transposed()


def g_pos(gx: float, gy: float, gz: float) -> Vector:
    """Convert Godot (X right, Y up, Z south) point to Blender (X right, Y north, Z up)."""
    return Vector((float(gx), -float(gz), float(gy)))


def g_vec(v: Sequence[float]) -> Vector:
    """Convert a 3-tuple or Vector in Godot coordinates to a Blender Vector."""
    return Vector((float(v[0]), -float(v[2]), float(v[1])))


def b_to_g_pos(bv: Vector) -> Tuple[float, float, float]:
    """Convert a Blender Vector (bx, by, bz) back to Godot (gx, gy, gz)."""
    return (float(bv.x), float(bv.z), float(-bv.y))


def g_mat(m_godot_3x3: Matrix) -> Matrix:
    """Convert a 3x3 rotation/scale Matrix defined in Godot axes into Blender axes."""
    return C_G2B @ m_godot_3x3 @ C_B2G


def g_rot_x(angle_rad: float) -> Matrix:
    """3x3 Blender rotation matrix for a rotation around Godot's +X axis."""
    return g_mat(Matrix.Rotation(angle_rad, 3, 'X'))


def g_rot_y(angle_rad: float) -> Matrix:
    """3x3 Blender rotation matrix for a rotation around Godot's +Y (up) axis."""
    return g_mat(Matrix.Rotation(angle_rad, 3, 'Y'))


def g_rot_z(angle_rad: float) -> Matrix:
    """3x3 Blender rotation matrix for a rotation around Godot's +Z (south) axis."""
    return g_mat(Matrix.Rotation(angle_rad, 3, 'Z'))


def g_euler(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0, order: str = 'YXZ') -> Matrix:
    """3x3 Blender rotation matrix from Euler angles (in radians) defined in Godot space."""
    m_godot = Euler((rx, ry, rz), order).to_matrix()
    return g_mat(m_godot)


# ==============================================================================
# 2. SCENE RESET & MATERIAL PALETTE
# ==============================================================================

def reset_scene() -> None:
    """Clear all objects, meshes, and materials from the headless Blender scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_bmesh() -> bmesh.types.BMesh:
    """Create a fresh BMesh instance."""
    return bmesh.new()


class MaterialPalette:
    """Manages an ordered list of Blender Principled BSDF materials for multi-surface glTF export."""

    def __init__(self) -> None:
        self.materials: List[bpy.types.Material] = []
        self._name_to_idx: Dict[str, int] = {}

    def add(
        self,
        name: str,
        base_color: Tuple[float, float, float, float],
        roughness: float = 0.85,
        metallic: float = 0.0,
        alpha: float = 1.0,
    ) -> int:
        if name in self._name_to_idx:
            return self._name_to_idx[name]

        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = base_color
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = metallic
            if alpha < 1.0 and "Alpha" in bsdf.inputs:
                bsdf.inputs["Alpha"].default_value = alpha
                if hasattr(mat, "blend_method"):
                    mat.blend_method = 'BLEND'

        idx = len(self.materials)
        self.materials.append(mat)
        self._name_to_idx[name] = idx
        return idx

    def idx(self, name: str) -> int:
        return self._name_to_idx[name]

    @classmethod
    def create_medieval_bergen_palette(cls) -> "MaterialPalette":
        """Standard 9-material palette matching BuildingAssembler's PBR surface resolver."""
        p = cls()
        p.add("wood_spruce",      (0.49, 0.35, 0.21, 1.0), roughness=0.82)
        p.add("wood_dark",        (0.24, 0.16, 0.10, 1.0), roughness=0.88)
        p.add("wood_weathered",   (0.38, 0.31, 0.24, 1.0), roughness=0.88)
        p.add("stone_foundation", (0.39, 0.38, 0.36, 1.0), roughness=0.92)
        p.add("sod_roof",         (0.25, 0.36, 0.17, 1.0), roughness=0.94)
        p.add("birch_bark",       (0.76, 0.70, 0.56, 1.0), roughness=0.78)
        p.add("iron_hardware",    (0.16, 0.16, 0.18, 1.0), roughness=0.52, metallic=0.85)
        p.add("window_glass",     (0.55, 0.68, 0.64, 0.52), roughness=0.18, metallic=0.10, alpha=0.52)
        p.add("shutter_wood",     (0.44, 0.22, 0.15, 1.0), roughness=0.84)
        return p


# ==============================================================================
# 3. PROCEDURAL BMESH PRIMITIVES (AUTHORED IN GODOT COORDINATES)
# ==============================================================================

def add_box(
    bm: bmesh.types.BMesh,
    center_g: Sequence[float],
    size_g: Sequence[float],
    mat_idx: int,
    rot_g: Optional[Matrix] = None,
    bevel_top: float = 0.0,
) -> List[bmesh.types.BMVert]:
    """
    Add a 3D box authored in Godot coordinates:
      center_g: (gx, gy, gz) center in Godot space
      size_g:   (sx, sy, sz) full dimensions along Godot X, Y, Z
      rot_g:    optional 3x3 Blender rotation matrix from g_rot_x/y/z or g_euler
      bevel_top: optional inset fraction (0.0 - 0.35) on the top (+Y) face
    """
    hx, hy, hz = float(size_g[0]) * 0.5, float(size_g[1]) * 0.5, float(size_g[2]) * 0.5
    top_scale = max(0.2, 1.0 - float(bevel_top))

    local_corners_g = [
        (-hx, -hy, -hz),
        ( hx, -hy, -hz),
        ( hx, -hy,  hz),
        (-hx, -hy,  hz),
        (-hx * top_scale,  hy, -hz * top_scale),
        ( hx * top_scale,  hy, -hz * top_scale),
        ( hx * top_scale,  hy,  hz * top_scale),
        (-hx * top_scale,  hy,  hz * top_scale),
    ]

    c_b = g_vec(center_g)
    verts: List[bmesh.types.BMVert] = []
    for lx, ly, lz in local_corners_g:
        v_b = g_pos(lx, ly, lz)
        if rot_g is not None:
            v_b = rot_g @ v_b
        verts.append(bm.verts.new(c_b + v_b))

    quads = [
        (0, 3, 2, 1),  # Bottom (-Y)
        (4, 5, 6, 7),  # Top (+Y)
        (0, 1, 5, 4),  # North (-Z)
        (2, 3, 7, 6),  # South (+Z)
        (1, 2, 6, 5),  # East (+X)
        (3, 0, 4, 7),  # West (-X)
    ]
    for q in quads:
        try:
            f = bm.faces.new((verts[q[0]], verts[q[1]], verts[q[2]], verts[q[3]]))
            f.material_index = mat_idx
        except ValueError:
            pass
    return verts


def add_cylinder_g(
    bm: bmesh.types.BMesh,
    base_center_g: Sequence[float],
    axis_dir_g: Sequence[float],
    length: float,
    radius_bottom: float,
    radius_top: Optional[float] = None,
    segments: int = 8,
    mat_idx: int = 0,
    cap_ends: bool = True,
) -> List[bmesh.types.BMVert]:
    """Add an oriented cylinder/frustum starting at `base_center_g` along `axis_dir_g` in Godot space."""
    if radius_top is None:
        radius_top = radius_bottom

    axis_b = g_vec(axis_dir_g).normalized()
    up_ref = Vector((0.0, 0.0, 1.0)) if abs(axis_b.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u_b = axis_b.cross(up_ref).normalized()
    v_b = axis_b.cross(u_b).normalized()

    p0_b = g_vec(base_center_g)
    p1_b = p0_b + axis_b * float(length)

    ring0: List[bmesh.types.BMVert] = []
    ring1: List[bmesh.types.BMVert] = []
    for i in range(segments):
        ang = (2.0 * math.pi * i) / float(segments)
        ca, sa = math.cos(ang), math.sin(ang)
        radial = u_b * ca + v_b * sa
        ring0.append(bm.verts.new(p0_b + radial * float(radius_bottom)))
        ring1.append(bm.verts.new(p1_b + radial * float(radius_top)))

    for i in range(segments):
        inext = (i + 1) % segments
        try:
            f = bm.faces.new((ring0[i], ring0[inext], ring1[inext], ring1[i]))
            f.material_index = mat_idx
        except ValueError:
            pass

    if cap_ends and segments >= 3:
        try:
            f0 = bm.faces.new(list(reversed(ring0)))
            f0.material_index = mat_idx
            f1 = bm.faces.new(ring1)
            f1.material_index = mat_idx
        except ValueError:
            pass

    return ring0 + ring1


def add_hewn_log(
    bm: bmesh.types.BMesh,
    start_g: Sequence[float],
    end_g: Sequence[float],
    radius: float,
    mat_idx: int,
    sections: int = 8,
    end_taper: float = 0.78,
    flat_ratio: float = 0.90,
    wobble_seed: float = 0.0,
) -> List[bmesh.types.BMVert]:
    """
    Add a hand-hewn octagonal timber log between `start_g` and `end_g` in Godot space,
    with broadaxe side flattening (`flat_ratio`), organic wobble, and beveled *laftehode* ends.
    """
    p0_b = g_vec(start_g)
    p1_b = g_vec(end_g)
    delta_b = p1_b - p0_b
    length = delta_b.length
    if length < 1e-4:
        return []

    axis_b = delta_b / length
    # In Blender space, +Z is Godot +Y (vertical up)
    up_b = Vector((0.0, 0.0, 1.0)) if abs(axis_b.z) < 0.92 else Vector((1.0, 0.0, 0.0))
    side_b = axis_b.cross(up_b).normalized()
    vert_b = side_b.cross(axis_b).normalized()

    rings: List[List[bmesh.types.BMVert]] = []
    for s in range(sections + 1):
        t = float(s) / float(sections)
        pos_b = p0_b.lerp(p1_b, t)
        if 0 < s < sections:
            wob = 0.008 * math.sin(t * math.pi * 2.0 + wobble_seed * 1.7)
            pos_b = pos_b + side_b * wob + vert_b * (wob * 0.5)

        taper = end_taper if (s == 0 or s == sections) else 1.0
        ring: List[bmesh.types.BMVert] = []
        for k in range(8):
            ang = (2.0 * math.pi * k) / 8.0 + (math.pi / 8.0)
            cs, sn = math.cos(ang), math.sin(ang)
            r_side = radius * taper * flat_ratio * cs
            r_vert = radius * taper * sn
            ring.append(bm.verts.new(pos_b + side_b * r_side + vert_b * r_vert))
        rings.append(ring)

    for s in range(sections):
        rA, rB = rings[s], rings[s + 1]
        for k in range(8):
            knext = (k + 1) % 8
            try:
                f = bm.faces.new((rA[k], rA[knext], rB[knext], rB[k]))
                f.material_index = mat_idx
            except ValueError:
                pass

    try:
        f_start = bm.faces.new(list(reversed(rings[0])))
        f_start.material_index = mat_idx
        f_end = bm.faces.new(rings[-1])
        f_end.material_index = mat_idx
    except ValueError:
        pass

    return [v for r in rings for v in r]


def add_fieldstone(
    bm: bmesh.types.BMesh,
    center_g: Sequence[float],
    radii_g: Sequence[float],
    mat_idx: int,
    seed: int = 1,
) -> None:
    """Add a faceted Bergen gneiss/slate fieldstone block with deterministic surface irregularity."""
    temp = bmesh.new()
    bmesh.ops.create_icosphere(temp, subdivisions=1, radius=1.0)
    rx, ry, rz = float(radii_g[0]), float(radii_g[1]), float(radii_g[2])
    c_b = g_vec(center_g)

    vmap = {}
    for i, v in enumerate(temp.verts):
        gx, gy, gz = v.co.x, v.co.z, -v.co.y
        n_val = 1.0 + 0.12 * math.sin(seed * 3.1 + i * 2.3) * math.cos(seed * 1.7 - i * 1.9)
        # Flatten top and bottom slightly so stones sit in stable courses
        gy_flat = max(-0.82, min(0.82, gy))
        p_b = g_pos(gx * rx * n_val, gy_flat * ry, gz * rz * n_val) + c_b
        vmap[v] = bm.verts.new(p_b)

    for f in temp.faces:
        try:
            nf = bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = mat_idx
        except ValueError:
            pass
    temp.free()


def apply_box_uvs(bm: bmesh.types.BMesh, uv_scale: float = 0.5) -> None:
    """Project triplanar world-scale UVs onto all faces in `bm` using Godot coordinates."""
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            gx, gy, gz = b_to_g_pos(loop.vert.co)
            if az >= ax and az >= ay:
                # Top/Bottom in Blender Z == Godot Y
                u, v = gx * uv_scale, gz * uv_scale
            elif ax >= ay and ax >= az:
                # East/West
                u, v = gz * uv_scale, gy * uv_scale
            else:
                # North/South
                u, v = gx * uv_scale, gy * uv_scale
            loop[uv_layer].uv = (u, v)


# ==============================================================================
# 4. GLTF 2.0 (.GLB) EXPORT & HIGH-POLY DECIMATION
# ==============================================================================

def export_glb(
    bm: bmesh.types.BMesh,
    name: str,
    out_dir: str,
    palette: MaterialPalette,
    smooth_shading: bool = False,
    uv_scale: float = 0.5,
) -> str:
    """
    Finalize a BMesh (weld close vertices, recalculate outward normals, project box UVs),
    bind all materials from `palette`, and export a binary `.glb` file to `out_dir/name.glb`.
    """
    os.makedirs(out_dir, exist_ok=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    apply_box_uvs(bm, uv_scale=uv_scale)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    for mat in palette.materials:
        mesh.materials.append(mat)

    for poly in mesh.polygons:
        poly.use_smooth = smooth_shading

    bpy.ops.object.select_all(action='DESELECT')
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    filepath = os.path.join(out_dir, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials='EXPORT',
        export_normals=True,
        export_texcoords=True,
    )
    size_kb = os.path.getsize(filepath) / 1024.0
    print(f"[blender_godot_kit] Exported {filepath} ({size_kb:.1f} KB, {len(mesh.polygons)} polys)")
    return filepath


def decimate_and_export_glb(
    input_glb_path: str,
    output_glb_path: str,
    target_tris: int = 800,
    ground_align: bool = True,
) -> str:
    """
    Load a high-poly raw `.glb` model, merge its mesh geometry, optionally align its base
    to `y_min = 0.0` in Godot space, decimate it to `target_tris`, and export a lightweight `.glb`.
    """
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=input_glb_path)

    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not mesh_objs:
        raise RuntimeError(f"No mesh objects found in {input_glb_path}")

    bpy.ops.object.select_all(action='DESELECT')
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    if len(mesh_objs) > 1:
        bpy.ops.object.join()

    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if ground_align and len(obj.data.vertices) > 0:
        min_z = min(v.co.z for v in obj.data.vertices)
        for v in obj.data.vertices:
            v.co.z -= min_z

    current_tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
    if current_tris > target_tris and current_tris > 0:
        ratio = max(0.01, min(1.0, float(target_tris) / float(current_tris)))
        mod = obj.modifiers.new(name="WebGL_Decimate", type='DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)

    os.makedirs(os.path.dirname(os.path.abspath(output_glb_path)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_glb_path,
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials='EXPORT',
        export_normals=True,
        export_texcoords=True,
    )
    final_tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
    size_kb = os.path.getsize(output_glb_path) / 1024.0
    print(
        f"[blender_godot_kit] Decimated {input_glb_path} ({current_tris} tris) -> "
        f"{output_glb_path} ({final_tris} tris, {size_kb:.1f} KB)"
    )
    return output_glb_path
