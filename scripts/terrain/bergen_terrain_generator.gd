@tool
class_name BergenTerrainGenerator
extends Node3D

## Procedural, Deterministic Bergen 1360 Topography Generator
## Models the geography of Bergen:
## - Vågen harbour bay
## - Nordnes peninsula
## - Bryggen terrace bank
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
@export var bryggen_shelf_width: float = 90.0 ## Flat shoreline strip for medieval tenements
@export var bryggen_shelf_height: float = 1.8 ## Slightly above high tide

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

## Pure deterministic mathematical height function for Bergen at coordinate (x, z)
func sample_height(x: float, z: float) -> float:
	# Apply domain warping to simulate glacial fjord scraping
	var wx: float = x
	var wz: float = z
	var warp_offset_x := _base_noise.get_noise_2d(x * 0.8, z * 0.8) * 35.0
	var warp_offset_z := _base_noise.get_noise_2d(z * 0.8 + 500.0, x * 0.8) * 35.0
	wx += warp_offset_x
	wz += warp_offset_z

	# Geographic orientation:
	# Center (0, 0) is the mouth of Vågen bay.
	# +X is East (towards Mount Fløyen)
	# -X is West (towards Puddefjorden and Nordnes)
	# +Z is South-East (inland, head of Vågen bay, towards Store Lungegårdsvann)
	# -Z is North-West (out towards Byfjorden and the North Sea)

	# 1. Macro Mountain Massif: Fløyen on the East (+X)
	# Ramp height steeply when moving east of x = 120m
	var fløyen_dist := maxf(0.0, wx - 110.0)
	var mountain_ramp := clampf(fløyen_dist / 400.0, 0.0, 1.0)
	# Non-linear cliff ramp: smoothstep
	mountain_ramp = mountain_ramp * mountain_ramp * (3.0 - 2.0 * mountain_ramp)

	var ridge_val := (_ridge_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	var base_val := (_base_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	var detail_val := _detail_noise.get_noise_2d(x, z) * 3.5

	var mountain_height := mountain_ramp * (max_mountain_height * (0.65 * ridge_val + 0.35 * base_val))

	# 2. Fjord Carving: Vågen Bay
	# Vågen extends roughly from (0, -200) to (0, +550) along Z
	var vagen_center_x := sin(wz * 0.003) * 60.0 # slight curve of the bay
	var dist_to_vagen_axis := absf(wx - vagen_center_x)
	var vagen_z_factor := clampf((wz + 200.0) / vagen_length, 0.0, 1.0)
	
	# Bay carve mask (tapering at the head of the bay)
	var vagen_half_width := (vagen_width * 0.5) * (1.0 - 0.25 * vagen_z_factor)
	var in_vagen_trough := 1.0 - smoothstep(vagen_half_width * 0.4, vagen_half_width * 1.2, dist_to_vagen_axis)
	if wz < -250.0:
		# Open sea / Byfjorden to the north
		in_vagen_trough = maxf(in_vagen_trough, clampf((-wz - 250.0) / 150.0, 0.0, 1.0))
	elif wz > (vagen_length - 100.0):
		# Head of the bay transitions into marshy valley
		var falloff := clampf((wz - (vagen_length - 100.0)) / 120.0, 0.0, 1.0)
		in_vagen_trough *= (1.0 - falloff)

	# 3. Bryggen Shoreline Terrace:
	# Flat strip along north-east bank of Vågen (wx between 40m and 120m, wz between -100m and 600m)
	var is_bryggen_zone := false
	var bryggen_weight := 0.0
	if wx >= 35.0 and wx <= 140.0 and wz >= -120.0 and wz <= 650.0:
		var x_shelf_factor := 1.0 - absf((wx - 85.0) / 55.0)
		var z_shelf_factor := clampf(1.0 - absf((wz - 265.0) / 385.0), 0.0, 1.0)
		bryggen_weight = clampf(x_shelf_factor * z_shelf_factor, 0.0, 1.0)

	# 4. Puddefjorden & Western Fjord:
	# Deep water to the west (wx < -380m)
	var puddefjord_dist := clampf((-wx - 300.0) / 200.0, 0.0, 1.0)

	# 5. Mountain Streams & Gullies (Glacial freshwater runoff from Fløyen)
	# Stream 1: Descending from Sandviksfjellet into northern Vågen
	var stream1_center := sin(wz * 0.02) * 20.0 + (wz * 0.4 + 180.0)
	var stream1_dist := absf(wx - stream1_center)
	var stream1_mask := clampf(1.0 - (stream1_dist / 14.0), 0.0, 1.0) * clampf((wz + 100.0) / 300.0, 0.0, 1.0)
	var stream1_carve := stream1_mask * stream1_mask * 4.5

	# Stream 2: Fløyen southern creek feeding into the head of the valley
	var stream2_center := cos(wz * 0.015) * 18.0 + 120.0
	var stream2_dist := absf(wx - stream2_center)
	var stream2_mask := clampf(1.0 - (stream2_dist / 12.0), 0.0, 1.0) * clampf((wz - 200.0) / 400.0, 0.0, 1.0)
	var stream2_carve := stream2_mask * stream2_mask * 3.8

	# 6. Composite Elevation Calculation
	var height: float = mountain_height - stream1_carve - stream2_carve

	# Carve Vågen
	if in_vagen_trough > 0.001:
		height = lerpf(height, vagen_depth, in_vagen_trough)

	# Carve Puddefjorden
	if puddefjord_dist > 0.001:
		height = lerpf(height, vagen_depth * 1.5, puddefjord_dist)

	# Flatten Bryggen terrace for wooden tenements
	if bryggen_weight > 0.01:
		height = lerpf(height, bryggen_shelf_height, bryggen_weight * 0.85)

	# Add rock and turf surface detail (suppressed in water and flat wharfs)
	if height > 0.5 and bryggen_weight < 0.8:
		height += detail_val

	return height

## Returns true if the position has access to drinkable freshwater (streams/springs/wells)
func is_freshwater_stream(world_pos: Vector3) -> bool:
	if world_pos.y <= sea_level:
		# Below sea level is saltwater fjord
		return false

	var wx := world_pos.x
	var wz := world_pos.z

	# Check proximity to stream 1
	var stream1_center := sin(wz * 0.02) * 20.0 + (wz * 0.4 + 180.0)
	if absf(wx - stream1_center) < 8.0 and wz > -100.0 and wz < 500.0:
		return true

	# Check proximity to stream 2
	var stream2_center := cos(wz * 0.015) * 18.0 + 120.0
	if absf(wx - stream2_center) < 7.0 and wz > 200.0 and wz < 700.0:
		return true

	return false


## Generates the 3D terrain ArrayMesh
func generate_terrain() -> void:
	if not _base_noise:
		_init_noise()

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

	# Precompute vertex grid
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

	# Compute vertex normals and slope-aware vertex colors
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
			# Normal pointing UP (+Y): Z cross X in right-handed coordinate system
			var normal := tangent_z.cross(tangent_x).normalized()
			if normal.y < 0.0:
				normal = -normal
			normals[idx] = normal

			# Slope & elevation-aware biome coloring
			var y := current.y
			var slope := 1.0 - clampf(normal.y, 0.0, 1.0)
			var color: Color
			if y <= 0.2:
				color = Color(0.20, 0.23, 0.22) # Muddy fjord seabed / shoreline
			elif y <= 4.0 and absf(current.x - 85.0) < 55.0 and current.z > -100.0 and current.z < 650.0:
				color = Color(0.42, 0.38, 0.31) # Wharf gravel, timber foundation level
			else:
				var base_grass := Color(0.26, 0.46, 0.18) # Lush Bergen meadow green
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

				# Steep slopes expose rock cliffs (Mount Fløyen & Sandviksfjellet)
				if slope > 0.36:
					var cliff_factor := clampf((slope - 0.36) / 0.25, 0.0, 1.0)
					color = color.lerp(mountain_stone, cliff_factor)

			colors[idx] = color

	# Build triangle faces with Counter-Clockwise (CCW) winding order for upward-facing triangles
	for iz in range(mesh_resolution):
		for ix in range(mesh_resolution):
			var row1 := iz * (mesh_resolution + 1)
			var row2 := (iz + 1) * (mesh_resolution + 1)

			var v0 := row1 + ix
			var v1 := row1 + (ix + 1)
			var v2 := row2 + ix
			var v3 := row2 + (ix + 1)

			# Triangle 1 (v0 -> v1 -> v2) front-facing CCW
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

			# Triangle 2 (v1 -> v3 -> v2) front-facing CCW
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

	# Assign high-fidelity atmospheric shader material with procedural grass & rock textures
	terrain_mesh_instance.material_override = _create_terrain_material()

	# Generate physical StaticBody3D collision shape from terrain mesh
	_ensure_terrain_collision(mesh)

	# Setup Water Plane at y = sea_level (y = 0.0)
	_ensure_water_plane()

	# Scatter harvestable trees deterministically across the terrain
	_scatter_forests()

	# Generate authentic medieval Bergen farmsteads on fertile lower shelves
	_generate_farmsteads()

	# Scatter wildlife & livestock across distinct ecosystem zones
	_scatter_wildlife()

func _create_terrain_material() -> Material:
	var fallback := StandardMaterial3D.new()
	fallback.vertex_color_use_as_albedo = true
	fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fallback.roughness = 0.85
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	plane_mesh.subdivide_width = 16
	plane_mesh.subdivide_depth = 16
	water_plane_instance.mesh = plane_mesh
	water_plane_instance.position.y = sea_level

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.10, 0.22, 0.28, 0.82)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.15
	water_mat.metallic = 0.1
	water_plane_instance.material_override = water_mat

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

	var farm_definitions := [
		{"name": "Sandviken Gård", "x": 160.0, "z": -200.0},
		{"name": "Bryggen Hinterland Gård", "x": 160.0, "z": 150.0},
		{"name": "Southern Valley Gård", "x": 160.0, "z": 580.0}
	]

	for i in range(farm_definitions.size()):
		var farm_def: Dictionary = farm_definitions[i]
		var fx: float = farm_def["x"]
		var fz: float = farm_def["z"]
		var fy: float = sample_height(fx, fz)

		var farm_node := FarmsteadGenerator.create_farmstead(i + 1, Vector3(fx, fy, fz), farm_def["name"], self)
		farmsteads_container.add_child(farm_node)

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

	var farm_centers := [
		Vector3(160.0, sample_height(160.0, -200.0), -200.0),
		Vector3(160.0, sample_height(160.0, 150.0), 150.0),
		Vector3(160.0, sample_height(160.0, 580.0), 580.0)
	]

	# -------------------------------------------------------------------------
	# 1. Mountain Wolves (Confined strictly to crags above 80m altitude)
	# -------------------------------------------------------------------------
	# Packs lurking among the rocky ledges and pines of Fløyen & Sandviksfjellet
	var wolf_pack_centers: Array[Vector3] = [
		Vector3(340.0, 0.0, 200.0)  # Fløyen Mountain Plateau Ledges
	]

	var wolf_total := 0
	for p_idx in range(wolf_pack_centers.size()):
		var p_center: Vector3 = wolf_pack_centers[p_idx]
		var pack_size: int = 3
		for w_i in range(pack_size):
			var wx: float = p_center.x + rng.randf_range(-15.0, 15.0)
			var wz: float = p_center.z + rng.randf_range(-15.0, 15.0)
			var wy: float = sample_height(wx, wz)

			# Strict altitude requirement: must be >= 80m
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

	# -------------------------------------------------------------------------
	# 2. Docile Norwegian Cattle (Cows grazing inside/adjacent to farm pastures)
	# -------------------------------------------------------------------------
	var cow_total := 0
	for farm_idx in range(farm_centers.size()):
		var fc: Vector3 = farm_centers[farm_idx]
		for c_i in range(1):
			var cow := CharacterBody3D.new()
			cow.name = "Cow_%d" % cow_total
			cow.set_script(load("res://scripts/fauna/cow_ai.gd"))

			var cx := fc.x + rng.randf_range(-6.0, 6.0)
			var cz := fc.z + rng.randf_range(-6.0, 6.0)
			var cy := sample_height(cx, cz)
			cow.set("home_position", fc)
			cow.set("pasture_radius", 18.0)

			wildlife_container.add_child(cow)
			cow.add_to_group("cow")
			cow.add_to_group("fauna")
			cow.add_to_group("livestock")
			cow.global_position = Vector3(cx, cy, cz)
			cow_total += 1

	# -------------------------------------------------------------------------
	# 3. Old Norwegian Short-Tail Sheep (Villsau grazing on hillside meadows near farms)
	# -------------------------------------------------------------------------
	var sheep_total := 0
	for farm_idx in range(farm_centers.size()):
		var fc: Vector3 = farm_centers[farm_idx]
		var meadow_center := fc + Vector3(18.0, 0, rng.randf_range(-6.0, 6.0))
		for s_i in range(1):
			var sheep := CharacterBody3D.new()
			sheep.name = "Sheep_%d" % sheep_total
			sheep.set_script(load("res://scripts/fauna/sheep_ai.gd"))

			# Grazing up along the hillside meadow above the farm
			var sx := meadow_center.x + rng.randf_range(-6.0, 6.0)
			var sz := meadow_center.z + rng.randf_range(-6.0, 6.0)
			var sy := sample_height(sx, sz)
			sheep.set("home_position", meadow_center)
			sheep.set("pasture_radius", 20.0)

			# Fleece variations (natural off-white, heather grey, black)
			var fleece_variations := [
				Color(0.88, 0.86, 0.82), # Oatmeal white
				Color(0.55, 0.53, 0.50), # Heather grey
				Color(0.25, 0.23, 0.22)  # Charcoal black
			]
			sheep.set("fleece_color", fleece_variations[farm_idx % fleece_variations.size()])

			wildlife_container.add_child(sheep)
			sheep.add_to_group("sheep")
			sheep.add_to_group("fauna")
			sheep.add_to_group("livestock")
			sheep.global_position = Vector3(sx, sy, sz)
			sheep_total += 1

	# -------------------------------------------------------------------------
	# 4. Norwegian Mountain Hares (Rabbits hopping in brush & perimeter outside farms)
	# -------------------------------------------------------------------------
	var rabbit_total := 0
	for farm_idx in range(farm_centers.size()):
		var fc: Vector3 = farm_centers[farm_idx]
		for r_i in range(1):
			var rabbit := CharacterBody3D.new()
			rabbit.name = "Rabbit_%d" % rabbit_total
			rabbit.set_script(load("res://scripts/fauna/rabbit_ai.gd"))

			# Hopping in perimeter brush 16m to 35m outside farm fences
			var angle := rng.randf() * 2.0 * PI
			var dist := rng.randf_range(16.0, 30.0)
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

	# -------------------------------------------------------------------------
	# 5. Red Deer (Peaceful herbivores grazing in lower valley & woods)
	# -------------------------------------------------------------------------
	for i in range(4):
		var dx := rng.randf_range(40.0, 180.0)
		var dz := rng.randf_range(50.0, 420.0)
		var dy := sample_height(dx, dz)

		if dy > 1.5 and dy < 60.0:
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
	# Clear existing collision children if any
	for child in terrain_mesh_instance.get_children():
		if child is StaticBody3D:
			child.queue_free()

	# Create static body and concave trimesh collision
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

func _scatter_forests() -> void:
	var trees_container := get_node_or_null("HarvestableTrees") as Node3D
	if trees_container:
		trees_container.queue_free()

	trees_container = Node3D.new()
	trees_container.name = "HarvestableTrees"
	add_child(trees_container)
	trees_container.owner = self

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 999

	# Scatter ~100 harvestable trees along the lower hillsides and valley
	var count := 100
	for i in range(count):
		# Concentrate trees in the valley and mountain slopes: x in [20, 220], z in [-50, 450]
		var tx := rng.randf_range(30.0, 200.0)
		var tz := rng.randf_range(-60.0, 480.0)
		var ty := sample_height(tx, tz)

		# Keep farmstead yards clear of trees
		var near_farm := false
		for f_pos in [Vector3(160.0, 0, -200.0), Vector3(160.0, 0, 150.0), Vector3(160.0, 0, 580.0)]:
			if Vector2(tx - f_pos.x, tz - f_pos.z).length() < 18.0:
				near_farm = true
				break
		if near_farm:
			continue

		# Only plant on solid land above sea level and below rocky crags
		if ty > 1.2 and ty < 90.0:
			var tree_node := StaticBody3D.new()
			tree_node.name = "Tree_%d" % i
			tree_node.set_script(load("res://scripts/environment/harvestable_tree.gd"))

			# 70% Spruce, 30% Birch
			var is_spruce := rng.randf() > 0.3
			tree_node.set("tree_type", 1 if is_spruce else 0)

			# Visual primitive mesh (Cylinder trunk + Cone canopy)
			var trunk_mesh := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.18
			cyl.bottom_radius = 0.25
			cyl.height = 4.0
			trunk_mesh.mesh = cyl
			trunk_mesh.position.y = 2.0

			var trunk_mat := StandardMaterial3D.new()
			trunk_mat.albedo_color = Color(0.32, 0.22, 0.14) if is_spruce else Color(0.9, 0.9, 0.85) # White bark for birch
			trunk_mesh.material_override = trunk_mat
			tree_node.add_child(trunk_mesh)

			var canopy_mesh := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 1.6 if is_spruce else 1.9
			cone.height = 5.0 if is_spruce else 3.5
			canopy_mesh.mesh = cone
			canopy_mesh.position.y = 5.2 if is_spruce else 4.0

			var canopy_mat := StandardMaterial3D.new()
			canopy_mat.albedo_color = Color(0.14, 0.28, 0.12) if is_spruce else Color(0.35, 0.52, 0.18)
			canopy_mesh.material_override = canopy_mat
			tree_node.add_child(canopy_mesh)

			# Collision shape for axe hits
			var col := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.4
			capsule.height = 4.0
			col.shape = capsule
			col.position.y = 2.0
			tree_node.add_child(col)

			trees_container.add_child(tree_node)
			tree_node.global_position = Vector3(tx, ty, tz)

