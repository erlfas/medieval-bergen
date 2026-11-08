extends SceneTree

# Gate 3 Verification Script: Biotic Grazing & Grass Spatial Distribution

func _init() -> void:
	print("=== Running GATE 3: Biotic Grazing & Grass Distribution Verification ===")
	var errors: Array[String] = []

	var terrain_gen = BergenTerrainGenerator.new()
	terrain_gen.world_seed = 1360
	terrain_gen._init_noise()
	terrain_gen.generate_terrain()
	root.add_child(terrain_gen)

	var grass_container = terrain_gen.get_node_or_null("GrassSectors")
	if grass_container == null:
		errors.append("GrassSectors container node was not created under terrain generator!")
		_finish(errors, terrain_gen)
		return

	var sector_count = grass_container.get_child_count()
	print("Created %d grass sectors" % sector_count)
	if sector_count < 6:
		errors.append("Too few grass sectors created: %d (expected >= 6)" % sector_count)

	# Collect sheep pasture centers from farmsteads
	var sheep_pastures: Array[Vector3] = []
	for pad in terrain_gen._settlement_pads:
		if pad.get("is_farm", false):
			var fx: float = pad["x"]
			var fz: float = pad["z"]
			sheep_pastures.append(Vector3(fx + 18.0, 0.0, fz))
	print("Identified %d sheep pasture grazing zones" % sheep_pastures.size())

	var total_clumps := 0
	var sheep_pasture_clumps := 0
	var sheep_pasture_height_violations := 0
	var wilderness_clumps := 0
	var wilderness_height_violations := 0
	var building_overlap_violations := 0
	var ground_alignment_violations := 0

	for s_idx in range(sector_count):
		var sector = grass_container.get_child(s_idx)
		var mmi0 = sector.get_node_or_null("GrassLOD0") as MultiMeshInstance3D
		var mmi1 = sector.get_node_or_null("GrassLOD1") as MultiMeshInstance3D

		if mmi0 == null or mmi0.multimesh == null:
			errors.append("Sector %s missing GrassLOD0 MultiMeshInstance3D" % sector.name)
			continue
		if mmi1 == null or mmi1.multimesh == null:
			errors.append("Sector %s missing GrassLOD1 MultiMeshInstance3D" % sector.name)
			continue

		var mm = mmi0.multimesh
		var count = mm.instance_count
		total_clumps += count

		for i in range(count):
			var xform: Transform3D = mm.get_instance_transform(i)
			var pos := xform.origin
			var scale_y := xform.basis.y.length()

			# 1. Test Ground Alignment
			var ground_y := terrain_gen.sample_height(pos.x, pos.z)
			if absf(pos.y - ground_y) > 0.08:
				ground_alignment_violations += 1

			# 2. Test Building Exclusion
			for pad in terrain_gen._settlement_pads:
				var px: float = pad.get("x", 0.0)
				var pz: float = pad.get("z", 0.0)
				var pr: float = pad.get("inner_radius", 18.0) - 1.0
				if Vector2(pos.x - px, pos.z - pz).length_squared() < pr * pr:
					building_overlap_violations += 1

			# 3. Test Sheep Pasture Height
			var min_sheep_dist := 9999.0
			for sp in sheep_pastures:
				var d := Vector2(pos.x - sp.x, pos.z - sp.z).length()
				if d < min_sheep_dist:
					min_sheep_dist = d

			if min_sheep_dist <= 15.0:
				sheep_pasture_clumps += 1
				if scale_y > 0.38:
					sheep_pasture_height_violations += 1

			# 4. Test Wilderness Height
			if pos.y > 40.0:
				wilderness_clumps += 1
				if scale_y < 0.85:
					wilderness_height_violations += 1

	print("Total clumps evaluated across all sectors: %d" % total_clumps)
	print("Sheep pasture clumps sampled: %d (violations > 0.38m: %d)" % [sheep_pasture_clumps, sheep_pasture_height_violations])
	print("Wilderness clumps sampled: %d (violations < 0.85m: %d)" % [wilderness_clumps, wilderness_height_violations])
	print("Building footprint overlaps: %d" % building_overlap_violations)
	print("Ground alignment deviations > 0.08m: %d" % ground_alignment_violations)

	if sheep_pasture_clumps == 0:
		errors.append("No grass clumps sampled in sheep pasture zones!")
	elif sheep_pasture_height_violations > 0:
		errors.append("%d sheep pasture grass clumps exceeded height threshold!" % sheep_pasture_height_violations)

	if wilderness_clumps == 0:
		errors.append("No grass clumps sampled in wilderness altitude > 40m!")
	elif wilderness_height_violations > 0:
		errors.append("%d wilderness grass clumps fell below height threshold!" % wilderness_height_violations)

	if building_overlap_violations > 0:
		errors.append("%d grass clumps spawned inside building footprints!" % building_overlap_violations)

	if ground_alignment_violations > 0:
		errors.append("%d grass clumps failed ground elevation clamping!" % ground_alignment_violations)

	_finish(errors, terrain_gen)

func _finish(errors: Array[String], node: Node) -> void:
	node.queue_free()
	if not errors.is_empty():
		print("\nGATE 3 FAILED with errors:")
		for e in errors:
			print(" - ", e)
		quit(1)
	else:
		print("\n>>> GATE 3 PASSED: Biotic grazing heights and spatial distribution verified! <<<\n")
		quit(0)
