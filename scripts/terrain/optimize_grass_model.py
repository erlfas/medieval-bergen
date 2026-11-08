#!/usr/bin/env python3
"""
Optimization pipeline for 3dmodels/grass clump 3d model.glb
Outputs:
- assets/terrain/grass_clump_lod0.glb (~400 triangles, clean geometry)
- assets/terrain/grass_clump_lod1.glb (6 triangles, crossed-quad)
- assets/terrain/grass_clump_albedo.jpg (512x512, high-quality PBR basecolor)
- assets/terrain/grass_clump_normal.jpg (512x512, tangent-space normal)
- assets/terrain/grass_clump_pbr.jpg (512x512, metallic/roughness)
- assets/terrain/grass_billboard.png (512x512 alpha cutout for LOD1)
"""

import os
import trimesh
import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial import cKDTree
from scipy.sparse.csgraph import connected_components
from scipy.sparse import coo_matrix
import fast_simplification._simplify as s

def optimize_grass():
    input_glb = "3dmodels/grass clump 3d model.glb"
    output_dir = "assets/terrain"
    os.makedirs(output_dir, exist_ok=True)

    print(f"Loading {input_glb}...")
    scene = trimesh.load(input_glb)
    geom_name = list(scene.geometry.keys())[0]
    mesh = scene.geometry[geom_name]

    print(f"Original mesh: {len(mesh.vertices)} vertices, {len(mesh.faces)} faces")

    # 1. Texture Optimization (JPEG for opaque PBR maps matches original GLB format while cutting VRAM >90%)
    mat = mesh.visual.material
    albedo_path = os.path.join(output_dir, "grass_clump_albedo.jpg")
    normal_path = os.path.join(output_dir, "grass_clump_normal.jpg")
    pbr_path = os.path.join(output_dir, "grass_clump_pbr.jpg")

    if mat.baseColorTexture:
        albedo_img = mat.baseColorTexture.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
        albedo_img.save(albedo_path, "JPEG", quality=88, optimize=True)
        print(f"Saved optimized albedo: {albedo_path} ({os.path.getsize(albedo_path) // 1024} KB)")

    if mat.normalTexture:
        normal_img = mat.normalTexture.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
        normal_img.save(normal_path, "JPEG", quality=88, optimize=True)
        print(f"Saved optimized normal: {normal_path} ({os.path.getsize(normal_path) // 1024} KB)")

    if mat.metallicRoughnessTexture:
        pbr_img = mat.metallicRoughnessTexture.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
        pbr_img.save(pbr_path, "JPEG", quality=88, optimize=True)
        print(f"Saved optimized PBR: {pbr_path} ({os.path.getsize(pbr_path) // 1024} KB)")

    # Clean up older large uncompressed PNGs if present
    for old_png in ["grass_clump_albedo.png", "grass_clump_normal.png", "grass_clump_pbr.png"]:
        p = os.path.join(output_dir, old_png)
        if os.path.exists(p):
            os.remove(p)

    # 2. Geometry Decimation for LOD0
    n = len(mesh.vertices)
    edges = mesh.edges_unique
    data = np.ones(len(edges))
    adj = coo_matrix((data, (edges[:, 0], edges[:, 1])), shape=(n, n))
    n_comp, labels = connected_components(adj, directed=False)

    face_labels = labels[mesh.faces[:, 0]]
    comp_areas = np.bincount(face_labels, weights=mesh.area_faces, minlength=n_comp)

    # Keep top 65 major grass blades
    top_k = min(65, n_comp)
    top_indices = np.argsort(comp_areas)[-top_k:]
    face_mask = np.isin(face_labels, top_indices)
    sub = mesh.submesh([face_mask], append=True)

    pts = sub.vertices.astype(np.float64, order="C")
    fcs = sub.faces.astype(np.int32, order="C")
    s.load_int32(len(pts), len(fcs), pts, fcs)
    s.simplify(target_count=380, aggressiveness=7.0, verbose=False, preserve_border=False)

    p_lod0 = s.return_points()
    f_lod0 = s.return_triangles()

    # Map UV coordinates from original mesh using KDTree
    orig_tree = cKDTree(mesh.vertices)
    _, indices = orig_tree.query(p_lod0)
    uv_lod0 = mesh.visual.uv[indices]

    # Re-anchor base to exact y=0.0
    p_lod0[:, 1] -= np.min(p_lod0[:, 1])

    lod0_mesh = trimesh.Trimesh(
        vertices=p_lod0,
        faces=f_lod0,
        process=True
    )
    lod0_mesh.visual = trimesh.visual.TextureVisuals(uv=uv_lod0)

    lod0_path = os.path.join(output_dir, "grass_clump_lod0.glb")
    lod0_mesh.export(lod0_path)
    print(f"Exported LOD0: {lod0_path} ({len(lod0_mesh.faces)} tris, {len(lod0_mesh.vertices)} verts, {os.path.getsize(lod0_path) // 1024} KB)")

    # 3. Crossed-Quad Billboard Generation for LOD1
    lod1_verts = []
    lod1_faces = []
    lod1_uvs = []

    width = 0.85
    height = 0.78
    half_w = width * 0.5

    angles = [0.0, np.pi / 3.0, 2.0 * np.pi / 3.0]
    for angle in angles:
        dx = np.cos(angle) * half_w
        dz = np.sin(angle) * half_w
        base_idx = len(lod1_verts)

        lod1_verts.append([-dx, 0.0, -dz])
        lod1_verts.append([dx, 0.0, dz])
        lod1_verts.append([dx, height, dz])
        lod1_verts.append([-dx, height, -dz])

        lod1_uvs.append([0.0, 1.0])
        lod1_uvs.append([1.0, 1.0])
        lod1_uvs.append([1.0, 0.0])
        lod1_uvs.append([0.0, 0.0])

        lod1_faces.append([base_idx, base_idx + 1, base_idx + 2])
        lod1_faces.append([base_idx, base_idx + 2, base_idx + 3])

    lod1_mesh = trimesh.Trimesh(
        vertices=np.array(lod1_verts, dtype=np.float32),
        faces=np.array(lod1_faces, dtype=np.int32),
        process=True
    )
    lod1_mesh.visual = trimesh.visual.TextureVisuals(uv=np.array(lod1_uvs, dtype=np.float32))

    lod1_path = os.path.join(output_dir, "grass_clump_lod1.glb")
    lod1_mesh.export(lod1_path)
    print(f"Exported LOD1: {lod1_path} ({len(lod1_mesh.faces)} tris, {os.path.getsize(lod1_path) // 1024} KB)")

    # 4. Bake Billboard Cutout Texture for LOD1
    bw, bh = 512, 512
    billboard_img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(billboard_img)

    b_pts = lod0_mesh.vertices.copy()
    min_x, max_x = np.min(b_pts[:, 0]), np.max(b_pts[:, 0])
    min_y, max_y = np.min(b_pts[:, 1]), np.max(b_pts[:, 1])

    scale = min((bw - 32) / (max_x - min_x), (bh - 32) / (max_y - min_y))
    px = ((b_pts[:, 0] - min_x) * scale + 16).astype(int)
    py = (bh - 16 - (b_pts[:, 1] - min_y) * scale).astype(int)

    col_base = (56, 98, 34, 255)
    for f in lod0_mesh.faces:
        poly = [(px[f[0]], py[f[0]]), (px[f[1]], py[f[1]]), (px[f[2]], py[f[2]])]
        draw.polygon(poly, fill=col_base, outline=col_base)

    billboard_path = os.path.join(output_dir, "grass_billboard.png")
    billboard_img.save(billboard_path, optimize=True)
    print(f"Exported billboard cutout: {billboard_path} ({os.path.getsize(billboard_path) // 1024} KB)")

if __name__ == "__main__":
    optimize_grass()
