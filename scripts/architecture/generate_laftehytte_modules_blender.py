#!/usr/bin/env python3
"""
Blender Python (bpy) Modular 3D Asset Generator for Medieval Bergen 1360 Laftehytte (Årestue).

Builds authentic 14th-century Western Norwegian log cabin (Laftehytte) architectural modules
using Blender's bmesh geometry engine and exports WebGL-ready binary glTF 2.0 (.glb) assets
into `assets/modular_pieces/laftehytte/`.

Generated Modular Pieces:
  1. foundation_pier.glb         - Stacked Bergen gneiss/slate corner & bay stone pier (Grunnmurstein)
  2. foundation_plinth_4m.glb    - Dry-stone rubble skirt + tarred mudsill timber (Svillstokk)
  3. floor_plank_bay.glb         - Joists + chamfered wide hand-hewn spruce floorboards (Gulvbord)
  4. laft_log_4m.glb             - Single hand-hewn octagonal spruce log with saddle notches (Laftestokk)
  5. laft_wall_solid.glb         - 8-course interlocking notched log wall with corner heads (Lafteverk)
  6. laft_wall_window.glb        - 8-course notched log wall with mullioned window & iron-hinged shutters
  7. laft_wall_doorway.glb       - 8-course notched log wall with carved portal jambs, lintel & open door
  8. laft_gable_triangle.glb     - 6-course tapered triangular log gable with purlin notches (Gavlvegg)
  9. torvtak_roof_slope.glb      - Rafters (Sperrer), birch bark (Never), torvvol log, hooks & sod turf
 10. ljore_smoke_vent.glb        - Ridge beam, turf crest, crossed bargeboards (Vindski) & Ljore frame
 11. are_central_hearth.glb      - Raised dry-stone hearth ring (Åre), ash bed, char logs & iron trivet
 12. langbenk_sleeping_bench.glb - Interior spruce wall sleeping bench (Langbenk / Bris) with trestles
 13. stage_1_foundation.glb      - Complete 5.0m x 5.0m Stage 1 Foundation & Plank Floor
 14. stage_2_walls.glb           - Complete 5.0m x 5.0m Stage 2 Interlocking Log Walls, Windows & Door
 15. stage_3_roof.glb            - Complete 5.0m x 5.0m Stage 3 Gables, Rafters, Sod Roof & Ljore
 16. stage_4_hearth.glb          - Complete Stage 4 Central Åre Hearth & Langbenk Bench
"""

import os
import math
import bpy
import bmesh
from mathutils import Vector, Matrix, Euler


OUTPUT_DIR = os.path.join("assets", "modular_pieces", "laftehytte")


# ==============================================================================
# COORDINATE CONVERSION HELPERS (Godot Y-Up -> Blender Z-Up)
# ==============================================================================
# Blender's glTF exporter maps Blender (X, Y, Z) -> glTF/Godot (X, Z, -Y).
# Therefore, to place a point at Godot (gx, gy, gz), we place it in Blender at:
#   bx = gx
#   by = -gz
#   bz = gy

def g2b(gx: float, gy: float, gz: float) -> Vector:
    """Converts Godot (X_right, Y_up, Z_back) to Blender (X, Y, Z) pre-export coordinates."""
    return Vector((float(gx), float(-gz), float(gy)))


def g2b_vec(v) -> Vector:
    return Vector((float(v[0]), float(-v[2]), float(v[1])))


def godot_rot_matrix(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> Matrix:
    """
    Constructs a 3x3 rotation matrix in Godot space (YXZ Euler order matching Godot Node3D)
    and converts it to the equivalent basis in Blender space via M_blend = C * M_godot * C^-1.
    """
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)

    mx = Matrix(((1, 0, 0), (0, cx, -sx), (0, sx, cx)))
    my = Matrix(((cy, 0, sy), (0, 1, 0), (-sy, 0, cy)))
    mz = Matrix(((cz, -sz, 0), (sz, cz, 0), (0, 0, 1)))
    mg = my @ mx @ mz

    # Coordinate change matrix C: (gx, gy, gz) -> (gx, -gz, gy)
    c_mat = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    c_inv = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
    return (c_mat @ mg @ c_inv).to_4x4()


# ==============================================================================
# PBR MATERIAL PALETTE (Matching BuildingAssembler Material Keys)
# ==============================================================================

MATERIAL_SPECS = {
    "wood_spruce": {
        "color": (0.45, 0.30, 0.17, 1.0),
        "roughness": 0.86,
        "metallic": 0.0,
    },
    "wood_dark": {
        "color": (0.24, 0.16, 0.10, 1.0),
        "roughness": 0.90,
        "metallic": 0.0,
    },
    "wood_weathered": {
        "color": (0.38, 0.31, 0.24, 1.0),
        "roughness": 0.92,
        "metallic": 0.0,
    },
    "stone_foundation": {
        "color": (0.46, 0.45, 0.43, 1.0),
        "roughness": 0.93,
        "metallic": 0.0,
    },
    "sod_roof": {
        "color": (0.24, 0.42, 0.17, 1.0),
        "roughness": 0.95,
        "metallic": 0.0,
    },
    "birch_bark": {
        "color": (0.86, 0.82, 0.73, 1.0),
        "roughness": 0.78,
        "metallic": 0.0,
    },
    "iron_hardware": {
        "color": (0.15, 0.15, 0.17, 1.0),
        "roughness": 0.45,
        "metallic": 0.65,
    },
    "window_glass": {
        "color": (0.52, 0.64, 0.58, 1.0),
        "roughness": 0.22,
        "metallic": 0.25,
        "emission": (0.42, 0.34, 0.18, 1.0),
        "emission_strength": 0.35,
    },
    "shutter_wood": {
        "color": (0.32, 0.22, 0.14, 1.0),
        "roughness": 0.85,
        "metallic": 0.0,
    },
}


class ModuleBuilder:
    """Accumulates bmesh geometry across named material slots and exports a clean single-mesh .glb."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")
        self.mat_keys = []
        self.mat_map = {}

    def _get_mat_index(self, mat_key: str) -> int:
        if mat_key not in self.mat_map:
            idx = len(self.mat_keys)
            self.mat_keys.append(mat_key)
            self.mat_map[mat_key] = idx
        return self.mat_map[mat_key]

    def _assign_mat_and_box_uv(self, faces, mat_idx: int):
        for f in faces:
            f.material_index = mat_idx
            f.smooth = False
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for loop in f.loops:
                co = loop.vert.co
                if az >= ax and az >= ay:
                    u, v = co.x * 0.5, co.y * 0.5
                elif ax >= ay:
                    u, v = co.y * 0.5, co.z * 0.5
                else:
                    u, v = co.x * 0.5, co.z * 0.5
                loop[self.uv_layer].uv = (u, v)

    def add_box(
        self,
        mat_key: str,
        size: tuple,
        pos: tuple,
        rot: tuple = (0.0, 0.0, 0.0),
        chamfer: float = 0.0,
    ):
        """Adds an oriented box in Godot coordinates (width_x, height_y, depth_z)."""
        mat_idx = self._get_mat_index(mat_key)
        sx, sy, sz = float(size[0]), float(size[1]), float(size[2])

        temp_bm = bmesh.new()
        bmesh.ops.create_cube(temp_bm, size=1.0)
        # Scale in Godot->Blender mapping: X -> sx, Y -> sz, Z -> sy
        bmesh.ops.scale(temp_bm, vec=Vector((sx, sz, sy)), verts=temp_bm.verts)

        if chamfer > 0.001:
            bmesh.ops.bevel(
                temp_bm,
                geom=list(temp_bm.edges),
                offset=min(chamfer, min(sx, sy, sz) * 0.28),
                segments=1,
                profile=0.5,
                affect='EDGES',
            )

        rot_m = godot_rot_matrix(rot[0], rot[1], rot[2])
        bmesh.ops.transform(
            temp_bm,
            matrix=Matrix.Translation(g2b(*pos)) @ rot_m,
            verts=temp_bm.verts,
        )

        self._merge_temp_bm(temp_bm, mat_idx)

    def add_hewn_log(
        self,
        mat_key: str,
        length: float,
        height: float,
        thickness: float,
        pos: tuple,
        yaw: float = 0.0,
        has_left_notch: bool = False,
        has_right_notch: bool = False,
        notch_offset: float = 0.30,
    ):
        """
        Builds a genuine hand-hewn octagonal Norwegian Lafteverk log (Medfar profile)
        along local X, with optional saddle notches (Lafteknute) and beveled end-grain.
        """
        mat_idx = self._get_mat_index(mat_key)
        dark_idx = self._get_mat_index("wood_dark")

        temp_bm = bmesh.new()
        hx = length * 0.5
        hy = height * 0.5
        hz = thickness * 0.5

        # 8-vertex hand-hewn oval-octagonal cross section in Godot (Y, Z) -> Blender (Z, -Y)
        profile_yz = [
            (hy * 0.96, -hz * 0.58),
            (hy * 0.55, -hz * 1.00),
            (-hy * 0.55, -hz * 1.00),
            (-hy * 0.96, -hz * 0.58),
            (-hy * 0.96, hz * 0.58),
            (-hy * 0.55, hz * 1.00),
            (hy * 0.55, hz * 1.00),
            (hy * 0.96, hz * 0.58),
        ]

        # Longitudinal X stations so we can pinch the saddle notches (Nov) near corners
        x_stations = [-hx]
        if has_left_notch and hx > notch_offset + 0.18:
            n_x = -hx + notch_offset
            x_stations.extend([n_x - 0.11, n_x, n_x + 0.11])
        if has_right_notch and hx > notch_offset + 0.18:
            n_x = hx - notch_offset
            x_stations.extend([n_x - 0.11, n_x, n_x + 0.11])
        x_stations.append(hx)

        rings = []
        for si, x_val in enumerate(x_stations):
            is_end = (si == 0 or si == len(x_stations) - 1)
            is_notch_center = False
            if has_left_notch and abs(x_val - (-hx + notch_offset)) < 0.01:
                is_notch_center = True
            if has_right_notch and abs(x_val - (hx - notch_offset)) < 0.01:
                is_notch_center = True

            scale_y = 0.88 if is_end else (0.76 if is_notch_center else 1.0)
            scale_z = 0.88 if is_end else (0.84 if is_notch_center else 1.0)

            ring_verts = []
            for py, pz in profile_yz:
                v = temp_bm.verts.new(g2b(x_val, py * scale_y, pz * scale_z))
                ring_verts.append(v)
            rings.append((ring_verts, is_notch_center))

        # Bridge consecutive rings
        for r_idx in range(len(rings) - 1):
            r0, n0 = rings[r_idx]
            r1, n1 = rings[r_idx + 1]
            ring_mat = dark_idx if (n0 or n1) else mat_idx
            n_pts = len(r0)
            for i in range(n_pts):
                inext = (i + 1) % n_pts
                f = temp_bm.faces.new((r0[i], r1[i], r1[inext], r0[inext]))
                f.material_index = ring_mat

        # End caps (dark weathered end-grain on Laftehode)
        f_left = temp_bm.faces.new(list(reversed(rings[0][0])))
        f_left.material_index = dark_idx
        f_right = temp_bm.faces.new(rings[-1][0])
        f_right.material_index = dark_idx

        bmesh.ops.recalc_face_normals(temp_bm, faces=temp_bm.faces)

        rot_m = godot_rot_matrix(0.0, yaw, 0.0)
        bmesh.ops.transform(
            temp_bm,
            matrix=Matrix.Translation(g2b(*pos)) @ rot_m,
            verts=temp_bm.verts,
        )

        self._merge_temp_bm_preserve_mats(temp_bm)

    def add_cylinder(
        self,
        mat_key: str,
        top_r: float,
        bot_r: float,
        height: float,
        pos: tuple,
        rot: tuple = (0.0, 0.0, 0.0),
        segments: int = 8,
    ):
        """Adds a tapered cylinder in Godot coordinates (axis along Godot Y-up before rotation)."""
        mat_idx = self._get_mat_index(mat_key)
        temp_bm = bmesh.new()
        bmesh.ops.create_cone(
            temp_bm,
            cap_ends=True,
            cap_tris=False,
            segments=segments,
            radius1=bot_r,
            radius2=top_r,
            depth=height,
        )
        bmesh.ops.recalc_face_normals(temp_bm, faces=temp_bm.faces)

        rot_m = godot_rot_matrix(rot[0], rot[1], rot[2])
        bmesh.ops.transform(
            temp_bm,
            matrix=Matrix.Translation(g2b(*pos)) @ rot_m,
            verts=temp_bm.verts,
        )
        self._merge_temp_bm(temp_bm, mat_idx)

    def _merge_temp_bm(self, temp_bm: bmesh.types.BMesh, mat_idx: int):
        bmesh.ops.recalc_face_normals(temp_bm, faces=temp_bm.faces)
        vert_map = {}
        for v in temp_bm.verts:
            vert_map[v] = self.bm.verts.new(v.co)
        new_faces = []
        for f in temp_bm.faces:
            try:
                nf = self.bm.faces.new([vert_map[v] for v in f.verts])
                new_faces.append(nf)
            except ValueError:
                pass
        self._assign_mat_and_box_uv(new_faces, mat_idx)
        temp_bm.free()

    def _merge_temp_bm_preserve_mats(self, temp_bm: bmesh.types.BMesh):
        vert_map = {}
        for v in temp_bm.verts:
            vert_map[v] = self.bm.verts.new(v.co)
        for f in temp_bm.faces:
            try:
                nf = self.bm.faces.new([vert_map[v] for v in f.verts])
                self._assign_mat_and_box_uv([nf], f.material_index)
            except ValueError:
                pass
        temp_bm.free()

    def export_glb(self, filepath: str) -> dict:
        """Converts accumulated bmesh into a Blender Object with Principled BSDF materials and exports .glb."""
        bpy.ops.wm.read_factory_settings(use_empty=True)

        bmesh.ops.triangulate(self.bm, faces=self.bm.faces)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)

        mesh_data = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh_data)
        self.bm.free()

        obj = bpy.data.objects.new(self.name, mesh_data)
        bpy.context.collection.objects.link(obj)

        for mat_key in self.mat_keys:
            spec = MATERIAL_SPECS.get(mat_key, MATERIAL_SPECS["wood_spruce"])
            mat = bpy.data.materials.new(name=mat_key)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = spec["color"]
                bsdf.inputs["Roughness"].default_value = spec["roughness"]
                bsdf.inputs["Metallic"].default_value = spec["metallic"]
                if "emission" in spec and "Emission Color" in bsdf.inputs:
                    bsdf.inputs["Emission Color"].default_value = spec["emission"]
                    bsdf.inputs["Emission Strength"].default_value = spec.get("emission_strength", 0.35)
            mesh_data.materials.append(mat)

        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=filepath,
            export_format='GLB',
            export_apply=True,
            export_yup=True,
            export_materials='EXPORT',
        )

        stats = {
            "name": self.name,
            "filepath": filepath,
            "verts": len(mesh_data.vertices),
            "tris": len(mesh_data.polygons),
            "materials": list(self.mat_keys),
            "bytes": os.path.getsize(filepath),
        }
        return stats


# ==============================================================================
# ARCHITECTURAL COMPONENT HELPERS (Shared across atomic & stage modules)
# ==============================================================================

def build_foundation_pier_geom(mb: ModuleBuilder, center_xz: tuple = (0.0, 0.0), pier_depth_below: float = 0.45):
    """Stacked Bergen slate/gneiss foundation pier (Grunnmurstein) with 3 chamfered stone courses."""
    cx, cz = center_xz
    total_h = pier_depth_below + 0.18
    # Bottom broad footing boulder
    mb.add_box("stone_foundation", (0.64, total_h * 0.45, 0.64), (cx, -pier_depth_below + total_h * 0.22, cz), chamfer=0.04)
    # Middle flat slate stone
    mb.add_box("stone_foundation", (0.58, total_h * 0.35, 0.58), (cx, -pier_depth_below + total_h * 0.60, cz), rot=(0, 0.08, 0), chamfer=0.03)
    # Top leveled cap stone supporting the svillstokk
    mb.add_box("stone_foundation", (0.54, total_h * 0.24, 0.54), (cx, 0.08, cz), chamfer=0.025)


def build_foundation_plinth_geom(mb: ModuleBuilder, span: float = 4.0, center: tuple = (0.0, 0.0, 0.0), yaw: float = 0.0):
    """Dry-stone rubble skirt + heavy tarred timber mudsill (Svillstokk) along wall axis."""
    cx, cy, cz = center
    basis_x = (math.cos(yaw), 0.0, -math.sin(yaw))

    def local_pt(lx: float, ly: float, lz: float):
        return (
            cx + lx * basis_x[0] + lz * math.sin(yaw),
            cy + ly,
            cz + lx * basis_x[2] + lz * math.cos(yaw),
        )

    # Recessed dry-stone rubble plinth courses
    mb.add_box("stone_foundation", (span - 0.16, 0.32, 0.38), local_pt(0, -0.22, 0), rot=(0, yaw, 0), chamfer=0.03)
    mb.add_box("stone_foundation", (span - 0.12, 0.22, 0.34), local_pt(0, 0.02, 0), rot=(0, yaw, 0), chamfer=0.025)

    # Heavy tarred mudsill beam (Svillstokk) with chamfered top shoulders
    mb.add_box("wood_dark", (span + 0.18, 0.18, 0.28), local_pt(0, 0.10, 0), rot=(0, yaw, 0), chamfer=0.02)


def build_floor_plank_bay_geom(mb: ModuleBuilder, width: float = 4.0, depth: float = 4.0, y_top: float = 0.10):
    """Sub-floor transverse joists (Gulvbjelker) + individual chamfered spruce floorboards (Gulvbord)."""
    half_w = width * 0.5
    half_d = depth * 0.5

    # 3 transverse floor joists underneath
    for jz_frac in [-0.36, 0.0, 0.36]:
        mb.add_box("wood_dark", (width - 0.24, 0.10, 0.14), (0.0, y_top - 0.08, jz_frac * depth), chamfer=0.01)

    # Individual wide hand-planed floorboards with plank gaps and beveled edges
    plank_count = max(6, int(round(width / 0.42)))
    inner_w = width - 0.24
    plank_w = inner_w / float(plank_count)
    for p in range(plank_count):
        px = -inner_w * 0.5 + (float(p) + 0.5) * plank_w
        y_var = 0.003 if (p % 2 == 0) else 0.0
        mb.add_box(
            "wood_weathered",
            (plank_w * 0.94, 0.07, depth - 0.24),
            (px, y_top - 0.035 + y_var, 0.0),
            chamfer=0.008,
        )


def build_door_assembly_geom(
    mb: ModuleBuilder,
    center_bottom: tuple,
    wall_yaw: float = 0.0,
    door_w: float = 1.12,
    door_h: float = 1.95,
    wall_thick: float = 0.32,
    is_open: bool = True,
):
    """Carved Norwegian portal doorway (Dørstolper, Dørbislag, stepped threshold & iron-hinged plank door)."""
    cx, cy, cz = center_bottom
    rx, rz = math.cos(wall_yaw), -math.sin(wall_yaw)
    fx, fz = math.sin(wall_yaw), -math.cos(wall_yaw)  # Outward normal (-Z when yaw=0)

    def pt(right_off: float, up_off: float, fwd_off: float):
        return (
            cx + right_off * rx + fwd_off * fx,
            cy + up_off,
            cz + right_off * rz + fwd_off * fz,
        )

    # 1. Low-profile stepped slate welcome stone & oak sill (<= 0.10m high for smooth walking)
    mb.add_box("stone_foundation", (door_w + 0.36, 0.09, 0.48), pt(0.0, 0.045, 0.22), rot=(0, wall_yaw, 0), chamfer=0.02)
    mb.add_box("wood_dark", (door_w + 0.18, 0.07, wall_thick + 0.08), pt(0.0, 0.035, 0.0), rot=(0, wall_yaw, 0), chamfer=0.01)

    # 2. Heavy carved portal jamb posts (Dørstolper) with medieval capital molding
    jamb_w = 0.16
    for sign_x in (-1.0, 1.0):
        jx = sign_x * (door_w * 0.5 + jamb_w * 0.45)
        mb.add_box("wood_dark", (jamb_w, door_h + 0.06, wall_thick + 0.10), pt(jx, door_h * 0.5, 0.0), rot=(0, wall_yaw, 0), chamfer=0.02)
        # Decorative carved portal capital block near top of jamb
        mb.add_box("wood_dark", (jamb_w + 0.04, 0.16, wall_thick + 0.14), pt(jx, door_h - 0.14, 0.02), rot=(0, wall_yaw, 0), chamfer=0.015)

    # 3. Overhead carved lintel beam & sloped rain hood (Dørbislag)
    lintel_h = 0.22
    mb.add_box("wood_dark", (door_w + jamb_w * 2.5, lintel_h, wall_thick + 0.12), pt(0.0, door_h + lintel_h * 0.5, 0.0), rot=(0, wall_yaw, 0), chamfer=0.02)
    mb.add_box("wood_dark", (door_w + 0.46, 0.07, 0.34), pt(0.0, door_h + lintel_h + 0.05, wall_thick * 0.5 + 0.14), rot=(math.radians(18.0), wall_yaw, 0), chamfer=0.01)

    # 4. Planked Door Leaf (Dørblad) with 4 chamfered boards, rear Z-battens & wrought-iron strap hinges
    leaf_w = door_w - 0.06
    leaf_h = door_h - 0.08
    hinge_origin = pt(-leaf_w * 0.5, 0.06, wall_thick * 0.38)
    leaf_yaw = wall_yaw + (math.radians(82.0) if is_open else 0.0)
    lrx, lrz = math.cos(leaf_yaw), -math.sin(leaf_yaw)
    lfx, lfz = math.sin(leaf_yaw), -math.cos(leaf_yaw)

    def lpt(r_off: float, u_off: float, f_off: float):
        return (
            hinge_origin[0] + r_off * lrx + f_off * lfx,
            hinge_origin[1] + u_off,
            hinge_origin[2] + r_off * lrz + f_off * lfz,
        )

    board_count = 4
    board_w = leaf_w / float(board_count)
    for b in range(board_count):
        bx = (float(b) + 0.5) * board_w
        mb.add_box("shutter_wood", (board_w * 0.94, leaf_h, 0.065), lpt(bx, leaf_h * 0.5, 0.0), rot=(0, leaf_yaw, 0), chamfer=0.008)

    for by_frac in (0.24, 0.76):
        # Rear horizontal timber batten
        mb.add_box("wood_dark", (leaf_w * 0.92, 0.11, 0.04), lpt(leaf_w * 0.5, leaf_h * by_frac, -0.045), rot=(0, leaf_yaw, 0), chamfer=0.006)
        # Wrought-iron strap hinge (Jernbeslag) + decorative spear tip on outer face
        mb.add_box("iron_hardware", (leaf_w * 0.64, 0.055, 0.02), lpt(leaf_w * 0.34, leaf_h * by_frac, 0.04), rot=(0, leaf_yaw, 0), chamfer=0.004)
        mb.add_box("iron_hardware", (0.09, 0.09, 0.022), lpt(leaf_w * 0.66, leaf_h * by_frac, 0.04), rot=(0, leaf_yaw, math.radians(45.0)))

    # Diagonal Z-brace between rear battens
    mb.add_box("wood_dark", (leaf_w * 0.82, 0.09, 0.035), lpt(leaf_w * 0.5, leaf_h * 0.50, -0.042), rot=(0, leaf_yaw, math.radians(28.0)), chamfer=0.005)

    # Iron latch plate & ring pull
    mb.add_box("iron_hardware", (0.08, 0.16, 0.04), lpt(leaf_w * 0.84, leaf_h * 0.48, 0.05), rot=(0, leaf_yaw, 0), chamfer=0.005)


def build_window_assembly_geom(
    mb: ModuleBuilder,
    center_pos: tuple,
    wall_yaw: float = 0.0,
    win_w: float = 0.86,
    win_h: float = 0.82,
    wall_thick: float = 0.32,
    has_glass: bool = True,
    has_shutters: bool = True,
):
    """Recessed medieval timber window frame, sill, crossbar mullions, crown glass & open shutters."""
    cx, cy, cz = center_pos
    rx, rz = math.cos(wall_yaw), -math.sin(wall_yaw)
    fx, fz = math.sin(wall_yaw), -math.cos(wall_yaw)

    def pt(r_off: float, u_off: float, f_off: float):
        return (
            cx + r_off * rx + f_off * fx,
            cy + u_off,
            cz + r_off * rz + f_off * fz,
        )

    # Sill (Vindusbrett) & top weather cap
    mb.add_box("wood_dark", (win_w + 0.24, 0.09, wall_thick + 0.14), pt(0.0, -win_h * 0.5 - 0.045, 0.04), rot=(0, wall_yaw, 0), chamfer=0.012)
    mb.add_box("wood_dark", (win_w + 0.26, 0.11, wall_thick + 0.12), pt(0.0, win_h * 0.5 + 0.055, 0.03), rot=(0, wall_yaw, 0), chamfer=0.012)

    # Left & right jambs (Vinduskarm)
    for sign_x in (-1.0, 1.0):
        mb.add_box("wood_dark", (0.11, win_h, wall_thick + 0.08), pt(sign_x * (win_w * 0.5 + 0.05), 0.0, 0.0), rot=(0, wall_yaw, 0), chamfer=0.01)

    # Crown glass pane & wooden crossbar mullions (Sprosse)
    glass_mat = "window_glass" if has_glass else "wood_dark"
    mb.add_box(glass_mat, (win_w - 0.04, win_h - 0.04, 0.05), pt(0.0, 0.0, 0.0), rot=(0, wall_yaw, 0))
    mb.add_box("wood_dark", (0.048, win_h - 0.02, 0.09), pt(0.0, 0.0, 0.02), rot=(0, wall_yaw, 0), chamfer=0.005)
    mb.add_box("wood_dark", (win_w - 0.02, 0.048, 0.09), pt(0.0, 0.0, 0.02), rot=(0, wall_yaw, 0), chamfer=0.005)

    # Hinged wooden storm shutters (Vinduslemmer) with wrought-iron straps
    if has_shutters:
        shut_w = win_w * 0.48
        shut_h = win_h * 0.96
        for sign_x in (-1.0, 1.0):
            shut_yaw = wall_yaw - sign_x * math.radians(18.0)
            sx_off = sign_x * (win_w * 0.5 + shut_w * 0.5 + 0.07)
            s_pos = pt(sx_off, 0.0, wall_thick * 0.5 + 0.04)
            mb.add_box("shutter_wood", (shut_w, shut_h, 0.045), s_pos, rot=(0, shut_yaw, 0), chamfer=0.006)
            for hy in (-0.30, 0.30):
                h_pos = pt(sx_off, win_h * hy, wall_thick * 0.5 + 0.068)
                mb.add_box("iron_hardware", (shut_w * 0.78, 0.04, 0.015), h_pos, rot=(0, shut_yaw, 0))


def build_lafteverk_wall_courses_geom(
    mb: ModuleBuilder,
    wall_center_bottom: tuple,
    wall_span: float,
    wall_h: float,
    wall_yaw: float = 0.0,
    log_courses: int = 8,
    wall_thick: float = 0.32,
    nov_overhang: float = 0.30,
    apertures: list = None,
):
    """
    Constructs interlocking horizontal hand-hewn octagonal spruce log courses (Lafteverk)
    with corner saddle notches (Lafteknute), moss chinking seams (Mosefar), and aperture cuts.
    """
    if apertures is None:
        apertures = []

    cx, cy, cz = wall_center_bottom
    rx, rz = math.cos(wall_yaw), -math.sin(wall_yaw)
    course_h = wall_h / float(log_courses)
    total_span = wall_span + nov_overhang * 2.0
    half_span = total_span * 0.5

    for c in range(log_courses):
        cur_y = cy + (float(c) + 0.5) * course_h
        c_bot = float(c) * course_h
        c_top = float(c + 1) * course_h

        cuts = []
        for ap in apertures:
            ap_ymin = ap.get("y_min", 0.0)
            ap_ymax = ap.get("y_max", 2.0)
            if c_top > ap_ymin + 0.02 and c_bot < ap_ymax - 0.02:
                ap_x = ap.get("x", 0.0)
                ap_hw = ap.get("w", 1.0) * 0.5
                cuts.append((ap_x - ap_hw, ap_x + ap_hw))

        cuts.sort(key=lambda pair: pair[0])

        seg_start = -half_span
        segments = []
        for cut_l, cut_r in cuts:
            if cut_l > seg_start + 0.08:
                segments.append((seg_start, cut_l))
            seg_start = max(seg_start, cut_r)
        if half_span > seg_start + 0.08:
            segments.append((seg_start, half_span))

        for s_left, s_right in segments:
            seg_len = s_right - s_left
            seg_mid = (s_left + s_right) * 0.5
            lx = cx + seg_mid * rx
            lz = cz + seg_mid * rz

            has_l_notch = abs(s_left - (-half_span)) < 0.02
            has_r_notch = abs(s_right - half_span) < 0.02

            mb.add_hewn_log(
                "wood_spruce",
                seg_len,
                course_h * 0.94,
                wall_thick,
                (lx, cur_y, lz),
                yaw=wall_yaw,
                has_left_notch=has_l_notch,
                has_right_notch=has_r_notch,
                notch_offset=nov_overhang,
            )

            # Dark moss/tar chinking seam tucked between courses
            if seg_len > 0.24:
                mb.add_box(
                    "wood_dark",
                    (seg_len - 0.14, course_h * 0.12, wall_thick * 0.78),
                    (lx, cur_y - course_h * 0.46, lz),
                    rot=(0, wall_yaw, 0),
                )


def build_gable_triangle_geom(
    mb: ModuleBuilder,
    center_base: tuple,
    width: float = 5.0,
    gable_h: float = 1.40,
    wall_thick: float = 0.32,
    nov_overhang: float = 0.30,
    yaw: float = 0.0,
    gable_courses: int = 6,
):
    """6-course tapered triangular log gable (Gavlvegg) with purlin notches & breather vent."""
    cx, cy, cz = center_base
    step_h = gable_h / float(gable_courses)
    for g in range(gable_courses):
        frac = (float(g) + 0.5) / float(gable_courses)
        cur_w = (width + nov_overhang * 1.5) * (1.0 - frac * 0.88)
        gy = cy + (float(g) + 0.5) * step_h
        mb.add_hewn_log(
            "wood_spruce",
            cur_w,
            step_h * 0.95,
            wall_thick,
            (cx, gy, cz),
            yaw=yaw,
            has_left_notch=(g < 2),
            has_right_notch=(g < 2),
            notch_offset=0.22,
        )
        # Purlin cross-beam ends projecting slightly from gable face
        if g == 2:
            rx, rz = math.cos(yaw), -math.sin(yaw)
            for sign_x in (-1.0, 1.0):
                px = cx + sign_x * (width * 0.26) * rx
                pz = cz + sign_x * (width * 0.26) * rz
                mb.add_box("wood_dark", (0.20, 0.20, wall_thick + 0.18), (px, gy, pz), rot=(0, yaw, 0), chamfer=0.02)


def build_roof_slope_geom(
    mb: ModuleBuilder,
    width: float = 5.0,
    depth: float = 5.0,
    wall_h: float = 2.28,
    gable_h: float = 1.40,
    side_sign: float = -1.0,
):
    """
    Builds one side of a traditional Norwegian Torvtak (Sod Roof):
    - Side purlin (Ås)
    - Exposed spruce rafters (Sperrer)
    - White birch bark waterproof sheets (Never)
    - Eaves retaining log (Torvvol) + carved wooden hook brackets (Torvhald)
    - Stepped overlapping grassy sod turf courses (Torv)
    """
    half_w = width * 0.5
    half_d = depth * 0.5
    eaves_overhang_x = 0.48
    eaves_overhang_z = 0.45
    roof_len = depth + eaves_overhang_z * 2.0
    run_x = half_w + eaves_overhang_x
    rise_y = gable_h + 0.18
    slope_len = math.sqrt(run_x * run_x + rise_y * rise_y)
    pitch_rad = math.atan2(rise_y, run_x)

    # 1. Side Purlin (Ås)
    mb.add_box(
        "wood_dark",
        (0.18, 0.18, roof_len + 0.20),
        (side_sign * (half_w * 0.52), wall_h + gable_h * 0.50, 0.0),
        chamfer=0.015,
    )

    # 2. Individual Exposed Rafters (Sperrer)
    rafter_count = max(5, int(round(depth / 1.10)) + 1)
    for r in range(rafter_count):
        rz = -half_d - eaves_overhang_z * 0.6 + float(r) / float(rafter_count - 1) * (depth + eaves_overhang_z * 1.2)
        r_pos = (side_sign * (run_x * 0.5), wall_h + rise_y * 0.46, rz)
        mb.add_box(
            "wood_spruce",
            (slope_len + 0.16, 0.13, 0.12),
            r_pos,
            rot=(0.0, 0.0, -side_sign * pitch_rad),
            chamfer=0.012,
        )

    # 3. White Birch Bark Underlayment Deck (Never)
    deck_pos = (side_sign * (run_x * 0.5), wall_h + rise_y * 0.52, 0.0)
    mb.add_box(
        "birch_bark",
        (slope_len + 0.08, 0.06, roof_len),
        deck_pos,
        rot=(0.0, 0.0, -side_sign * pitch_rad),
    )

    # 4. Stepped Living Sod Turf Courses (Torvtak)
    course_rows = 5
    row_span = slope_len / float(course_rows)
    for c in range(course_rows):
        t_frac = (float(c) + 0.5) / float(course_rows)
        cx = side_sign * (t_frac * run_x)
        cy = wall_h + rise_y * (1.0 - t_frac) + 0.10
        mb.add_box(
            "sod_roof",
            (row_span * 1.08, 0.22, roof_len - 0.04),
            (cx, cy, 0.0),
            rot=(0.0, 0.0, -side_sign * (pitch_rad - math.radians(1.5))),
            chamfer=0.03,
        )

    # 5. Eaves Retaining Log (Torvvol), Birch Bark Drip Edge & Wooden Hook Brackets (Torvhald)
    eaves_x = side_sign * (run_x - 0.06)
    eaves_y = wall_h - 0.02
    mb.add_box("wood_dark", (0.18, 0.18, roof_len + 0.14), (eaves_x, eaves_y + 0.12, 0.0), chamfer=0.025)
    mb.add_box("birch_bark", (0.09, 0.07, roof_len + 0.08), (eaves_x + side_sign * 0.05, eaves_y, 0.0))
    for hk in range(5):
        hz = -half_d + (float(hk) + 0.5) * (depth / 5.0)
        mb.add_box("wood_dark", (0.30, 0.10, 0.09), (eaves_x, eaves_y + 0.06, hz), chamfer=0.01)


def build_ljore_and_bargeboards_geom(
    mb: ModuleBuilder,
    width: float = 5.0,
    depth: float = 5.0,
    wall_h: float = 2.28,
    gable_h: float = 1.40,
    has_ljore: bool = True,
):
    """Ridge beam (Mønsås), turf ridge crest (Mønskam), crossed bargeboards (Vindski) & Ljore smoke vent."""
    half_w = width * 0.5
    eaves_overhang_x = 0.48
    eaves_overhang_z = 0.45
    roof_len = depth + eaves_overhang_z * 2.0
    run_x = half_w + eaves_overhang_x
    rise_y = gable_h + 0.18
    slope_len = math.sqrt(run_x * run_x + rise_y * rise_y)
    pitch_rad = math.atan2(rise_y, run_x)
    ridge_y = wall_h + gable_h

    # Central Ridge Beam (Mønsås)
    mb.add_box("wood_dark", (0.28, 0.28, roof_len + 0.36), (0.0, ridge_y + 0.04, 0.0), chamfer=0.025)

    # Sod Ridge Crest Cap (Mønskam)
    mb.add_box("sod_roof", (0.48, 0.21, roof_len + 0.04), (0.0, wall_h + rise_y + 0.12, 0.0), chamfer=0.035)

    # Gable Bargeboards (Vindski) with crossed peak finials (Vindskikors)
    for sign_z in (-1.0, 1.0):
        gz = sign_z * (roof_len * 0.5)
        for sign_x in (-1.0, 1.0):
            b_pos = (sign_x * (run_x * 0.5), wall_h + rise_y * 0.54, gz)
            mb.add_box(
                "wood_dark",
                (slope_len + 0.32, 0.22, 0.08),
                b_pos,
                rot=(0.0, 0.0, -sign_x * pitch_rad),
                chamfer=0.015,
            )

    # Rooftop Smoke Vent Frame (Ljore) with raised wooden coaming & vent pole
    if has_ljore:
        lj_y = ridge_y + 0.24
        lj_z = 0.15
        for side_s in (-1.0, 1.0):
            mb.add_box("wood_dark", (0.92, 0.26, 0.12), (0.0, lj_y, lj_z + side_s * 0.40), chamfer=0.015)
            mb.add_box("wood_dark", (0.12, 0.26, 0.68), (side_s * 0.40, lj_y, lj_z), chamfer=0.015)
        # Tilted wooden smoke-vent cover (Ljorelem) & control pole
        mb.add_box("shutter_wood", (0.88, 0.05, 0.88), (0.0, lj_y + 0.22, lj_z), rot=(math.radians(16.0), 0, 0), chamfer=0.01)


def build_are_hearth_geom(mb: ModuleBuilder, center: tuple = (0.0, 0.0, 0.0)):
    """Authentic Bergen 1360 central stone fireplace (Åre) with 12 curb stones, char logs & iron trivet."""
    cx, cy, cz = center

    # Inner dark ash & compacted earth bed
    mb.add_box("wood_dark", (1.16, 0.12, 1.16), (cx, cy + 0.06, cz), chamfer=0.02)

    # Perimeter ring of 12 dressed Bergen slate/gneiss hearth curb stones
    ring_r = 0.58
    for i in range(12):
        angle = float(i) * (2.0 * math.pi / 12.0)
        sx = cx + math.cos(angle) * ring_r
        sz = cz + math.sin(angle) * ring_r
        mb.add_box(
            "stone_foundation",
            (0.36, 0.24, 0.26),
            (sx, cy + 0.12, sz),
            rot=(0.0, -angle + math.pi * 0.5, 0.0),
            chamfer=0.03,
        )

    # Crossed charwood logs in center of firepit
    mb.add_cylinder("wood_dark", 0.07, 0.08, 0.72, (cx, cy + 0.18, cz), rot=(0, math.radians(25.0), math.radians(82.0)), segments=7)
    mb.add_cylinder("wood_dark", 0.07, 0.08, 0.72, (cx, cy + 0.20, cz), rot=(0, math.radians(-55.0), math.radians(80.0)), segments=7)

    # Wrought-iron hearth A-frame kettle trivet over the fire
    for sign_x in (-1.0, 1.0):
        mb.add_box("iron_hardware", (0.04, 0.62, 0.04), (cx + sign_x * 0.42, cy + 0.40, cz), rot=(0, 0, -sign_x * math.radians(12.0)))
    mb.add_box("iron_hardware", (0.76, 0.04, 0.04), (cx, cy + 0.68, cz))
    # Iron pot hook hanging from crossbar
    mb.add_box("iron_hardware", (0.03, 0.22, 0.03), (cx, cy + 0.56, cz))


def build_langbenk_geom(mb: ModuleBuilder, center: tuple = (0.0, 0.0, 0.0), length: float = 3.0):
    """Interior spruce wall sleeping bench (Langbenk / Bris) with carved trestle legs & planked seat."""
    cx, cy, cz = center
    bench_w = 0.76
    bench_h = 0.44

    # 3 Heavy carved trestle leg supports
    for z_frac in (-0.42, 0.0, 0.42):
        lz = cz + z_frac * length
        mb.add_box("wood_dark", (bench_w - 0.06, bench_h - 0.05, 0.10), (cx, cy + (bench_h - 0.05) * 0.5, lz), chamfer=0.015)

    # Front apron rail
    mb.add_box("wood_dark", (0.06, 0.14, length - 0.08), (cx - bench_w * 0.42, cy + bench_h - 0.12, cz), chamfer=0.01)

    # 3 Longitudinal seat planks
    plank_w = bench_w / 3.0
    for p in range(3):
        px = cx - bench_w * 0.5 + (float(p) + 0.5) * plank_w
        mb.add_box("wood_spruce", (plank_w * 0.94, 0.06, length), (px, cy + bench_h - 0.03, cz), chamfer=0.008)

    # Headrest bolster beam at north end of bench
    mb.add_box("wood_dark", (bench_w * 0.92, 0.10, 0.18), (cx, cy + bench_h + 0.04, cz - length * 0.42), chamfer=0.02)


# ==============================================================================
# MODULE GENERATION CATALOG
# ==============================================================================

def generate_all_modules():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    manifest = []

    # 1. Foundation Pier (Grunnmurstein)
    mb = ModuleBuilder("foundation_pier")
    build_foundation_pier_geom(mb, (0.0, 0.0), 0.45)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "foundation_pier.glb")))

    # 2. Foundation Plinth & Mudsill 4m (Grunnmur & Svillstokk)
    mb = ModuleBuilder("foundation_plinth_4m")
    build_foundation_plinth_geom(mb, 4.0, (0.0, 0.0, 0.0), 0.0)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "foundation_plinth_4m.glb")))

    # 3. Floor Plank Bay 4m x 4m (Gulvbord)
    mb = ModuleBuilder("floor_plank_bay")
    build_floor_plank_bay_geom(mb, 4.0, 4.0, 0.10)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "floor_plank_bay.glb")))

    # 4. Single Hand-Hewn Notched Laft Log 4m (Laftestokk med Nov)
    mb = ModuleBuilder("laft_log_4m")
    mb.add_hewn_log("wood_spruce", 4.60, 0.28, 0.32, (0.0, 0.14, 0.0), yaw=0.0, has_left_notch=True, has_right_notch=True, notch_offset=0.30)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "laft_log_4m.glb")))

    # 5. Solid 8-Course Notched Log Wall 4.0m (Lafteverk Vegg)
    mb = ModuleBuilder("laft_wall_solid")
    build_lafteverk_wall_courses_geom(mb, (0.0, 0.0, 0.0), 4.0, 2.28, 0.0, 8, 0.32, 0.30, [])
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "laft_wall_solid.glb")))

    # 6. Shuttered Window 8-Course Notched Log Wall 4.0m (Lafteverk Vindusvegg)
    mb = ModuleBuilder("laft_wall_window")
    win_ap = [{"x": 0.0, "y_min": 0.92, "y_max": 1.72, "w": 0.86}]
    build_lafteverk_wall_courses_geom(mb, (0.0, 0.0, 0.0), 4.0, 2.28, 0.0, 8, 0.32, 0.30, win_ap)
    build_window_assembly_geom(mb, (0.0, 1.32, 0.0), 0.0, 0.86, 0.80, 0.32, True, True)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "laft_wall_window.glb")))

    # 7. Portal Doorway 8-Course Notched Log Wall 4.0m (Lafteverk Dørvegg)
    mb = ModuleBuilder("laft_wall_doorway")
    door_ap = [{"x": 0.0, "y_min": 0.0, "y_max": 1.95, "w": 1.12}]
    build_lafteverk_wall_courses_geom(mb, (0.0, 0.0, 0.0), 4.0, 2.28, 0.0, 8, 0.32, 0.30, door_ap)
    build_door_assembly_geom(mb, (0.0, 0.0, 0.0), 0.0, 1.12, 1.95, 0.32, True)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "laft_wall_doorway.glb")))

    # 8. Triangular Notched Log Gable (Gavlvegg)
    mb = ModuleBuilder("laft_gable_triangle")
    build_gable_triangle_geom(mb, (0.0, 0.0, 0.0), 5.0, 1.40, 0.32, 0.30, 0.0, 6)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "laft_gable_triangle.glb")))

    # 9. Raftered Birch-Bark & Sod Roof Slope Section (Torvtak med Sperrer)
    mb = ModuleBuilder("torvtak_roof_slope")
    build_roof_slope_geom(mb, 5.0, 5.0, 0.0, 1.40, -1.0)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "torvtak_roof_slope.glb")))

    # 10. Ridge Beam, Bargeboards & Ljore Smoke Vent (Ljore & Vindski)
    mb = ModuleBuilder("ljore_smoke_vent")
    build_ljore_and_bargeboards_geom(mb, 5.0, 5.0, 0.0, 1.40, True)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "ljore_smoke_vent.glb")))

    # 11. Central Stone Hearth (Åre Ildsted)
    mb = ModuleBuilder("are_central_hearth")
    build_are_hearth_geom(mb, (0.0, 0.0, 0.0))
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "are_central_hearth.glb")))

    # 12. Interior Wall Sleeping Bench (Langbenk)
    mb = ModuleBuilder("langbenk_sleeping_bench")
    build_langbenk_geom(mb, (0.0, 0.0, 0.0), 3.0)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "langbenk_sleeping_bench.glb")))

    # --------------------------------------------------------------------------
    # STAGE-LEVEL COMPOSITE MODULES (5.0m x 5.0m Standard Cabin Footprint)
    # --------------------------------------------------------------------------
    w, d = 5.0, 5.0
    hw, hd = w * 0.5, d * 0.5
    wall_h = 2.28
    gable_h = 1.40

    # 13. Stage 1: Complete Foundation & Floor (Grunnmur)
    mb = ModuleBuilder("stage_1_foundation")
    for px in (-hw, 0.0, hw):
        build_foundation_pier_geom(mb, (px, -hd), 0.42)
        build_foundation_pier_geom(mb, (px, hd), 0.42)
    build_foundation_pier_geom(mb, (-hw, 0.0), 0.42)
    build_foundation_pier_geom(mb, (hw, 0.0), 0.42)
    build_foundation_plinth_geom(mb, w, (0.0, 0.0, -hd), 0.0)
    build_foundation_plinth_geom(mb, w, (0.0, 0.0, hd), math.pi)
    build_foundation_plinth_geom(mb, d, (-hw, 0.0, 0.0), -math.pi * 0.5)
    build_foundation_plinth_geom(mb, d, (hw, 0.0, 0.0), math.pi * 0.5)
    build_floor_plank_bay_geom(mb, w, d, 0.10)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "stage_1_foundation.glb")))

    # 14. Stage 2: Complete 4 Interlocking Log Walls, Shuttered Windows & Door (Veggløft)
    mb = ModuleBuilder("stage_2_walls")
    build_lafteverk_wall_courses_geom(mb, (0.0, 0.0, -hd), w, wall_h, 0.0, 8, 0.32, 0.30, door_ap)
    build_door_assembly_geom(mb, (0.0, 0.0, -hd), 0.0, 1.12, 1.95, 0.32, True)
    build_lafteverk_wall_courses_geom(mb, (0.0, 0.0, hd), w, wall_h, math.pi, 8, 0.32, 0.30, win_ap)
    build_window_assembly_geom(mb, (0.0, 1.32, hd), math.pi, 0.86, 0.80, 0.32, True, True)
    build_lafteverk_wall_courses_geom(mb, (-hw, 0.0, 0.0), d, wall_h, -math.pi * 0.5, 8, 0.32, 0.30, win_ap)
    build_window_assembly_geom(mb, (-hw, 1.32, 0.0), -math.pi * 0.5, 0.86, 0.80, 0.32, True, True)
    build_lafteverk_wall_courses_geom(mb, (hw, 0.0, 0.0), d, wall_h, math.pi * 0.5, 8, 0.32, 0.30, win_ap)
    build_window_assembly_geom(mb, (hw, 1.32, 0.0), math.pi * 0.5, 0.86, 0.80, 0.32, True, True)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "stage_2_walls.glb")))

    # 15. Stage 3: Complete Gables, Rafters, Sod Roof & Ljore Smoke Vent (Torvtak)
    mb = ModuleBuilder("stage_3_roof")
    build_gable_triangle_geom(mb, (0.0, wall_h, -hd), w, gable_h, 0.32, 0.30, 0.0, 6)
    build_gable_triangle_geom(mb, (0.0, wall_h, hd), w, gable_h, 0.32, 0.30, math.pi, 6)
    build_roof_slope_geom(mb, w, d, wall_h, gable_h, -1.0)
    build_roof_slope_geom(mb, w, d, wall_h, gable_h, 1.0)
    build_ljore_and_bargeboards_geom(mb, w, d, wall_h, gable_h, True)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "stage_3_roof.glb")))

    # 16. Stage 4: Complete Central Åre Hearth & Langbenk Bench (Åre Ildsted)
    mb = ModuleBuilder("stage_4_hearth")
    build_are_hearth_geom(mb, (0.0, 0.06, 0.20))
    build_langbenk_geom(mb, (hw - 0.56, 0.06, 0.20), d * 0.58)
    manifest.append(mb.export_glb(os.path.join(OUTPUT_DIR, "stage_4_hearth.glb")))

    print("\n=== BLENDER LAFTEHYTTE MODULAR ASSET SUMMARY ===")
    total_kb = 0.0
    for item in manifest:
        kb = item["bytes"] / 1024.0
        total_kb += kb
        print(f"  [OK] {item['filepath']:48s} | {item['verts']:5d} verts | {item['tris']:5d} tris | {kb:6.1f} KB | mats={item['materials']}")
    print(f"Total modules exported: {len(manifest)} ({total_kb:.1f} KB total)")


if __name__ == "__main__":
    generate_all_modules()
