import numpy as np
from PIL import Image

def generate_textures():
    W = 512
    H = 512
    np.random.seed(1360)

    # Spectral fractal synthesis - 100% seamless, isotropic, organic
    def spectral_fbm(W, H, beta=2.0, seed=None):
        if seed is not None:
            np.random.seed(seed)
        ky = np.fft.fftfreq(H)[:, None]
        kx = np.fft.fftfreq(W)[None, :]
        k = np.sqrt(kx**2 + ky**2)
        k[0, 0] = 1.0

        phases = np.random.uniform(0, 2 * np.pi, (H, W))
        amplitudes = np.random.rayleigh(1.0, (H, W))
        fourier = amplitudes * np.exp(1j * phases)

        filter_kernel = 1.0 / (k ** beta)
        filter_kernel[0, 0] = 0.0

        filtered = fourier * filter_kernel
        spatial = np.fft.ifft2(filtered).real
        return (spatial - spatial.min()) / (spatial.max() - spatial.min() + 1e-6)

    print("Generating High-Fidelity Turf Grass...")
    macro = spectral_fbm(W, H, beta=2.3, seed=1360)
    turf = spectral_fbm(W, H, beta=1.8, seed=1361)
    blades = spectral_fbm(W, H, beta=1.1, seed=1362)
    micro_grain = spectral_fbm(W, H, beta=0.8, seed=1363)

    # Crisp individual grass blades and turf tufts
    grass_h = turf * 0.35 + blades * 0.45 + micro_grain * 0.20

    # High-contrast natural Norwegian palette
    # Soil dark loam: [34, 28, 18]
    # Rich under-turf: [45, 68, 26]
    # Prime meadow blade: [75, 125, 42]
    # Bright sunlit tip: [115, 172, 54]
    # Golden moss / lichen: [136, 142, 46]

    col_soil = np.array([38.0, 30.0, 20.0])
    col_deep = np.array([45.0, 68.0, 26.0])
    col_mid = np.array([72.0, 118.0, 38.0])
    col_bright = np.array([112.0, 168.0, 52.0])
    col_moss = np.array([136.0, 142.0, 46.0])

    # Blend colors
    t = grass_h[:, :, None]
    col = col_deep * (1.0 - t) + col_mid * t

    # Sharp blade tips
    tips = np.clip((blades - 0.55) * 3.0, 0.0, 1.0)[:, :, None]
    col = col * (1.0 - tips * 0.6) + col_bright * (tips * 0.6)

    # Micro soil patches in depressions
    soil_mask = np.clip((0.36 - grass_h) * 4.5 + (micro_grain - 0.68) * 1.8, 0.0, 1.0)[:, :, None]
    col = col * (1.0 - soil_mask) + col_soil * soil_mask

    # Moss colonies
    moss_mask = np.clip((macro - 0.60) * 3.5, 0.0, 1.0)[:, :, None]
    col = col * (1.0 - moss_mask * 0.45) + col_moss * (moss_mask * 0.45)

    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save("assets/terrain/grass_albedo.png")

    # Seamless Sobel Normal Map
    def make_normal_map(h_map, strength=6.0):
        dx = (np.roll(h_map, -1, axis=1) - np.roll(h_map, 1, axis=1)) * 0.5
        dy = (np.roll(h_map, -1, axis=0) - np.roll(h_map, 1, axis=0)) * 0.5
        nx = -dx * strength
        ny = -dy * strength
        nz = np.ones_like(nx)
        length = np.sqrt(nx**2 + ny**2 + nz**2) + 1e-6
        nx /= length
        ny /= length
        nz /= length
        norm_rgb = np.stack([
            ((nx * 0.5 + 0.5) * 255).astype(np.uint8),
            ((ny * 0.5 + 0.5) * 255).astype(np.uint8),
            ((nz * 0.5 + 0.5) * 255).astype(np.uint8)
        ], axis=2)
        return norm_rgb

    Image.fromarray(make_normal_map(grass_h, strength=6.5)).save("assets/terrain/grass_normal.png")

    # 2. ROCK ALBEDO & NORMAL
    print("Generating Rock...")
    rock_strata = spectral_fbm(W, H, beta=2.3, seed=2001)
    rock_crags = spectral_fbm(W, H, beta=1.5, seed=2002)
    rock_fissures = spectral_fbm(W, H, beta=1.0, seed=2003)
    rock_h = rock_strata * 0.35 + rock_crags * 0.45 + rock_fissures * 0.20

    col_rock_dark = np.array([40.0, 44.0, 48.0])
    col_rock_mid = np.array([72.0, 78.0, 84.0])
    col_rock_light = np.array([118.0, 124.0, 130.0])
    col_rock_lichen = np.array([85.0, 96.0, 75.0])

    rt = rock_h[:, :, None]
    rock_layer = col_rock_dark * (1.0 - rt) + col_rock_mid * rt
    quartz_vein = np.clip((rock_fissures - 0.70) * 4.5, 0.0, 1.0)[:, :, None]
    rock_layer = rock_layer * (1.0 - quartz_vein) + col_rock_light * quartz_vein
    lichen_mask = np.clip((rock_strata - 0.58) * 3.0, 0.0, 1.0)[:, :, None]
    rock_layer = rock_layer * (1.0 - lichen_mask * 0.4) + col_rock_lichen * (lichen_mask * 0.4)

    Image.fromarray(np.clip(rock_layer, 0, 255).astype(np.uint8)).save("assets/terrain/rock_albedo.png")
    Image.fromarray(make_normal_map(rock_h, strength=8.0)).save("assets/terrain/rock_normal.png")

    # 3. SCREE ALBEDO & NORMAL
    print("Generating Scree...")
    scree_large = spectral_fbm(W, H, beta=1.5, seed=3001)
    scree_small = spectral_fbm(W, H, beta=1.0, seed=3002)
    scree_h = scree_large * 0.55 + scree_small * 0.45

    col_scree_dark = np.array([52.0, 48.0, 45.0])
    col_scree_light = np.array([125.0, 118.0, 112.0])
    st = scree_h[:, :, None]
    scree_layer = col_scree_dark * (1.0 - st) + col_scree_light * st

    Image.fromarray(np.clip(scree_layer, 0, 255).astype(np.uint8)).save("assets/terrain/scree_albedo.png")
    Image.fromarray(make_normal_map(scree_h, strength=7.0)).save("assets/terrain/scree_normal.png")

    print("All Textures Generated Successfully!")

if __name__ == "__main__":
    generate_textures()
