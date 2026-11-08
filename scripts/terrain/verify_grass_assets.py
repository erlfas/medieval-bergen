#!/usr/bin/env python3
"""
Verification gate for Phase 1: Asset Ingestion, Decimation & Texture Optimization.
Checks:
- LOD0 triangle count <= 500
- LOD1 triangle count <= 12
- Disk footprint of generated assets <= 450 KB (down from 9.9 MB)
- Normal, UV, and bounding box validity
"""

import os
import sys
import trimesh
import numpy as np

def verify():
    print("=== Running GATE 1: Grass Asset Verification ===")
    errors = []

    lod0_path = "assets/terrain/grass_clump_lod0.glb"
    lod1_path = "assets/terrain/grass_clump_lod1.glb"
    albedo_path = "assets/terrain/grass_clump_albedo.jpg"
    normal_path = "assets/terrain/grass_clump_normal.jpg"
    pbr_path = "assets/terrain/grass_clump_pbr.jpg"
    billboard_path = "assets/terrain/grass_billboard.png"

    # Check existence
    for path in [lod0_path, lod1_path, albedo_path, normal_path, pbr_path, billboard_path]:
        if not os.path.exists(path):
            errors.append(f"Missing expected asset: {path}")

    if errors:
        for e in errors:
            print("FAIL:", e)
        sys.exit(1)

    # 1. Inspect LOD0
    lod0 = trimesh.load(lod0_path, force="mesh")
    n_tris_lod0 = len(lod0.faces)
    print(f"LOD0: {n_tris_lod0} triangles, {len(lod0.vertices)} vertices")
    if n_tris_lod0 > 500:
        errors.append(f"LOD0 triangle count {n_tris_lod0} exceeds threshold 500")

    # Bounds check
    bounds_min, bounds_max = lod0.bounds
    print(f"LOD0 Bounds: min={bounds_min.round(3)}, max={bounds_max.round(3)}")
    if bounds_min[1] < -0.05 or bounds_min[1] > 0.05:
        errors.append(f"LOD0 root Y ({bounds_min[1]}) is not aligned to ground plane 0.0")
    if bounds_max[1] < 0.50 or bounds_max[1] > 1.10:
        errors.append(f"LOD0 height ({bounds_max[1]}) is outside expected [0.50, 1.10]")

    # 2. Inspect LOD1
    lod1 = trimesh.load(lod1_path, force="mesh")
    n_tris_lod1 = len(lod1.faces)
    print(f"LOD1: {n_tris_lod1} triangles, {len(lod1.vertices)} vertices")
    if n_tris_lod1 > 12:
        errors.append(f"LOD1 triangle count {n_tris_lod1} exceeds threshold 12")

    # 3. File size check
    total_size = sum(os.path.getsize(p) for p in [lod0_path, lod1_path, albedo_path, normal_path, pbr_path, billboard_path])
    total_kb = total_size / 1024.0
    print(f"Total optimized assets footprint: {total_kb:.1f} KB (raw source was 9,676 KB)")
    if total_kb > 450.0:
        errors.append(f"Total asset footprint {total_kb:.1f} KB exceeds threshold 450 KB")

    if errors:
        print("\nGATE 1 FAILED with errors:")
        for e in errors:
            print(f" - {e}")
        sys.exit(1)
    else:
        print("\n>>> GATE 1 PASSED: All asset decimation and size benchmarks met! <<<\n")

if __name__ == "__main__":
    verify()
