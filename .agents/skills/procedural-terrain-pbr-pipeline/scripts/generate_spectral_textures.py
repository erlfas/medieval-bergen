#!/usr/bin/env python3
"""
Procedural Spectral Fractal Terrain Texture Generator for Godot WebGL Games.
Generates 100% seamless, mathematically isotropic PBR textures:
1. Grass & meadow turf (albedo + tangent normal map)
2. Mountain rock cliffs & granite strata (albedo + tangent normal map)
3. Scree & talus gravel (albedo + tangent normal map)
Uses 2D Fast Fourier Transform (FFT) power-law spectral filtering (1 / k^beta)
to guarantee zero tiling seams, no diamond/grid artifacts, and natural fractional Brownian motion.
"""

import sys
import os
import numpy as np
from PIL import Image

def spectral_fbm(width: int, height: int, beta: float = 2.0, seed: int = None) -> np.ndarray:
    """Generates 2D seamless fractional Brownian motion via Fourier filtering."""
    if seed is not None:
        np.random.seed(seed)
    ky = np.fft.fftfreq(height)[:, None]
    kx = np.fft.fftfreq(width)[None, :]
    k = np.sqrt(kx**2 + ky**2)
    k[0, 0] = 1.0  # DC component

    phases = np.random.uniform(0, 2 * np.pi, (height, width))
    amplitudes = np.random.rayleigh(1.0, (height, width))
    fourier = amplitudes * np.exp(1j * phases)

    filter_kernel = 1.0 / (k ** beta)
    filter_kernel[0, 0] = 0.0

    filtered = fourier * filter_kernel
    spatial = np.fft.ifft2(filtered).real
    return (spatial - spatial.min()) / (spatial.max() - spatial.min() + 1e-6)

def make_normal_map(h_map: np.ndarray, strength: float = 6.0) -> np.ndarray:
    """Computes a seamless tangent-space normal map using periodic central differences."""
    dx = (np.roll(h_map, -1, axis=1) - np.roll(h_map, 1, axis=1)) * 0.5
    dy = (np.roll(h_map, -1, axis=0) - np.roll(h_map, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(nx)
    length = np.sqrt(nx**2 + ny**2 + nz**2) + 1e-6
    nx /= length
    ny /= length
    nz /= length
    return np.stack([
        ((nx * 0.5 + 0.5) * 255).astype(np.uint8),
        ((ny * 0.5 + 0.5) * 255).astype(np.uint8),
        ((nz * 0.5 + 0.5) * 255).astype(np.uint8)
    ], axis=2)

def generate_all(output_dir: str = "assets/terrain", size: int = 512):
    os.makedirs(output_dir, exist_ok=True)
    W, H = size, size

    print(f"Generating procedural textures ({W}x{H}) into {output_dir}...")

    # 1. GRASS & TURF
    macro = spectral_fbm(W, H, beta=2.3, seed=1360)
    turf = spectral_fbm(W, H, beta=1.8, seed=1361)
    blades = spectral_fbm(W, H, beta=1.1, seed=1362)
    micro = spectral_fbm(W, H, beta=0.8, seed=1363)
    grass_h = turf * 0.35 + blades * 0.45 + micro * 0.20

    col_soil = np.array([38.0, 30.0, 20.0])
    col_deep = np.array([45.0, 68.0, 26.0])
    col_mid = np.array([72.0, 118.0, 38.0])
    col_bright = np.array([112.0, 168.0, 52.0])
    col_moss = np.array([136.0, 142.0, 46.0])

    t = grass_h[:, :, None]
    grass_col = col_deep * (1.0 - t) + col_mid * t
    tips = np.clip((blades - 0.55) * 3.0, 0.0, 1.0)[:, :, None]
    grass_col = grass_col * (1.0 - tips * 0.6) + col_bright * (tips * 0.6)
    soil_mask = np.clip((0.36 - grass_h) * 4.5 + (micro - 0.68) * 1.8, 0.0, 1.0)[:, :, None]
    grass_col = grass_col * (1.0 - soil_mask) + col_soil * soil_mask
    moss_mask = np.clip((macro - 0.60) * 3.5, 0.0, 1.0)[:, :, None]
    grass_col = grass_col * (1.0 - moss_mask * 0.45) + col_moss * (moss_mask * 0.45)

    Image.fromarray(np.clip(grass_col, 0, 255).astype(np.uint8)).save(os.path.join(output_dir, "grass_albedo.png"))
    Image.fromarray(make_normal_map(grass_h, strength=6.5)).save(os.path.join(output_dir, "grass_normal.png"))

    # 2. ROCK
    rock_strata = spectral_fbm(W, H, beta=2.3, seed=2001)
    rock_crags = spectral_fbm(W, H, beta=1.5, seed=2002)
    rock_fissures = spectral_fbm(W, H, beta=1.0, seed=2003)
    rock_h = rock_strata * 0.35 + rock_crags * 0.45 + rock_fissures * 0.20

    col_rock_dark = np.array([40.0, 44.0, 48.0])
    col_rock_mid = np.array([72.0, 78.0, 84.0])
    col_rock_light = np.array([118.0, 124.0, 130.0])
    col_rock_lichen = np.array([85.0, 96.0, 75.0])

    rt = rock_h[:, :, None]
    rock_col = col_rock_dark * (1.0 - rt) + col_rock_mid * rt
    vein = np.clip((rock_fissures - 0.70) * 4.5, 0.0, 1.0)[:, :, None]
    rock_col = rock_col * (1.0 - vein) + col_rock_light * vein
    lichen = np.clip((rock_strata - 0.58) * 3.0, 0.0, 1.0)[:, :, None]
    rock_col = rock_col * (1.0 - lichen * 0.4) + col_rock_lichen * (lichen * 0.4)

    Image.fromarray(np.clip(rock_col, 0, 255).astype(np.uint8)).save(os.path.join(output_dir, "rock_albedo.png"))
    Image.fromarray(make_normal_map(rock_h, strength=8.0)).save(os.path.join(output_dir, "rock_normal.png"))

    # 3. SCREE
    scree_large = spectral_fbm(W, H, beta=1.5, seed=3001)
    scree_small = spectral_fbm(W, H, beta=1.0, seed=3002)
    scree_h = scree_large * 0.55 + scree_small * 0.45
    col_scree_dark = np.array([52.0, 48.0, 45.0])
    col_scree_light = np.array([125.0, 118.0, 112.0])
    st = scree_h[:, :, None]
    scree_col = col_scree_dark * (1.0 - st) + col_scree_light * st

    Image.fromarray(np.clip(scree_col, 0, 255).astype(np.uint8)).save(os.path.join(output_dir, "scree_albedo.png"))
    Image.fromarray(make_normal_map(scree_h, strength=7.0)).save(os.path.join(output_dir, "scree_normal.png"))

    print("Spectral textures generation complete!")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/terrain"
    generate_all(output_dir=out)
