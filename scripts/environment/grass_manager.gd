class_name GrassManager
extends Node

## High-Performance Multi-Tier Grass System for Medieval Bergen 1360.
## Features:
## 1. Up-close LOD0 (0m-22m) using decimated 3D model with physically-based wind shader.
## 2. Mid-range LOD1 (20m-65m) using crossed-quad billboard clusters with synchronized wind.
## 3. Biotic height solver: short cropped grass in sheep grazing pastures (<= 0.35m),
##    medium lush valley grass (0.5m-0.75m), and tall wild grass in wilderness & foothills (1.0m-1.4m).
## 4. Chunked 42x42m spatial sectors with native GPU distance culling, adding zero per-frame GDScript loops.

static var _cached_lod0_mesh: Mesh = null
static var _cached_lod1_mesh: Mesh = null

static func get_lod0_mesh() -> Mesh:
	if _cached_lod0_mesh != null:
		return _cached_lod0_mesh

	var lod0_scene = load("res://assets/terrain/grass_clump_lod0.glb") as PackedScene
	if lod0_scene != null:
		var inst = lod0_scene.instantiate()
		var mi: MeshInstance3D = null
		if inst is MeshInstance3D:
			mi = inst as MeshInstance3D
		else:
			var children := inst.find_children("*", "MeshInstance3D", true, false)
			if not children.is_empty():
				mi = children[0] as MeshInstance3D
		if mi != null and mi.mesh != null:
			_cached_lod0_mesh = mi.mesh.duplicate()
			inst.free()
			return _cached_lod0_mesh
		inst.free()

	# Procedural fallback if asset not yet imported
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.08, 0.72, 0.03)
	for i in range(5):
		var yaw := float(i) * (TAU / 5.0)
		var basis := Basis.from_euler(Vector3(deg_to_rad(12.0), yaw, 0.0))
		st.append_from(blade, 0, Transform3D(basis, Vector3(0, 0.36, 0)))
	st.generate_tangents()
	_cached_lod0_mesh = st.commit()
	return _cached_lod0_mesh

static func get_lod1_mesh() -> Mesh:
	if _cached_lod1_mesh != null:
		return _cached_lod1_mesh

	var lod1_scene = load("res://assets/terrain/grass_clump_lod1.glb") as PackedScene
	if lod1_scene != null:
		var inst = lod1_scene.instantiate()
		var mi: MeshInstance3D = null
		if inst is MeshInstance3D:
			mi = inst as MeshInstance3D
		else:
			var children := inst.find_children("*", "MeshInstance3D", true, false)
			if not children.is_empty():
				mi = children[0] as MeshInstance3D
		if mi != null and mi.mesh != null:
			_cached_lod1_mesh = mi.mesh.duplicate()
			inst.free()
			return _cached_lod1_mesh
		inst.free()

	# Procedural crossed-quad fallback
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.78)
	for i in range(3):
		var yaw := float(i) * (PI / 3.0)
		var basis := Basis.from_euler(Vector3(0, yaw, 0))
		st.append_from(q, 0, Transform3D(basis, Vector3(0, 0.39, 0)))
	st.generate_tangents()
	_cached_lod1_mesh = st.commit()
	return _cached_lod1_mesh

## Evaluates grass profile at world position (x, z)
static func evaluate_grass_profile(
	x: float,
	z: float,
	terrain_gen: BergenTerrainGenerator,
	settlement_pads: Array[Dictionary],
	sheep_pastures: Array[Vector3],
	rng: RandomNumberGenerator
) -> Dictionary:
	var result := {
		"valid": false,
		"y": 0.0,
		"height": 0.65,
		"scale_xz": 0.65,
		"color": Color.WHITE,
		"yaw": 0.0
	}

	var y := terrain_gen.sample_height(x, z)
	result["y"] = y

	# Water & high crag culling
	if y < 1.0 or y > 105.0:
		return result

	# Check slope (trees & grass do not grow on sheer cliff faces > 30 deg)
	var h_r := terrain_gen.sample_height(x + 1.5, z)
	var h_u := terrain_gen.sample_height(x, z + 1.5)
	var grad := sqrt(pow((h_r - y) / 1.5, 2.0) + pow((h_u - y) / 1.5, 2.0))
	if grad > 0.65: # ~33 deg slope
		return result

	# Stream exclusion
	if terrain_gen.is_freshwater_stream(Vector3(x, y, z)):
		return result

	# Building footprint exclusion
	for pad in settlement_pads:
		var px: float = pad.get("x", 0.0)
		var pz: float = pad.get("z", 0.0)
		var pr: float = pad.get("inner_radius", 18.0)
		if Vector2(x - px, z - pz).length_squared() < (pr - 1.0) * (pr - 1.0):
			return result

	# Check sheep grazing pastures (within 20m of farm sheep pasture centers)
	var min_sheep_dist := 9999.0
	for sp in sheep_pastures:
		var d := Vector2(x - sp.x, z - sp.z).length()
		if d < min_sheep_dist:
			min_sheep_dist = d

	var h_scale: float
	var tint: Color

	if min_sheep_dist <= 20.0:
		# Sheep pasture: heavily cropped, short grazed lawn turf (0.16m - 0.32m)
		var graze_factor := min_sheep_dist / 20.0
		h_scale = lerpf(0.18, 0.35, graze_factor * graze_factor) * rng.randf_range(0.92, 1.10)
		tint = Color(0.95, 1.06, 0.92) # Vibrant fresh cropped green
	elif y > 25.0:
		# Far-away wilderness / mountain foothills: tall wild grass blowing vigorously (0.90m - 1.40m)
		var wild_t := clampf((y - 25.0) / 45.0, 0.0, 1.0)
		h_scale = lerpf(0.90, 1.36, wild_t) * rng.randf_range(0.95, 1.12)
		tint = Color(1.05, 1.02, 0.84) # Golden wild rye / fescue tint
	else:
		# Lowland valley meadows: medium lush grass (0.50m - 0.75m)
		h_scale = rng.randf_range(0.50, 0.75)
		tint = Color(0.88, 1.02, 0.86)

	result["valid"] = true
	result["height"] = h_scale
	result["scale_xz"] = h_scale * rng.randf_range(0.88, 1.14)
	result["color"] = tint
	result["yaw"] = rng.randf() * TAU
	return result

## Populates sectorized MultiMesh grass across the valleys
static func populate_grass(
	terrain_gen: BergenTerrainGenerator,
	settlement_pads: Array[Dictionary],
	world_seed: int
) -> void:
	# 1. Clean up old container if regenerating
	var old_container := terrain_gen.get_node_or_null("GrassSectors")
	if old_container:
		old_container.free()

	var grass_container := Node3D.new()
	grass_container.name = "GrassSectors"
	terrain_gen.add_child(grass_container)
	grass_container.owner = terrain_gen

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1337

	# Collect sheep pasture centers (18m offset from farm centers, matching SheepAI placement)
	var sheep_pastures: Array[Vector3] = []
	for pad in settlement_pads:
		if pad.get("is_farm", false):
			var fx: float = pad["x"]
			var fz: float = pad["z"]
			sheep_pastures.append(Vector3(fx + 18.0, 0.0, fz))

	var lod0_mesh := get_lod0_mesh()
	var lod1_mesh := get_lod1_mesh()

	var lod0_mat := load("res://assets/terrain/grass_wind_material.tres") as Material
	var lod1_mat := load("res://assets/terrain/grass_billboard_material.tres") as Material

	# 2. Sector Grid Setup (110m x 110m macro sectors keeps total MultiMeshInstance3D count < 32)
	var sector_size := 110.0
	var min_x := -170.0
	var max_x := 300.0
	var min_z := -360.0
	var max_z := 700.0

	var total_sectors_created := 0
	var total_clumps_placed := 0

	var sz := min_z
	while sz < max_z:
		var sx := min_x
		while sx < max_x:
			# Check sector center elevation
			var center_y := terrain_gen.sample_height(sx + sector_size * 0.5, sz + sector_size * 0.5)
			if center_y < 0.5 or center_y > 115.0:
				sx += sector_size
				continue

			var sector_xforms: Array[Transform3D] = []
			var sector_colors: Array[Color] = []

			# Candidate instances per macro sector (dense lush meadow coverage)
			var candidates := 1400
			for c in range(candidates):
				var px := sx + rng.randf_range(2.0, sector_size - 2.0)
				var pz := sz + rng.randf_range(2.0, sector_size - 2.0)

				var prof := evaluate_grass_profile(px, pz, terrain_gen, settlement_pads, sheep_pastures, rng)
				if not prof["valid"]:
					continue

				var py: float = prof["y"]
				var h_s: float = prof["height"]
				var w_s: float = prof["scale_xz"]
				var yaw: float = prof["yaw"]

				var basis := Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04), yaw, rng.randf_range(-0.04, 0.04)))
				basis = basis.scaled(Vector3(w_s, h_s, w_s))

				# Align base tightly to sampled ground
				sector_xforms.append(Transform3D(basis, Vector3(px, py - 0.02, pz)))
				sector_colors.append(prof["color"])

			if not sector_xforms.is_empty():
				_create_sector_multimeshes(
					grass_container,
					"Sector_%d" % total_sectors_created,
					lod0_mesh,
					lod1_mesh,
					lod0_mat,
					lod1_mat,
					sector_xforms,
					sector_colors
				)
				total_sectors_created += 1
				total_clumps_placed += sector_xforms.size()

			sx += sector_size
		sz += sector_size

	print("GrassManager: created %d spatial sectors with %d total grass clumps" % [total_sectors_created, total_clumps_placed])

static func _create_sector_multimeshes(
	parent: Node3D,
	sector_name: String,
	lod0_mesh: Mesh,
	lod1_mesh: Mesh,
	lod0_mat: Material,
	lod1_mat: Material,
	xforms: Array[Transform3D],
	colors: Array[Color]
) -> void:
	var sector_node := Node3D.new()
	sector_node.name = sector_name
	parent.add_child(sector_node)

	var count := xforms.size()

	# --- LOD 0: Up-Close 3D Clump (0m to 36m) ---
	var mmi0 := MultiMeshInstance3D.new()
	mmi0.name = "GrassLOD0"
	mmi0.material_override = lod0_mat
	mmi0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi0.visibility_range_end = 36.0
	mmi0.visibility_range_end_margin = 0.0
	mmi0.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	var mm0 := MultiMesh.new()
	mm0.transform_format = MultiMesh.TRANSFORM_3D
	mm0.use_colors = true
	mm0.mesh = lod0_mesh
	mm0.instance_count = count
	for i in range(count):
		mm0.set_instance_transform(i, xforms[i])
		mm0.set_instance_color(i, colors[i])
	mmi0.multimesh = mm0
	sector_node.add_child(mmi0)

	# --- LOD 1: Mid/Far Range Crossed-Quad Billboard (32m to 150m) ---
	var mmi1 := MultiMeshInstance3D.new()
	mmi1.name = "GrassLOD1"
	mmi1.material_override = lod1_mat
	mmi1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi1.visibility_range_begin = 32.0
	mmi1.visibility_range_begin_margin = 0.0
	mmi1.visibility_range_end = 150.0
	mmi1.visibility_range_end_margin = 0.0
	mmi1.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	var mm1 := MultiMesh.new()
	mm1.transform_format = MultiMesh.TRANSFORM_3D
	mm1.use_colors = true
	mm1.mesh = lod1_mesh
	mm1.instance_count = count
	for i in range(count):
		mm1.set_instance_transform(i, xforms[i])
		mm1.set_instance_color(i, colors[i])
	mmi1.multimesh = mm1
	sector_node.add_child(mmi1)
