@tool
extends SceneTree

## Procedural Texture Generator for Medieval Bergen Terrain
## Generates high-fidelity, seamless, realistic Norwegian textures:
## 1. Lush Bergen meadow grass (albedo + normal)
## 2. Mount Fløyen & Sandviksfjellet granite cliffs (albedo + normal)
## 3. Mountain scree / talus gravel (albedo + normal)

func _init() -> void:
	print("--- Starting Terrain Texture Generation ---")
	await _generate_all_textures()
	print("--- Terrain Texture Generation Complete ---")
	quit()

func _generate_all_textures() -> void:
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("assets/terrain"):
		dir.make_dir_recursive("assets/terrain")

	await _generate_grass_textures()
	await _generate_rock_textures()
	await _generate_scree_textures()
	await _generate_macro_noise()

func _generate_grass_textures() -> void:
	print("Generating Grass Textures...")
	var size := 512

	# 1. Base turf noise (clumping & soil)
	var noise_turf := FastNoiseLite.new()
	noise_turf.seed = 1360
	noise_turf.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_turf.frequency = 0.015
	noise_turf.fractal_octaves = 4
	noise_turf.fractal_gain = 0.5

	# 2. Blade / tuft detail noise
	var noise_blades := FastNoiseLite.new()
	noise_blades.seed = 1360 + 42
	noise_blades.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_blades.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise_blades.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	noise_blades.frequency = 0.07
	noise_blades.fractal_octaves = 3

	# 3. Fine fiber noise
	var noise_fiber := FastNoiseLite.new()
	noise_fiber.seed = 1360 + 99
	noise_fiber.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_fiber.frequency = 0.15
	noise_fiber.fractal_octaves = 2

	# 4. Moss patch noise
	var noise_moss := FastNoiseLite.new()
	noise_moss.seed = 1360 + 77
	noise_moss.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moss.frequency = 0.03
	noise_moss.fractal_octaves = 3

	var img_albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var height_map := PackedFloat32Array()
	height_map.resize(size * size)

	# Norwegian Bergen grass color palette
	var col_sod_dark := Color(0.13, 0.20, 0.09)     # Deep humus / wet soil underlayer
	var col_grass_deep := Color(0.20, 0.38, 0.13)    # Lush Bergen emerald meadow
	var col_grass_mid := Color(0.28, 0.48, 0.17)     # Prime grass blade green
	var col_grass_bright := Color(0.38, 0.58, 0.22)  # Sunlit tips & young ryegrass
	var col_moss_olive := Color(0.42, 0.46, 0.16)    # Norwegian golden-olive bog moss
	var col_moss_bright := Color(0.50, 0.54, 0.20)   # Star moss highlights

	for y in range(size):
		var vy := float(y) / float(size)
		var angle_y := vy * TAU
		var cy := cos(angle_y) * 40.0
		var sy := sin(angle_y) * 40.0

		for x in range(size):
			var vx := float(x) / float(size)
			var angle_x := vx * TAU
			var cx := cos(angle_x) * 40.0
			var sx := sin(angle_x) * 40.0

			# Seamless 4D toroidal sampling via pairs
			var n_turf := (noise_turf.get_noise_2d(cx, cy) + noise_turf.get_noise_2d(sx + 50.0, sy + 50.0)) * 0.5
			var n_blade := (noise_blades.get_noise_2d(cx * 1.5, cy * 1.5) + noise_blades.get_noise_2d(sx * 1.5 + 80.0, sy * 1.5 + 80.0)) * 0.5
			var n_fiber := (noise_fiber.get_noise_2d(cx * 2.0, cy * 2.0) + noise_fiber.get_noise_2d(sx * 2.0, sy * 2.0)) * 0.5
			var n_moss := (noise_moss.get_noise_2d(cx, cy) + noise_moss.get_noise_2d(sx + 120.0, sy + 120.0)) * 0.5

			# Normalize to [0, 1]
			var turf_val := clampf((n_turf + 1.0) * 0.5, 0.0, 1.0)
			var blade_val := clampf((n_blade + 1.0) * 0.5, 0.0, 1.0)
			var fiber_val := clampf((n_fiber + 1.0) * 0.5, 0.0, 1.0)
			var moss_val := clampf((n_moss + 1.0) * 0.5, 0.0, 1.0)

			# Multi-octave composite height for normal map
			var h := turf_val * 0.4 + blade_val * 0.45 + fiber_val * 0.15
			height_map[y * size + x] = h

			# Color blending
			var col: Color
			if turf_val < 0.25:
				# Humus / soil base transitioning to dark grass
				col = col_sod_dark.lerp(col_grass_deep, turf_val / 0.25)
			elif turf_val < 0.65:
				# Deep meadow green transitioning to mid green
				var t := (turf_val - 0.25) / 0.4
				col = col_grass_deep.lerp(col_grass_mid, t)
			else:
				# Mid green to bright tips
				var t := (turf_val - 0.65) / 0.35
				col = col_grass_mid.lerp(col_grass_bright, t)

			# Add blade highlights
			col = col.lerp(col_grass_bright, blade_val * 0.35)

			# Add moss patches (concentrated in damp turf hollows)
			if moss_val > 0.52 and turf_val < 0.7:
				var m_factor := clampf((moss_val - 0.52) / 0.4, 0.0, 1.0)
				var moss_col := col_moss_olive.lerp(col_moss_bright, fiber_val)
				col = col.lerp(moss_col, m_factor * 0.75)

			# Subtle blade micro-shadowing
			col = col * (0.85 + 0.3 * fiber_val)
			col.a = 1.0
			img_albedo.set_pixel(x, y, col)

	img_albedo.save_png("res://assets/terrain/grass_albedo.png")
	print("Saved grass_albedo.png")

	# Generate Grass Normal Map from height_map using Sobel filter
	var img_normal := _generate_normal_from_heights(height_map, size, 3.5)
	img_normal.save_png("res://assets/terrain/grass_normal.png")
	print("Saved grass_normal.png")

func _generate_rock_textures() -> void:
	print("Generating Mountain Rock Textures (Fløyen / Sandviksfjellet)...")
	var size := 512

	# 1. Granite base fracture noise
	var noise_crags := FastNoiseLite.new()
	noise_crags.seed = 1360 + 555
	noise_crags.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_crags.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_crags.frequency = 0.018
	noise_crags.fractal_octaves = 4
	noise_crags.fractal_gain = 0.6

	# 2. Metamorphic Gneiss strata (horizontal & dipping bands)
	var noise_strata := FastNoiseLite.new()
	noise_strata.seed = 1360 + 888
	noise_strata.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_strata.frequency = 0.04
	noise_strata.fractal_octaves = 3

	# 3. Micro grain & mineral speckle (quartz / biotite mica)
	var noise_grain := FastNoiseLite.new()
	noise_grain.seed = 1360 + 111
	noise_grain.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_grain.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN
	noise_grain.frequency = 0.12

	# 4. Lichen coverage noise
	var noise_lichen := FastNoiseLite.new()
	noise_lichen.seed = 1360 + 444
	noise_lichen.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_lichen.frequency = 0.025
	noise_lichen.fractal_octaves = 3

	var img_albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var height_map := PackedFloat32Array()
	height_map.resize(size * size)

	# Scandinavian Granite / Gneiss palette
	var col_shadow_crevice := Color(0.15, 0.16, 0.17) # Deep fracture shadows
	var col_granite_dark := Color(0.27, 0.28, 0.30)   # Dark charcoal granite / amphibolite
	var col_granite_mid := Color(0.38, 0.40, 0.42)    # Typical Bergen granite slate
	var col_strata_light := Color(0.50, 0.52, 0.54)   # Quartz / feldspar metamorphic banding
	var col_ridge_highlight := Color(0.60, 0.62, 0.63)# Sunlit weathered cliff edge
	var col_lichen_pale := Color(0.38, 0.44, 0.36)    # Crustose sage lichen
	var col_lichen_yellow := Color(0.48, 0.46, 0.32)  # Alpine rock lichen highlights

	for y in range(size):
		var vy := float(y) / float(size)
		var angle_y := vy * TAU
		var cy := cos(angle_y) * 40.0
		var sy := sin(angle_y) * 40.0

		for x in range(size):
			var vx := float(x) / float(size)
			var angle_x := vx * TAU
			var cx := cos(angle_x) * 40.0
			var sx := sin(angle_x) * 40.0

			var n_crags := (noise_crags.get_noise_2d(cx, cy) + noise_crags.get_noise_2d(sx + 70.0, sy + 70.0)) * 0.5
			# Metamorphic strata: stretch horizontally to simulate geologic bedding
			var n_strata := (noise_strata.get_noise_2d(cx * 0.3 + cy * 0.1, cy * 2.2) + noise_strata.get_noise_2d(sx * 0.3 + sy * 0.1, sy * 2.2)) * 0.5
			var n_grain := (noise_grain.get_noise_2d(cx * 2.0, cy * 2.0) + noise_grain.get_noise_2d(sx * 2.0, sy * 2.0)) * 0.5
			var n_lichen := (noise_lichen.get_noise_2d(cx, cy) + noise_lichen.get_noise_2d(sx + 90.0, sy + 90.0)) * 0.5

			var crag_val := clampf((n_crags + 1.0) * 0.5, 0.0, 1.0)
			var strata_val := clampf((n_strata + 1.0) * 0.5, 0.0, 1.0)
			var grain_val := clampf((n_grain + 1.0) * 0.5, 0.0, 1.0)
			var lichen_val := clampf((n_lichen + 1.0) * 0.5, 0.0, 1.0)

			# Height for cliff normal map: combine strata steps, ridged crags, and mineral grain
			var h := crag_val * 0.5 + strata_val * 0.35 + grain_val * 0.15
			height_map[y * size + x] = h

			# Base granite color
			var col: Color
			if crag_val < 0.2:
				col = col_shadow_crevice.lerp(col_granite_dark, crag_val / 0.2)
			elif crag_val < 0.7:
				var t := (crag_val - 0.2) / 0.5
				col = col_granite_dark.lerp(col_granite_mid, t)
			else:
				var t := (crag_val - 0.7) / 0.3
				col = col_granite_mid.lerp(col_ridge_highlight, t)

			# Add metamorphic gneiss strata bands (light quartz streaks)
			if strata_val > 0.6:
				var st_f := (strata_val - 0.6) / 0.4
				col = col.lerp(col_strata_light, st_f * 0.6)

			# Add mineral grain sparkle (biotite / quartz flecks)
			col = col * (0.9 + 0.2 * grain_val)

			# Add crustose lichen patches on sheltered facets
			if lichen_val > 0.56:
				var l_factor := clampf((lichen_val - 0.56) / 0.35, 0.0, 1.0)
				var l_col := col_lichen_pale.lerp(col_lichen_yellow, strata_val)
				col = col.lerp(l_col, l_factor * 0.7)

			col.a = 1.0
			img_albedo.set_pixel(x, y, col)

	img_albedo.save_png("res://assets/terrain/rock_albedo.png")
	print("Saved rock_albedo.png")

	var img_normal := _generate_normal_from_heights(height_map, size, 4.5)
	img_normal.save_png("res://assets/terrain/rock_normal.png")
	print("Saved rock_normal.png")

func _generate_scree_textures() -> void:
	print("Generating Mountain Scree / Talus Textures...")
	var size := 512

	# Angular gravel / pebble Voronoi cells
	var noise_gravel := FastNoiseLite.new()
	noise_gravel.seed = 1360 + 333
	noise_gravel.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_gravel.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN
	noise_gravel.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	noise_gravel.frequency = 0.06

	var noise_dirt := FastNoiseLite.new()
	noise_dirt.seed = 1360 + 222
	noise_dirt.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_dirt.frequency = 0.03
	noise_dirt.fractal_octaves = 3

	var img_albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var height_map := PackedFloat32Array()
	height_map.resize(size * size)

	var col_stone_dark := Color(0.24, 0.25, 0.26)
	var col_stone_mid := Color(0.36, 0.37, 0.39)
	var col_stone_light := Color(0.48, 0.49, 0.50)
	var col_earth := Color(0.30, 0.26, 0.20)

	for y in range(size):
		var vy := float(y) / float(size)
		var angle_y := vy * TAU
		var cy := cos(angle_y) * 40.0
		var sy := sin(angle_y) * 40.0

		for x in range(size):
			var vx := float(x) / float(size)
			var angle_x := vx * TAU
			var cx := cos(angle_x) * 40.0
			var sx := sin(angle_x) * 40.0

			var n_g := (noise_gravel.get_noise_2d(cx, cy) + noise_gravel.get_noise_2d(sx + 50.0, sy + 50.0)) * 0.5
			var n_d := (noise_dirt.get_noise_2d(cx, cy) + noise_dirt.get_noise_2d(sx + 10.0, sy + 10.0)) * 0.5

			var g_val := clampf((n_g + 1.0) * 0.5, 0.0, 1.0)
			var d_val := clampf((n_d + 1.0) * 0.5, 0.0, 1.0)

			height_map[y * size + x] = g_val * 0.75 + d_val * 0.25

			var col := col_stone_dark.lerp(col_stone_mid, g_val)
			if g_val > 0.7:
				col = col.lerp(col_stone_light, (g_val - 0.7) / 0.3)
			# Dirt between stones
			if g_val < 0.35:
				col = col.lerp(col_earth, (0.35 - g_val) / 0.35)

			col.a = 1.0
			img_albedo.set_pixel(x, y, col)

	img_albedo.save_png("res://assets/terrain/scree_albedo.png")
	print("Saved scree_albedo.png")

	var img_normal := _generate_normal_from_heights(height_map, size, 4.0)
	img_normal.save_png("res://assets/terrain/scree_normal.png")
	print("Saved scree_normal.png")

func _generate_macro_noise() -> void:
	print("Generating Macro Variation Noise...")
	var size := 512

	var n1 := FastNoiseLite.new()
	n1.seed = 1360 + 1001
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.008
	n1.fractal_octaves = 4

	var n2 := FastNoiseLite.new()
	n2.seed = 1360 + 2002
	n2.noise_type = FastNoiseLite.TYPE_PERLIN
	n2.frequency = 0.015
	n2.fractal_octaves = 3

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		var vy := float(y) / float(size)
		var angle_y := vy * TAU
		var cy := cos(angle_y) * 40.0
		var sy := sin(angle_y) * 40.0

		for x in range(size):
			var vx := float(x) / float(size)
			var angle_x := vx * TAU
			var cx := cos(angle_x) * 40.0
			var sx := sin(angle_x) * 40.0

			var v1 := (n1.get_noise_2d(cx, cy) + n1.get_noise_2d(sx + 30.0, sy + 30.0)) * 0.5
			var v2 := (n2.get_noise_2d(cx, cy) + n2.get_noise_2d(sx + 60.0, sy + 60.0)) * 0.5

			var r := clampf((v1 + 1.0) * 0.5, 0.0, 1.0) # Meadow lushness/dryness
			var g := clampf((v2 + 1.0) * 0.5, 0.0, 1.0) # Moss/lichen density
			var b := clampf((v1 * 0.5 + v2 * 0.5 + 1.0) * 0.5, 0.0, 1.0) # Strata modulation

			img.set_pixel(x, y, Color(r, g, b, 1.0))

	img.save_png("res://assets/terrain/macro_noise.png")
	print("Saved macro_noise.png")

## Computes a seamless normal map from a height array using Sobel filter
func _generate_normal_from_heights(heights: PackedFloat32Array, size: int, strength: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		var y_prev := (y - 1 + size) % size
		var y_next := (y + 1) % size

		for x in range(size):
			var x_prev := (x - 1 + size) % size
			var x_next := (x + 1) % size

			# Sobel filter kernel
			var tl := heights[y_prev * size + x_prev]
			var t  := heights[y_prev * size + x]
			var tr := heights[y_prev * size + x_next]

			var l  := heights[y * size + x_prev]
			var r  := heights[y * size + x_next]

			var bl := heights[y_next * size + x_prev]
			var b  := heights[y_next * size + x]
			var br := heights[y_next * size + x_next]

			var dx := (tr + 2.0 * r + br) - (tl + 2.0 * l + bl)
			var dy := (bl + 2.0 * b + br) - (tl + 2.0 * t + tr)

			var n := Vector3(-dx * strength, -dy * strength, 1.0).normalized()

			# Map [-1, 1] to [0, 1]
			var nr := (n.x + 1.0) * 0.5
			var ng := (n.y + 1.0) * 0.5
			var nb := (n.z + 1.0) * 0.5

			img.set_pixel(x, y, Color(nr, ng, nb, 1.0))

	return img
