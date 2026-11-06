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
			terrain_mesh_instance.mesh = ArrayMesh.new()
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

			# Biome vertex coloring:
			# Water / shoreline: Blue-grey / sand
			# Lowland / wharf: Earth / timber brown
			# Grassy hillside: Bergen lush green
			# Cliff / Mountain peaks: Cold granite slate / lichen
			var color: Color
			if y <= 0.2:
				color = Color(0.22, 0.25, 0.23) # Muddy fjord seabed / shoreline
			elif y <= 4.0:
				color = Color(0.42, 0.38, 0.31) # Wharf gravel, timber foundation level
			elif y <= 85.0:
				color = Color(0.28, 0.44, 0.22) # Grass, meadows, birch forests
			elif y <= 210.0:
				color = Color(0.36, 0.40, 0.33) # Steep highland pine & moss
			else:
				color = Color(0.48, 0.49, 0.48) # Rocky summit crag (Fløyen / Sandviksfjellet)

			colors[vert_index] = color
			vert_index += 1

	# Compute vertex normals
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
			normals[idx] = normal

	# Build triangle faces
	for iz in range(mesh_resolution):
		for ix in range(mesh_resolution):
			var row1 := iz * (mesh_resolution + 1)
			var row2 := (iz + 1) * (mesh_resolution + 1)

			var v0 := row1 + ix
			var v1 := row1 + (ix + 1)
			var v2 := row2 + ix
			var v3 := row2 + (ix + 1)

			# Triangle 1
			st.set_normal(normals[v0])
			st.set_color(colors[v0])
			st.set_uv(uvs[v0])
			st.add_vertex(vertices[v0])

			st.set_normal(normals[v2])
			st.set_color(colors[v2])
			st.set_uv(uvs[v2])
			st.add_vertex(vertices[v2])

			st.set_normal(normals[v1])
			st.set_color(colors[v1])
			st.set_uv(uvs[v1])
			st.add_vertex(vertices[v1])

			# Triangle 2
			st.set_normal(normals[v1])
			st.set_color(colors[v1])
			st.set_uv(uvs[v1])
			st.add_vertex(vertices[v1])

			st.set_normal(normals[v2])
			st.set_color(colors[v2])
			st.set_uv(uvs[v2])
			st.add_vertex(vertices[v2])

			st.set_normal(normals[v3])
			st.set_color(colors[v3])
			st.set_uv(uvs[v3])
			st.add_vertex(vertices[v3])

	var mesh := st.commit()
	terrain_mesh_instance.mesh = mesh

	# Create simple vertex-color standard material if none assigned
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	terrain_mesh_instance.material_override = mat

	# Generate physical StaticBody3D collision shape from terrain mesh
	_ensure_terrain_collision(mesh)

	# Setup Water Plane at y = sea_level (y = 0.0)
	_ensure_water_plane()

	# Scatter harvestable trees deterministically across the terrain
	_scatter_forests()

	# Scatter wildlife (Red Deer & Wolves)
	_scatter_wildlife()

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

func _scatter_wildlife() -> void:
	var wildlife_container := get_node_or_null("Wildlife") as Node3D
	if wildlife_container:
		wildlife_container.queue_free()

	wildlife_container = Node3D.new()
	wildlife_container.name = "Wildlife"
	add_child(wildlife_container)
	wildlife_container.owner = self

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 777

	# 1. Spawn Red Deer (~12 deer)
	for i in range(12):
		var dx := rng.randf_range(40.0, 180.0)
		var dz := rng.randf_range(50.0, 420.0)
		var dy := sample_height(dx, dz)

		if dy > 1.5 and dy < 60.0:
			var deer := CharacterBody3D.new()
			deer.name = "Deer_%d" % i
			deer.set_script(load("res://scripts/fauna/deer_ai.gd"))

			# Deer Torso
			var mi_body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.35
			cap.height = 1.4
			mi_body.mesh = cap
			mi_body.rotation.x = deg_to_rad(90.0)
			mi_body.position.y = 0.9

			var mat_deer := StandardMaterial3D.new()
			mat_deer.albedo_color = Color(0.58, 0.38, 0.22) # Red deer tawny brown
			mi_body.material_override = mat_deer
			deer.add_child(mi_body)

			# Deer Head & Antlers
			var mi_head := MeshInstance3D.new()
			var box_head := BoxMesh.new()
			box_head.size = Vector3(0.25, 0.35, 0.45)
			mi_head.mesh = box_head
			mi_head.position = Vector3(0, 1.4, -0.7)
			mi_head.material_override = mat_deer
			deer.add_child(mi_head)

			# Collision
			var col := CollisionShape3D.new()
			var cap_col := CapsuleShape3D.new()
			cap_col.radius = 0.45
			cap_col.height = 1.4
			col.shape = cap_col
			col.position.y = 0.9
			deer.add_child(col)

			wildlife_container.add_child(deer)
			deer.global_position = Vector3(dx, dy, dz)

	# 2. Spawn Wolves (~6 wolves)
	for i in range(6):
		var wx := rng.randf_range(60.0, 240.0)
		var wz := rng.randf_range(100.0, 480.0)
		var wy := sample_height(wx, wz)

		if wy > 2.0 and wy < 90.0:
			var wolf := CharacterBody3D.new()
			wolf.name = "Wolf_%d" % i
			wolf.set_script(load("res://scripts/fauna/wolf_ai.gd"))

			# Wolf Torso
			var mi_body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.3
			cap.height = 1.2
			mi_body.mesh = cap
			mi_body.rotation.x = deg_to_rad(90.0)
			mi_body.position.y = 0.65

			var mat_wolf := StandardMaterial3D.new()
			mat_wolf.albedo_color = Color(0.32, 0.33, 0.35) # Scandinavian timber wolf grey
			mi_body.material_override = mat_wolf
			wolf.add_child(mi_body)

			# Wolf Head with yellow eyes
			var mi_head := MeshInstance3D.new()
			var box_head := BoxMesh.new()
			box_head.size = Vector3(0.24, 0.28, 0.4)
			mi_head.mesh = box_head
			mi_head.position = Vector3(0, 0.9, -0.6)
			mi_head.material_override = mat_wolf
			wolf.add_child(mi_head)

			# Collision
			var col := CollisionShape3D.new()
			var cap_col := CapsuleShape3D.new()
			cap_col.radius = 0.4
			cap_col.height = 1.2
			col.shape = cap_col
			col.position.y = 0.65
			wolf.add_child(col)

			wildlife_container.add_child(wolf)
			wolf.global_position = Vector3(wx, wy, wz)

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
	col_shape.shape = mesh.create_trimesh_shape()
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

	# Scatter ~150 harvestable trees along the lower hillsides and valley
	var count := 150
	for i in range(count):
		# Concentrate trees in the valley and mountain slopes: x in [20, 220], z in [-50, 450]
		var tx := rng.randf_range(30.0, 200.0)
		var tz := rng.randf_range(-60.0, 480.0)
		var ty := sample_height(tx, tz)

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

