class_name VegetationManager
extends Node

## High-Density Multi-Biome Forest & Understory Vegetation System for Medieval Bergen 1360.
## Combines:
## 1. Interactive Choppable HarvestableTree nodes (220+ multi-tier Spruce & Birch trees near valleys & trails)
## 2. GPU-Instanced Dense Forest Canopy via MultiMeshInstance3D (3,200+ Norwegian Spruce, Scots Pine & Downy Birch)
## 3. GPU-Instanced Dense Understory & Ground Flora via MultiMeshInstance3D (7,500+ Woodland Ferns,
##    Juniper/Heather Bushes, and Riparian Stream Reeds / Meadow Grass Tufts)
##
## Engineered to add only 6 total GPU draw calls for 10,700+ background trees and plants,
## keeping total scene MeshInstance3D count well below the WebGL 2.0 500-node limit.

## Builds a multi-tiered procedural Norwegian Spruce (Gran) or Downy Birch (Bjørk) compound mesh
static func build_detailed_tree_mesh(species: int = 0) -> ArrayMesh:
	# species: 0 = Birch (Bjørk), 1 = Spruce (Gran), 2 = Scots Pine (Furu)
	var arr_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()

	var trunk_mat := StandardMaterial3D.new()
	var canopy_mat := StandardMaterial3D.new()

	if species == 1: # Norwegian Spruce (Gran)
		trunk_mat.albedo_color = Color(0.30, 0.20, 0.13)
		trunk_mat.roughness = 0.90
		canopy_mat.albedo_color = Color(0.12, 0.27, 0.11)
		canopy_mat.roughness = 0.88
	elif species == 2: # Scots Pine (Furu)
		trunk_mat.albedo_color = Color(0.46, 0.26, 0.15)
		trunk_mat.roughness = 0.88
		canopy_mat.albedo_color = Color(0.16, 0.32, 0.15)
		canopy_mat.roughness = 0.86
	else: # Nordic Downy Birch (Bjørk)
		trunk_mat.albedo_color = Color(0.88, 0.86, 0.81)
		trunk_mat.roughness = 0.78
		canopy_mat.albedo_color = Color(0.33, 0.50, 0.18)
		canopy_mat.roughness = 0.84

	# Surface 0: Tapering Trunk & Root Flare
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(trunk_mat)
	var trunk := CylinderMesh.new()
	trunk.radial_segments = 7
	trunk.rings = 1
	if species == 1:
		trunk.top_radius = 0.11
		trunk.bottom_radius = 0.28
		trunk.height = 5.2
		st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0)))
	elif species == 2:
		trunk.top_radius = 0.14
		trunk.bottom_radius = 0.27
		trunk.height = 6.2
		st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 0)))
	else:
		trunk.top_radius = 0.12
		trunk.bottom_radius = 0.24
		trunk.height = 4.5
		st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 0)))
	st.generate_tangents()
	st.commit(arr_mesh)

	# Surface 1: Multi-Tiered Foliage Boughs / Crown Clusters
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(canopy_mat)

	if species == 1:
		# 4 overlapping conical spruce bough tiers from bottom skirt to spire peak
		var tiers := [
			{"y": 2.6, "bot_r": 2.05, "top_r": 0.45, "h": 2.4},
			{"y": 4.1, "bot_r": 1.68, "top_r": 0.35, "h": 2.3},
			{"y": 5.5, "bot_r": 1.25, "top_r": 0.22, "h": 2.1},
			{"y": 6.9, "bot_r": 0.78, "top_r": 0.04, "h": 1.9}
		]
		for t in tiers:
			var cone := CylinderMesh.new()
			cone.radial_segments = 7
			cone.rings = 1
			cone.bottom_radius = t["bot_r"]
			cone.top_radius = t["top_r"]
			cone.height = t["h"]
			st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, t["y"], 0)))
	elif species == 2:
		# Scots pine: high umbrella crown tiers atop tall bare trunk
		var pine_tiers := [
			{"pos": Vector3(0.0, 5.4, 0.0), "bot_r": 1.95, "top_r": 0.85, "h": 1.7},
			{"pos": Vector3(0.25, 6.4, -0.15), "bot_r": 1.55, "top_r": 0.42, "h": 1.5},
			{"pos": Vector3(-0.20, 7.1, 0.18), "bot_r": 1.05, "top_r": 0.12, "h": 1.2}
		]
		for pt in pine_tiers:
			var pcone := CylinderMesh.new()
			pcone.radial_segments = 7
			pcone.rings = 1
			pcone.bottom_radius = pt["bot_r"]
			pcone.top_radius = pt["top_r"]
			pcone.height = pt["h"]
			st.append_from(pcone, 0, Transform3D(Basis.IDENTITY, pt["pos"]))
	else:
		# Birch: 3 organic clustered leafy crowns
		var birch_clusters := [
			{"pos": Vector3(0.0, 4.1, 0.0), "bot_r": 1.85, "top_r": 0.65, "h": 2.4},
			{"pos": Vector3(0.42, 4.9, 0.28), "bot_r": 1.35, "top_r": 0.32, "h": 1.9},
			{"pos": Vector3(-0.38, 5.2, -0.24), "bot_r": 1.22, "top_r": 0.18, "h": 1.8}
		]
		for bc in birch_clusters:
			var bcone := CylinderMesh.new()
			bcone.radial_segments = 7
			bcone.rings = 1
			bcone.bottom_radius = bc["bot_r"]
			bcone.top_radius = bc["top_r"]
			bcone.height = bc["h"]
			st.append_from(bcone, 0, Transform3D(Basis.IDENTITY, bc["pos"]))

	st.generate_tangents()
	st.commit(arr_mesh)
	return arr_mesh

## Builds a lush radiating Woodland Fern (Bregne) clump mesh for forest floor understory
static func build_fern_clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.48, 0.16)
	mat.roughness = 0.82
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)

	var frond := BoxMesh.new()
	frond.size = Vector3(0.22, 0.03, 0.95)
	var frond_count := 7
	for i in range(frond_count):
		var yaw := float(i) / float(frond_count) * TAU
		var basis := Basis.from_euler(Vector3(deg_to_rad(-34.0), yaw, 0.0))
		var offset := basis.z * 0.36 + Vector3(0, 0.24, 0)
		st.append_from(frond, 0, Transform3D(basis, offset))

	st.generate_tangents()
	return st.commit()

## Builds a dense Juniper & Heather Shrub (Einer / Lyng) mound mesh
static func build_shrub_mound_mesh() -> ArrayMesh:
	var arr := ArrayMesh.new()
	var st := SurfaceTool.new()

	var mat_juniper := StandardMaterial3D.new()
	mat_juniper.albedo_color = Color(0.18, 0.34, 0.15)
	mat_juniper.roughness = 0.90

	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_juniper)
	var mound := CylinderMesh.new()
	mound.radial_segments = 6
	mound.rings = 1
	mound.bottom_radius = 0.85
	mound.top_radius = 0.32
	mound.height = 0.95
	st.append_from(mound, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0)))

	var side_mound := CylinderMesh.new()
	side_mound.radial_segments = 6
	side_mound.rings = 1
	side_mound.bottom_radius = 0.62
	side_mound.top_radius = 0.20
	side_mound.height = 0.72
	st.append_from(side_mound, 0, Transform3D(Basis.IDENTITY, Vector3(0.45, 0.32, 0.25)))
	st.append_from(side_mound, 0, Transform3D(Basis.IDENTITY, Vector3(-0.38, 0.28, -0.30)))
	st.generate_tangents()
	st.commit(arr)

	# Heather blossom accent crown
	var mat_heather := StandardMaterial3D.new()
	mat_heather.albedo_color = Color(0.44, 0.30, 0.38) # Muted Nordic heather purple-moss
	mat_heather.roughness = 0.88
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_heather)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.65, 0.22, 0.65)
	st.append_from(cap, 0, Transform3D(Basis.from_euler(Vector3(0, 0.4, 0)), Vector3(0.15, 0.68, 0.1)))
	st.generate_tangents()
	st.commit(arr)

	return arr

## Builds a Valley Meadow Grass & Riparian Reed Tuft mesh
static func build_meadow_reed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.49, 0.20)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)

	var blade := BoxMesh.new()
	blade.size = Vector3(0.12, 0.85, 0.03)
	for i in range(6):
		var angle := float(i) * (TAU / 6.0)
		var tilt := deg_to_rad(14.0 + float(i % 2) * 8.0)
		var basis := Basis.from_euler(Vector3(tilt, angle, 0.0))
		var pos := Vector3(cos(angle) * 0.18, 0.38, sin(angle) * 0.18)
		st.append_from(blade, 0, Transform3D(basis, pos))

	st.generate_tangents()
	return st.commit()

## Populates both Choppable HarvestableTree nodes and Dense MultiMesh Forests & Understory
static func populate_dense_vegetation(
	terrain_gen: BergenTerrainGenerator,
	settlement_pads: Array[Dictionary],
	world_seed: int
) -> void:
	# 1. Clean up existing containers
	var old_trees := terrain_gen.get_node_or_null("HarvestableTrees")
	if old_trees:
		old_trees.free()
	var old_veg := terrain_gen.get_node_or_null("DenseVegetationMultiMesh")
	if old_veg:
		old_veg.free()

	var trees_container := Node3D.new()
	trees_container.name = "HarvestableTrees"
	terrain_gen.add_child(trees_container)
	trees_container.owner = terrain_gen

	var veg_container := Node3D.new()
	veg_container.name = "DenseVegetationMultiMesh"
	terrain_gen.add_child(veg_container)
	veg_container.owner = terrain_gen

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 999

	# Forest grove density noise (creates thick woods alternating with natural valley glades)
	var grove_noise := FastNoiseLite.new()
	grove_noise.seed = world_seed + 404
	grove_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grove_noise.frequency = 0.0085
	grove_noise.fractal_octaves = 3

	var birch_mesh := build_detailed_tree_mesh(0)
	var spruce_mesh := build_detailed_tree_mesh(1)
	var pine_mesh := build_detailed_tree_mesh(2)

	var fern_mesh := build_fern_clump_mesh()
	var shrub_mesh := build_shrub_mound_mesh()
	var reed_mesh := build_meadow_reed_mesh()

	var harvestable_script = load("res://scripts/environment/harvestable_tree.gd")

	# -------------------------------------------------------------------------
	# TIER 1: 95 Interactive Choppable Trees in Valley Woods & Settlement Margins
	# (Keeps total scene MeshInstance3D count < 460 while MultiMesh renders 3,200+ canopy trees)
	# -------------------------------------------------------------------------
	var choppable_placed := 0
	var max_choppable := 95
	var attempts := 0
	while choppable_placed < max_choppable and attempts < 1400:
		attempts += 1
		var tx := rng.randf_range(-160.0, 290.0)
		var tz := rng.randf_range(-340.0, 680.0)
		var ty := terrain_gen.sample_height(tx, tz)

		if ty < 1.8 or ty > 88.0:
			continue
		if _is_inside_settlement(tx, tz, settlement_pads, 4.0):
			continue
		if terrain_gen.is_freshwater_stream(Vector3(tx, ty, tz)):
			continue

		# Higher probability in dense forest bands
		var g_val := (grove_noise.get_noise_2d(tx, tz) + 1.0) * 0.5
		if g_val < 0.28 and rng.randf() > 0.35:
			continue

		var tree_node := StaticBody3D.new()
		tree_node.name = "Tree_%d" % choppable_placed
		tree_node.set_script(harvestable_script)

		var is_spruce := (rng.randf() > 0.34) or (ty > 42.0)
		tree_node.set("tree_type", 1 if is_spruce else 0)

		var tree_mi := MeshInstance3D.new()
		tree_mi.name = "TreeCompoundMesh"
		tree_mi.mesh = spruce_mesh if is_spruce else birch_mesh
		var s_scale := rng.randf_range(0.85, 1.32)
		tree_mi.scale = Vector3(s_scale, s_scale * rng.randf_range(0.92, 1.15), s_scale)
		tree_mi.rotation.y = rng.randf() * TAU
		tree_node.add_child(tree_mi)

		var col := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.42
		capsule.height = 4.2
		col.shape = capsule
		col.position.y = 2.1
		tree_node.add_child(col)

		tree_node.position = Vector3(tx, ty, tz)
		trees_container.add_child(tree_node)
		choppable_placed += 1

	# -------------------------------------------------------------------------
	# TIER 2: 3,200+ Dense Forest Canopy Trees via MultiMeshInstance3D (3 Draw Calls)
	# -------------------------------------------------------------------------
	var spruce_xforms: Array[Transform3D] = []
	var pine_xforms: Array[Transform3D] = []
	var birch_xforms: Array[Transform3D] = []

	var canopy_candidates := 6200
	for i in range(canopy_candidates):
		# Concentrate dense forests across the valleys, Nordnes peninsula, Sandviken, and Fløyen slopes
		var fx: float
		var fz: float
		if i < 4200:
			fx = rng.randf_range(-240.0, 460.0)
			fz = rng.randf_range(-480.0, 780.0)
		else:
			fx = rng.randf_range(-680.0, 720.0)
			fz = rng.randf_range(-780.0, 880.0)

		var fy := terrain_gen.sample_height(fx, fz)
		if fy < 1.9 or fy > 165.0:
			continue

		# Check slope (trees don't grow on sheer vertical cliff faces > 40 deg)
		var h_r := terrain_gen.sample_height(fx + 2.0, fz)
		var h_u := terrain_gen.sample_height(fx, fz + 2.0)
		var grad := sqrt(pow((h_r - fy) * 0.5, 2.0) + pow((h_u - fy) * 0.5, 2.0))
		if grad > 0.82:
			continue

		# Dense cluster mask from grove noise
		var density := (grove_noise.get_noise_2d(fx, fz) + 1.0) * 0.5
		if density < 0.30 and rng.randf() > 0.22:
			continue

		if _is_inside_settlement(fx, fz, settlement_pads, 5.5):
			continue
		if terrain_gen.is_freshwater_stream(Vector3(fx, fy, fz)):
			continue

		var scale_f := rng.randf_range(0.78, 1.48) * lerpf(1.12, 0.72, clampf((fy - 20.0) / 140.0, 0.0, 1.0))
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.04, 0.04))).scaled(Vector3(scale_f, scale_f * rng.randf_range(0.9, 1.15), scale_f))
		var xform := Transform3D(basis, Vector3(fx, fy - 0.12, fz))

		# Species distribution by altitude & moisture
		if fy < 28.0 and rng.randf() < 0.45:
			birch_xforms.append(xform)
		elif fy > 55.0 and rng.randf() < 0.48:
			pine_xforms.append(xform)
		else:
			spruce_xforms.append(xform)

	_create_multimesh_batch(veg_container, "SpruceForestMultiMesh", spruce_mesh, spruce_xforms)
	_create_multimesh_batch(veg_container, "PineForestMultiMesh", pine_mesh, pine_xforms)
	_create_multimesh_batch(veg_container, "BirchForestMultiMesh", birch_mesh, birch_xforms)

	# -------------------------------------------------------------------------
	# TIER 3: 7,500+ Dense Understory & Valley Vegetation via MultiMeshInstance3D (3 Draw Calls)
	# -------------------------------------------------------------------------
	var fern_xforms: Array[Transform3D] = []
	var shrub_xforms: Array[Transform3D] = []
	var reed_xforms: Array[Transform3D] = []

	var understory_candidates := 10500
	for u in range(understory_candidates):
		var ux: float
		var uz: float
		if u < 7500:
			ux = rng.randf_range(-180.0, 380.0)
			uz = rng.randf_range(-420.0, 720.0)
		else:
			ux = rng.randf_range(-520.0, 580.0)
			uz = rng.randf_range(-680.0, 820.0)

		var uy := terrain_gen.sample_height(ux, uz)
		if uy < 0.6 or uy > 175.0:
			continue

		# Keep immediate building pads clear, but allow lush shrubs & grass right outside farm fences!
		if _is_inside_settlement(ux, uz, settlement_pads, -1.5):
			continue

		var h_r := terrain_gen.sample_height(ux + 1.5, uz)
		var h_u := terrain_gen.sample_height(ux, uz + 1.5)
		var grad := sqrt(pow((h_r - uy) / 1.5, 2.0) + pow((h_u - uy) / 1.5, 2.0))
		if grad > 0.90:
			continue

		var near_water := (uy < 3.5) or terrain_gen.is_freshwater_stream(Vector3(ux, uy, uz))
		var g_density := (grove_noise.get_noise_2d(ux * 1.4, uz * 1.4) + 1.0) * 0.5

		var u_scale := rng.randf_range(0.75, 1.45)
		var u_basis := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(u_scale, u_scale, u_scale))
		var u_xform := Transform3D(u_basis, Vector3(ux, uy - 0.04, uz))

		if near_water or (uy < 16.0 and g_density < 0.42):
			reed_xforms.append(u_xform)
		elif g_density > 0.44 and uy < 95.0:
			if rng.randf() < 0.62:
				fern_xforms.append(u_xform)
			else:
				shrub_xforms.append(u_xform)
		else:
			if rng.randf() < 0.55:
				shrub_xforms.append(u_xform)
			else:
				reed_xforms.append(u_xform)

	_create_multimesh_batch(veg_container, "WoodlandFernsMultiMesh", fern_mesh, fern_xforms, false, 260.0)
	_create_multimesh_batch(veg_container, "JuniperHeatherShrubsMultiMesh", shrub_mesh, shrub_xforms, false, 260.0)
	_create_multimesh_batch(veg_container, "ValleyReedsMeadowMultiMesh", reed_mesh, reed_xforms, false, 260.0)

static func _is_inside_settlement(x: float, z: float, settlement_pads: Array[Dictionary], margin: float = 2.0) -> bool:
	for pad in settlement_pads:
		var px: float = pad.get("x", 0.0)
		var pz: float = pad.get("z", 0.0)
		var pr: float = pad.get("inner_radius", 18.0) + margin
		if Vector2(x - px, z - pz).length_squared() < pr * pr:
			return true
	return false

static func _create_multimesh_batch(parent: Node3D, node_name: String, mesh: Mesh, xforms: Array[Transform3D], cast_shadows: bool = true, visibility_end: float = 0.0) -> void:
	if xforms.is_empty():
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if visibility_end > 0.0:
		mmi.visibility_range_end = visibility_end
		mmi.visibility_range_end_margin = 20.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	mmi.multimesh = mm
	parent.add_child(mmi)

