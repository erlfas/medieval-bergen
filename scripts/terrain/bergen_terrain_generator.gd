@tool
class_name BergenTerrainGenerator
extends Node3D

## Procedural, Deterministic Bergen 1360 Topography & Valley Plain Generator
## Models the geography of Bergen:
## - Vågen harbour bay & shallow wading foreshore
## - Nordnes peninsula
## - Bryggen terrace bank & Øvregaten town plain
## - Broad glacial valley plains (Sandviken, Central Hinterland, Markov, Store Lungegårdsvann)
## - Fløyen & Sandviksfjellet steep eastern mountains
## - Puddefjorden western fjord

@export_group("World Dimensions")
@export var world_size: Vector2 = Vector2(2048.0, 2048.0)
@export var mesh_resolution: int = 256 ## Grid subdivisions per axis
@export var max_mountain_height: float = 380.0 ## Fløyen peak height (~400m)
@export var sea_level: float = 0.0

@export_group("Deterministic Seed")
@export var world_seed: int = 1360:
	set(val):
		world_seed = val
		_init_noise()
		if Engine.is_editor_hint() and is_inside_tree():
			generate_terrain()

@export_group("Geographic Features")
@export var vagen_length: float = 750.0
@export var vagen_width: float = 220.0
@export var vagen_depth: float = -28.0
@export var bryggen_shelf_width: float = 110.0 ## Flat shoreline & valley town strip for medieval tenements
@export var bryggen_shelf_height: float = 2.0 ## Safely above Gerstner wave crests (+0.22m)

@export_group("Generation Actions")
@export var regenerate: bool = false:
	set(val):
		if val:
			generate_terrain()
			regenerate = false

@export_group("Atmospheric Terrain Textures")
@export var terrain_shader: Shader = preload("res://shaders/bergen_terrain.gdshader")
@export var grass_texture: Texture2D = preload("res://assets/terrain/grass_albedo.png")
@export var grass_normal_map: Texture2D = preload("res://assets/terrain/grass_normal.png")
@export var rock_texture: Texture2D = preload("res://assets/terrain/rock_albedo.png")
@export var rock_normal_map: Texture2D = preload("res://assets/terrain/rock_normal.png")
@export var scree_texture: Texture2D = preload("res://assets/terrain/scree_albedo.png")
@export var scree_normal_map: Texture2D = preload("res://assets/terrain/scree_normal.png")
@export var macro_noise_map: Texture2D = preload("res://assets/terrain/macro_noise.png")

var _base_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _warp_noise: FastNoiseLite

var terrain_mesh_instance: MeshInstance3D
var water_plane_instance: MeshInstance3D

## Registered flat valley plain pads for city districts and farmsteads:
## Each entry: {"name": String, "x": float, "z": float, "target_y": float, "inner_radius": float, "outer_radius": float, "is_farm": bool}
var _settlement_pads: Array[Dictionary] = []

func _ready() -> void:
	_init_noise()
	generate_terrain()

func _init_noise() -> void:
	# 1. Base continental and valley noise
	_base_noise = FastNoiseLite.new()
	_base_noise.seed = world_seed
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base_noise.frequency = 0.0012
	_base_noise.fractal_octaves = 4
	_base_noise.fractal_gain = 0.5

	# 2. Mountain ridges (Fløyen / Ulriken crags)
	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = world_seed + 101
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.frequency = 0.0035
	_ridge_noise.fractal_octaves = 4
	_ridge_noise.fractal_gain = 0.55

	# 3. Fine surface detail (boulders, ledges, turf)
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = world_seed + 202
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.frequency = 0.025
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_gain = 0.4

	# 4. Domain warp for organic Norwegian fjord coastlines
	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed = world_seed + 303
	_warp_noise.domain_warp_enabled = true
	_warp_noise.domain_warp_amplitude = 45.0
	_warp_noise.domain_warp_frequency = 0.004

	_compute_settlement_plains()

## Evaluates raw natural valley elevation before settlement pad leveling
func _sample_natural_valley_height(x: float, z: float) -> float:
	var wx: float = x
	var wz: float = z
	var warp_offset_x := _base_noise.get_noise_2d(x * 0.8, z * 0.8) * 32.0
	var warp_offset_z := _base_noise.get_noise_2d(z * 0.8 + 500.0, x * 0.8) * 32.0
	wx += warp_offset_x
	wz += warp_offset_z

	# 1. Broad Glacial Valley Floor between Vågen and Mount Fløyen:
	# Shift the steep mountain cliff ramp east to wx = 185m so x in [45..180] forms wide fertile valley plains
	var fløyen_dist := maxf(0.0, wx - 180.0)
	var mountain_ramp := clampf(fløyen_dist / 390.0, 0.0, 1.0)
	mountain_ramp = mountain_ramp * mountain_ramp * (3.0 - 2.0 * mountain_ramp)

	var ridge_val := (_ridge_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	var base_val := (_base_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	var detail_val := _detail_noise.get_noise_2d(x, z) * 3.2

	# Gentle valley meadow undulation (3m to 11m elevation across the valley floor)
	var valley_meadow_height := 3.2 + base_val * 5.8
	var mountain_height := valley_meadow_height + mountain_ramp * (max_mountain_height * (0.65 * ridge_val + 0.35 * base_val))

	# 2. Fjord Carving: Vågen Bay
	var vagen_center_x := sin(wz * 0.003) * 55.0
	var dist_to_vagen_axis := absf(wx - vagen_center_x)
	var vagen_z_factor := clampf((wz + 200.0) / vagen_length, 0.0, 1.0)

	var vagen_half_width := (vagen_width * 0.5) * (1.0 - 0.25 * vagen_z_factor)
	var in_vagen_trough := 1.0 - smoothstep(vagen_half_width * 0.4, vagen_half_width * 1.18, dist_to_vagen_axis)
	if wz < -250.0:
		in_vagen_trough = maxf(in_vagen_trough, clampf((-wz - 250.0) / 150.0, 0.0, 1.0))
	elif wz > (vagen_length - 100.0):
		var falloff := clampf((wz - (vagen_length - 100.0)) / 120.0, 0.0, 1.0)
		in_vagen_trough *= (1.0 - falloff)

	# 3. Bryggen & Valley Shoreline Terrace (wx between 35m and 165m, wz between -140m and 660m)
	var bryggen_weight := 0.0
	if wx >= 35.0 and wx <= 165.0 and wz >= -140.0 and wz <= 660.0:
		var x_shelf_factor := 1.0 - clampf(absf((wx - 95.0) / 65.0), 0.0, 1.0)
		var z_shelf_factor := clampf(1.0 - absf((wz - 260.0) / 400.0), 0.0, 1.0)
		bryggen_weight = clampf(x_shelf_factor * z_shelf_factor, 0.0, 1.0)

	# 4. Puddefjorden & Western Fjord
	var puddefjord_dist := clampf((-wx - 300.0) / 200.0, 0.0, 1.0)

	# 5. Mountain Streams & Gullies
	var stream1_center := sin(wz * 0.02) * 20.0 + (wz * 0.4 + 195.0)
	var stream1_dist := absf(wx - stream1_center)
	var stream1_mask := clampf(1.0 - (stream1_dist / 13.0), 0.0, 1.0) * clampf((wz + 100.0) / 300.0, 0.0, 1.0)
	var stream1_carve := stream1_mask * stream1_mask * 4.2

	var stream2_center := cos(wz * 0.015) * 16.0 + 118.0
	var stream2_dist := absf(wx - stream2_center)
	var stream2_mask := clampf(1.0 - (stream2_dist / 11.0), 0.0, 1.0) * clampf((wz - 210.0) / 400.0, 0.0, 1.0)
	var stream2_carve := stream2_mask * stream2_mask * 3.5

	var height: float = mountain_height - stream1_carve - stream2_carve

	if in_vagen_trough > 0.001:
		height = lerpf(height, vagen_depth, in_vagen_trough)

	if puddefjord_dist > 0.001:
		height = lerpf(height, vagen_depth * 1.5, puddefjord_dist)

	if bryggen_weight > 0.01:
		height = lerpf(height, bryggen_shelf_height + 1.2, bryggen_weight * 0.78)

	if height > 0.5 and bryggen_weight < 0.72:
		height += detail_val * (1.0 - bryggen_weight * 0.85)

	return height

## Pure deterministic mathematical height function for Bergen at coordinate (x, z)
## Incorporates smooth valley plain leveling pads under city blocks and farmsteads.
func sample_height(x: float, z: float) -> float:
	var height := _sample_natural_valley_height(x, z)

	# Apply registered flat valley plain pads (smoothstep transition so no harsh terrain seams occur)
	for pad in _settlement_pads:
		var px: float = pad["x"]
		var pz: float = pad["z"]
		var dist := Vector2(x - px, z - pz).length()
		var out_r: float = pad["outer_radius"]
		if dist < out_r:
			var in_r: float = pad["inner_radius"]
			var target_y: float = pad["target_y"]
			var w: float = 1.0 - smoothstep(in_r, out_r, dist)
			height = lerpf(height, target_y, w * 0.94)

	return height

## Solves for the flattest plain positions in each valley region and registers leveling pads
func _compute_settlement_plains() -> void:
	_settlement_pads.clear()

	# 1. Historic Bryggen Wharf & Rear Valley Town District Pad
	_settlement_pads.append({
		"name": "Bryggen City & Wharf Plain",
		"x": 82.0,
		"z": 80.0,
		"target_y": bryggen_shelf_height,
		"inner_radius": 38.0,
		"outer_radius": 58.0,
		"is_farm": false
	})

	# 2. Candidate Valley Regions for Farmsteads (searched via 9-point flatness kernel)
	var candidate_valley_zones := [
		{"name": "Sandviken Dal Gård", "search_x": 142.0, "search_z": -185.0},
		{"name": "Bryggen Valley Gård", "search_x": 146.0, "search_z": 168.0},
		{"name": "Markov Valley Gård", "search_x": 144.0, "search_z": 365.0},
		{"name": "Lungegård Plain Gård", "search_x": 148.0, "search_z": 560.0}
	]

	for zone in candidate_valley_zones:
		var best_pos := _find_flattest_valley_spot(zone["search_x"], zone["search_z"], 26.0, 18.0)
		var base_y := clampf(_sample_natural_valley_height(best_pos.x, best_pos.y), bryggen_shelf_height + 0.6, 16.0)
		_settlement_pads.append({
			"name": zone["name"],
			"x": best_pos.x,
			"z": best_pos.y,
			"target_y": base_y,
			"inner_radius": 22.0,
			"outer_radius": 38.0,
			"is_farm": true
		})

## Searches a valley neighborhood for the coordinate with minimal slope and height variance
func _find_flattest_valley_spot(center_x: float, center_z: float, search_radius: float, footprint_r: float) -> Vector2:
	var best_pt := Vector2(center_x, center_z)
	var best_score := 999999.0

	for dx_step in range(-2, 3):
		for dz_step in range(-2, 3):
			var cx := center_x + float(dx_step) * (search_radius * 0.45)
			var cz := center_z + float(dz_step) * (search_radius * 0.45)
			var h_c := _sample_natural_valley_height(cx, cz)

			# Must be safely above wave crests and below steep mountain slopes
			if h_c < 2.2 or h_c > 24.0:
				continue
			if is_freshwater_stream(Vector3(cx, h_c, cz)):
				continue

			var max_dh := 0.0
			for ox in [-footprint_r, 0.0, footprint_r]:
				for oz in [-footprint_r, 0.0, footprint_r]:
					var h_s := _sample_natural_valley_height(cx + ox, cz + oz)
					max_dh = maxf(max_dh, absf(h_s - h_c))

			if max_dh < best_score:
				best_score = max_dh
				best_pt = Vector2(cx, cz)

	return best_pt

## Returns true if the position has access to drinkable freshwater (streams/springs/wells)
func is_freshwater_stream(world_pos: Vector3) -> bool:
	if world_pos.y <= sea_level:
		return false

	var wx := world_pos.x
	var wz := world_pos.z

	var stream1_center := sin(wz * 0.02) * 20.0 + (wz * 0.4 + 195.0)
	if absf(wx - stream1_center) < 8.0 and wz > -100.0 and wz < 500.0:
		return true

	var stream2_center := cos(wz * 0.015) * 16.0 + 118.0
	if absf(wx - stream2_center) < 7.0 and wz > 210.0 and wz < 700.0:
		return true

	return false

## Generates the 3D terrain ArrayMesh
func generate_terrain() -> void:
	if not _base_noise:
		_init_noise()
	elif _settlement_pads.is_empty():
		_compute_settlement_plains()

	if terrain_mesh_instance == null:
		terrain_mesh_instance = get_node_or_null("TerrainMesh") as MeshInstance3D
		if terrain_mesh_instance == null:
			terrain_mesh_instance = MeshInstance3D.new()
			terrain_mesh_instance.name = "TerrainMesh"
			add_child(terrain_mesh_instance)
			terrain_mesh_instance.owner = self

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_x := world_size.x * 0.5
	var half_z := world_size.y * 0.5
	var step_x := world_size.x / float(mesh_resolution)
	var step_z := world_size.y / float(mesh_resolution)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()

	var total_verts := (mesh_resolution + 1) * (mesh_resolution + 1)
	vertices.resize(total_verts)
	normals.resize(total_verts)
	colors.resize(total_verts)
	uvs.resize(total_verts)

	var vert_index := 0
	for iz in range(mesh_resolution + 1):
		var z := -half_z + float(iz) * step_z
		for ix in range(mesh_resolution + 1):
			var x := -half_x + float(ix) * step_x
			var y := sample_height(x, z)

			vertices[vert_index] = Vector3(x, y, z)
			uvs[vert_index] = Vector2(float(ix) / float(mesh_resolution), float(iz) / float(mesh_resolution))
			vert_index += 1

	vert_index = 0
	for iz in range(mesh_resolution + 1):
		for ix in range(mesh_resolution + 1):
			var idx := iz * (mesh_resolution + 1) + ix
			var current := vertices[idx]

			var left := vertices[iz * (mesh_resolution + 1) + maxi(0, ix - 1)]
			var right := vertices[iz * (mesh_resolution + 1) + mini(mesh_resolution, ix + 1)]
			var down := vertices[maxi(0, iz - 1) * (mesh_resolution + 1) + ix]
			var up := vertices[mini(mesh_resolution, iz + 1) * (mesh_resolution + 1) + ix]

			var tangent_x := (right - left).normalized()
			var tangent_z := (up - down).normalized()
			var normal := tangent_z.cross(tangent_x).normalized()
			if normal.y < 0.0:
				normal = -normal
			normals[idx] = normal

			var y := current.y
			var slope := 1.0 - clampf(normal.y, 0.0, 1.0)
			var color: Color
			if y <= 0.2:
				color = Color(0.20, 0.23, 0.22) # Muddy fjord seabed / shoreline
			elif y <= 4.0 and absf(current.x - 82.0) < 42.0 and current.z > 20.0 and current.z < 140.0:
				color = Color(0.42, 0.38, 0.31) # Wharf gravel & town street level
			else:
				var base_grass := Color(0.26, 0.46, 0.18) # Lush Bergen valley meadow green
				var highland_moss := Color(0.35, 0.44, 0.28) # Sub-alpine moss and pine
				var mountain_stone := Color(0.44, 0.46, 0.48) # Cold granite slate / crag

				if y < 85.0:
					color = base_grass
				elif y < 200.0:
					var t := (y - 85.0) / 115.0
					color = base_grass.lerp(highland_moss, t)
				else:
					var t := clampf((y - 200.0) / 100.0, 0.0, 1.0)
					color = highland_moss.lerp(mountain_stone, t)

				if slope > 0.36:
					var cliff_factor := clampf((slope - 0.36) / 0.25, 0.0, 1.0)
					color = color.lerp(mountain_stone, cliff_factor)

			colors[idx] = color

	for iz in range(mesh_resolution):
		for ix in range(mesh_resolution):
			var row1 := iz * (mesh_resolution + 1)
			var row2 := (iz + 1) * (mesh_resolution + 1)

			var v0 := row1 + ix
			var v1 := row1 + (ix + 1)
			var v2 := row2 + ix
			var v3 := row2 + (ix + 1)

			st.set_normal(normals[v0])
			st.set_color(colors[v0])
			st.set_uv(uvs[v0])
			st.add_vertex(vertices[v0])

			st.set_normal(normals[v1])
			st.set_color(colors[v1])
			st.set_uv(uvs[v1])
			st.add_vertex(vertices[v1])

			st.set_normal(normals[v2])
			st.set_color(colors[v2])
			st.set_uv(uvs[v2])
			st.add_vertex(vertices[v2])

			st.set_normal(normals[v1])
			st.set_color(colors[v1])
			st.set_uv(uvs[v1])
			st.add_vertex(vertices[v1])

			st.set_normal(normals[v3])
			st.set_color(colors[v3])
			st.set_uv(uvs[v3])
			st.add_vertex(vertices[v3])

			st.set_normal(normals[v2])
			st.set_color(colors[v2])
			st.set_uv(uvs[v2])
			st.add_vertex(vertices[v2])

	st.generate_tangents()
	var mesh := st.commit()
	terrain_mesh_instance.mesh = mesh

	terrain_mesh_instance.material_override = _create_terrain_material()
	_ensure_terrain_collision(mesh)
	_ensure_water_plane()

	# Scatter dense multi-biome forests & understory vegetation
	_scatter_forests()

	# Scatter bog iron ore deposits in wetland basins along mountain streams
	_scatter_bog_ore_deposits()

	# Generate piece-by-piece valley farmsteads on verified flat valley plains
	_generate_farmsteads()

	# Generate piece-by-piece Bryggen Hanseatic Wharf & Valley Town District
	_generate_bryggen_waterfront()

	# Scatter wildlife & livestock across distinct ecosystem zones
	_scatter_wildlife()

	# Scatter high-performance multi-tier grass with biotic sheep grazing
	_scatter_grass()

func _scatter_grass() -> void:
	var grass_mgr = load("res://scripts/environment/grass_manager.gd")
	if grass_mgr:
		grass_mgr.populate_grass(self, _settlement_pads, world_seed)

func _generate_bryggen_waterfront() -> void:
	var bryggen_container := get_node_or_null("BryggenWaterfront") as Node3D
	if bryggen_container:
		bryggen_container.free()

	var bx: float = 62.0
	var bz: float = 80.0
	var by: float = sample_height(bx, bz)

	var bryggen_node := BryggenWharfGenerator.create_bryggen_waterfront(Vector3(bx, by, bz), self)
	bryggen_node.name = "BryggenWaterfront"
	add_child(bryggen_node)
	bryggen_node.owner = self

	var campfire_script = load("res://scripts/survival/campfire_interactable.gd")
	if campfire_script:
		var old_cf1 := get_node_or_null("BryggenCampfire")
		if old_cf1:
			old_cf1.free()
		var cf_bryggen: Node3D = campfire_script.new()
		cf_bryggen.name = "BryggenCampfire"
		add_child(cf_bryggen)
		cf_bryggen.global_position = Vector3(68.0, sample_height(68.0, 88.0) + 0.1, 88.0)

		var old_cf2 := get_node_or_null("StarterCampfire")
		if old_cf2:
			old_cf2.free()
		var cf_starter: Node3D = campfire_script.new()
		cf_starter.name = "StarterCampfire"
		add_child(cf_starter)
		var sy := sample_height(148.0, 146.0)
		cf_starter.global_position = Vector3(148.0, sy, 146.0)

func _create_terrain_material() -> Material:
	if terrain_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = terrain_shader
		if grass_texture != null:
			mat.set_shader_parameter("grass_albedo", grass_texture)
		if grass_normal_map != null:
			mat.set_shader_parameter("grass_normal", grass_normal_map)
		if rock_texture != null:
			mat.set_shader_parameter("rock_albedo", rock_texture)
		if rock_normal_map != null:
			mat.set_shader_parameter("rock_normal", rock_normal_map)
		if scree_texture != null:
			mat.set_shader_parameter("scree_albedo", scree_texture)
		if scree_normal_map != null:
			mat.set_shader_parameter("scree_normal", scree_normal_map)
		if macro_noise_map != null:
			mat.set_shader_parameter("macro_noise", macro_noise_map)
		return mat

	var fallback := StandardMaterial3D.new()
	fallback.vertex_color_use_as_albedo = true
	fallback.albedo_texture = grass_texture
	fallback.normal_enabled = true
	fallback.normal_texture = grass_normal_map
	fallback.uv1_scale = Vector3(120.0, 120.0, 1.0)
	fallback.roughness = 0.85
	fallback.cull_mode = BaseMaterial3D.CULL_BACK
	return fallback

func _ensure_water_plane() -> void:
	if water_plane_instance == null:
		water_plane_instance = get_node_or_null("FjordWater") as MeshInstance3D
		if water_plane_instance == null:
			water_plane_instance = MeshInstance3D.new()
			water_plane_instance.name = "FjordWater"
			add_child(water_plane_instance)
			water_plane_instance.owner = self

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = world_size * 1.1
	plane_mesh.subdivide_width = 128
	plane_mesh.subdivide_depth = 128
	water_plane_instance.mesh = plane_mesh
	water_plane_instance.position.y = sea_level

	var water_shader = load("res://shaders/fjord_water.gdshader")
	if water_shader:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = water_shader

		var noise1 := FastNoiseLite.new()
		noise1.seed = 1360
		noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise1.frequency = 0.04
		var norm_tex1 := NoiseTexture2D.new()
		norm_tex1.seamless = true
		norm_tex1.as_normal_map = true
		norm_tex1.bump_strength = 5.0
		norm_tex1.width = 256
		norm_tex1.height = 256
		norm_tex1.noise = noise1

		var noise2 := FastNoiseLite.new()
		noise2.seed = 1360 + 101
		noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise2.frequency = 0.07
		var norm_tex2 := NoiseTexture2D.new()
		norm_tex2.seamless = true
		norm_tex2.as_normal_map = true
		norm_tex2.bump_strength = 4.0
		norm_tex2.width = 256
		norm_tex2.height = 256
		norm_tex2.noise = noise2

		shader_mat.set_shader_parameter("wave_normal1", norm_tex1)
		shader_mat.set_shader_parameter("wave_normal2", norm_tex2)
		shader_mat.set_shader_parameter("wave_speed", 0.9)
		shader_mat.set_shader_parameter("wave_amplitude", 0.22)
		shader_mat.set_shader_parameter("wave_frequency", 0.045)
		shader_mat.set_shader_parameter("foam_distance", 0.75)
		water_plane_instance.material_override = shader_mat
	else:
		var water_mat := StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.10, 0.22, 0.28, 0.82)
		water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_mat.roughness = 0.15
		water_mat.metallic = 0.1
		water_plane_instance.material_override = water_mat

## Computes dynamic fjord water height at world position (x, z) synchronized with the shader
func sample_water_height(x: float, z: float, time_sec: float = -1.0) -> float:
	var t: float = time_sec
	if t < 0.0:
		t = float(Time.get_ticks_msec()) * 0.001

	var wave_speed := 0.9
	var wave_amplitude := 0.22
	var wave_frequency := 0.045

	var effective_time: float = t * wave_speed

	var dir1 := Vector2(0.8, 0.6)
	var k1 := wave_frequency
	var phase1: float = (dir1.x * x + dir1.y * z) * k1 + effective_time * 1.2
	var w1: float = sin(phase1)

	var dir2 := Vector2(-0.6, 0.8)
	var k2 := wave_frequency * 1.7
	var phase2: float = (dir2.x * x + dir2.y * z) * k2 + effective_time * 1.5
	var w2: float = sin(phase2)

	var dir3 := Vector2(0.35, -0.93)
	var k3 := wave_frequency * 3.2
	var phase3: float = (dir3.x * x + dir3.y * z) * k3 + effective_time * 2.1
	var w3: float = sin(phase3)

	var wave_h: float = (w1 * 0.55 + w2 * 0.30 + w3 * 0.15) * wave_amplitude
	return sea_level + wave_h

func _generate_farmsteads() -> void:
	var farmsteads_container := get_node_or_null("Farmsteads") as Node3D
	if farmsteads_container == null:
		farmsteads_container = Node3D.new()
		farmsteads_container.name = "Farmsteads"
		add_child(farmsteads_container)
		farmsteads_container.owner = self
	else:
		for child in farmsteads_container.get_children():
			child.free()

	var farm_id := 1
	for pad in _settlement_pads:
		if not pad.get("is_farm", false):
			continue
		var fx: float = pad["x"]
		var fz: float = pad["z"]
		var fy: float = sample_height(fx, fz)

		var farm_node := FarmsteadGenerator.create_farmstead(farm_id, Vector3(fx, fy, fz), pad["name"], self)
		farmsteads_container.add_child(farm_node)
		farm_id += 1

func _scatter_wildlife() -> void:
	var wildlife_container := get_node_or_null("Wildlife") as Node3D
	if wildlife_container == null:
		wildlife_container = Node3D.new()
		wildlife_container.name = "Wildlife"
		add_child(wildlife_container)
		wildlife_container.owner = self
	else:
		for child in wildlife_container.get_children():
			child.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 777

	var farm_centers: Array[Vector3] = []
	for pad in _settlement_pads:
		if pad.get("is_farm", false):
			var fx: float = pad["x"]
			var fz: float = pad["z"]
			farm_centers.append(Vector3(fx, sample_height(fx, fz), fz))

	# 1. Mountain Wolves (Confined strictly to crags above 80m altitude)
	var wolf_pack_centers: Array[Vector3] = [
		Vector3(380.0, 0.0, 200.0)
	]

	var wolf_total := 0
	for p_idx in range(wolf_pack_centers.size()):
		var p_center: Vector3 = wolf_pack_centers[p_idx]
		var pack_size: int = 3
		for w_i in range(pack_size):
			var wx: float = p_center.x + rng.randf_range(-15.0, 15.0)
			var wz: float = p_center.z + rng.randf_range(-15.0, 15.0)
			var wy: float = sample_height(wx, wz)

			if wy >= 80.0:
				var wolf := CharacterBody3D.new()
				wolf.name = "Wolf_%d" % wolf_total
				wolf.set_script(load("res://scripts/fauna/wolf_ai.gd"))
				wolf.set("mountain_home", Vector3(p_center.x, sample_height(p_center.x, p_center.z), p_center.z))
				wolf.set("min_mountain_altitude", 80.0)

				wildlife_container.add_child(wolf)
				wolf.add_to_group("wolf")
				wolf.add_to_group("fauna")
				wolf.global_position = Vector3(wx, wy, wz)
				wolf_total += 1

	# 2. Docile Norwegian Cattle (Cows grazing inside/adjacent to valley farm pastures)
	var cow_total := 0
	for farm_idx in range(farm_centers.size()):
		var fc: Vector3 = farm_centers[farm_idx]
		var cow := CharacterBody3D.new()
		cow.name = "Cow_%d" % cow_total
		cow.set_script(load("res://scripts/fauna/cow_ai.gd"))

		var cx := fc.x + rng.randf_range(-4.0, 5.0)
		var cz := fc.z + rng.randf_range(2.0, 8.0)
		var cy := sample_height(cx, cz)
		cow.set("home_position", fc)
		cow.set("pasture_radius", 18.0)

		wildlife_container.add_child(cow)
		cow.add_to_group("cow")
		cow.add_to_group("fauna")
		cow.add_to_group("livestock")
		cow.global_position = Vector3(cx, cy, cz)
		cow_total += 1

	# 3. Old Norwegian Short-Tail Sheep (Villsau grazing on valley meadows near farms)
	var sheep_total := 0
	for farm_idx in range(farm_centers.size()):
		var fc: Vector3 = farm_centers[farm_idx]
		var meadow_center := fc + Vector3(18.0, 0, rng.randf_range(-6.0, 6.0))
		var sheep := CharacterBody3D.new()
		sheep.name = "Sheep_%d" % sheep_total
		sheep.set_script(load("res://scripts/fauna/sheep_ai.gd"))

		var sx := meadow_center.x + rng.randf_range(-5.0, 5.0)
		var sz := meadow_center.z + rng.randf_range(-5.0, 5.0)
		var sy := sample_height(sx, sz)
		sheep.set("home_position", meadow_center)
		sheep.set("pasture_radius", 20.0)

		var fleece_variations := [
			Color(0.88, 0.86, 0.82),
			Color(0.55, 0.53, 0.50),
			Color(0.25, 0.23, 0.22)
		]
		sheep.set("fleece_color", fleece_variations[farm_idx % fleece_variations.size()])

		wildlife_container.add_child(sheep)
		sheep.add_to_group("sheep")
		sheep.add_to_group("fauna")
		sheep.add_to_group("livestock")
		sheep.global_position = Vector3(sx, sy, sz)
		sheep_total += 1

	# 4. Norwegian Mountain Hares (Rabbits hopping in perimeter brush outside farms)
	var rabbit_total := 0
	for farm_idx in range(farm_centers.size()):
		var fc: Vector3 = farm_centers[farm_idx]
		var rabbit := CharacterBody3D.new()
		rabbit.name = "Rabbit_%d" % rabbit_total
		rabbit.set_script(load("res://scripts/fauna/rabbit_ai.gd"))

		var angle := rng.randf() * 2.0 * PI
		var dist := rng.randf_range(18.0, 30.0)
		var rx := fc.x + cos(angle) * dist
		var rz := fc.z + sin(angle) * dist
		var ry := sample_height(rx, rz)

		rabbit.set("home_position", Vector3(rx, ry, rz))
		rabbit.set("roam_radius", 25.0)

		wildlife_container.add_child(rabbit)
		rabbit.add_to_group("rabbit")
		rabbit.add_to_group("fauna")
		rabbit.global_position = Vector3(rx, ry, rz)
		rabbit_total += 1

	# 5. Red Deer (Peaceful herbivores grazing in lower valley & woods)
	for i in range(4):
		var dx := rng.randf_range(45.0, 175.0)
		var dz := rng.randf_range(40.0, 420.0)
		var dy := sample_height(dx, dz)

		if dy > 1.8 and dy < 60.0:
			var deer := CharacterBody3D.new()
			deer.name = "Deer_%d" % i
			deer.set_script(load("res://scripts/fauna/deer_ai.gd"))

			var mi_body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.35
			cap.height = 1.4
			mi_body.mesh = cap
			mi_body.rotation.x = deg_to_rad(90.0)
			mi_body.position.y = 0.9

			var mat_deer := StandardMaterial3D.new()
			mat_deer.albedo_color = Color(0.58, 0.38, 0.22)
			mi_body.material_override = mat_deer
			deer.add_child(mi_body)

			var mi_head := MeshInstance3D.new()
			var box_head := BoxMesh.new()
			box_head.size = Vector3(0.25, 0.35, 0.45)
			mi_head.mesh = box_head
			mi_head.position = Vector3(0, 1.4, -0.7)
			mi_head.material_override = mat_deer
			deer.add_child(mi_head)

			var col := CollisionShape3D.new()
			var cap_col := CapsuleShape3D.new()
			cap_col.radius = 0.45
			cap_col.height = 1.4
			col.shape = cap_col
			col.position.y = 0.9
			deer.add_child(col)

			wildlife_container.add_child(deer)
			deer.global_position = Vector3(dx, dy, dz)

func _ensure_terrain_collision(mesh: ArrayMesh) -> void:
	for child in terrain_mesh_instance.get_children():
		if child is StaticBody3D:
			child.queue_free()

	var static_body := StaticBody3D.new()
	static_body.name = "TerrainStaticBody"
	terrain_mesh_instance.add_child(static_body)
	static_body.owner = self

	var col_shape := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape()
	if trimesh is ConcavePolygonShape3D:
		trimesh.backface_collision = true
	col_shape.shape = trimesh
	static_body.add_child(col_shape)
	col_shape.owner = self

static func _build_compound_tree_mesh(is_spruce: bool) -> ArrayMesh:
	return VegetationManager.build_detailed_tree_mesh(1 if is_spruce else 0)

func _scatter_forests() -> void:
	VegetationManager.populate_dense_vegetation(self, _settlement_pads, world_seed)

func _scatter_bog_ore_deposits() -> void:
	var bog_container := get_node_or_null("BogOreDeposits") as Node3D
	if bog_container:
		bog_container.free()

	bog_container = Node3D.new()
	bog_container.name = "BogOreDeposits"
	add_child(bog_container)
	bog_container.owner = self

	var deposit_locations := [
		Vector2(45.0, 85.0),
		Vector2(65.0, 140.0),
		Vector2(85.0, 195.0),
		Vector2(110.0, 110.0),
		Vector2(35.0, 230.0),
		Vector2(95.0, 60.0)
	]

	for i in range(deposit_locations.size()):
		var loc: Vector2 = deposit_locations[i]
		var gh: float = sample_height(loc.x, loc.y)
		if gh >= sea_level + 0.8 and gh <= sea_level + 35.0:
			var deposit := BogOreDeposit.new()
			deposit.name = "BogDeposit_%d" % i
			bog_container.add_child(deposit)
			deposit.global_position = Vector3(loc.x, gh, loc.y)
