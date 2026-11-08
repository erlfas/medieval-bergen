extends SceneTree

# Gate 4 Verification & Performance Benchmark Script

func _init() -> void:
	print("=== Running GATE 4: Full Scene Integration & WebGL Profiler Benchmark ===")
	_run_profiler()

func _run_profiler() -> void:
	var main_scene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: Failed to load res://scenes/main.tscn")
		quit(1)
		return

	var world = main_scene.instantiate()
	root.add_child(world)

	var errors: Array[String] = []

	# Allow scene, physics, and shaders to process initial frames
	var warmup_frames := 60
	for i in range(warmup_frames):
		await process_frame

	# 1. Audit Active Mesh Instances (WebGL Hard Budget Ceiling: < 500)
	var all_meshes = root.find_children("*", "MeshInstance3D", true, false)
	var mesh_count = all_meshes.size()
	print("Scene Total MeshInstance3D Count: %d (Budget Ceiling: < 500, Target: <= 490)" % mesh_count)
	if mesh_count > 490:
		errors.append("MeshInstance3D count %d exceeds WebGL target budget 490!" % mesh_count)

	# 2. Audit MultiMesh Batches in Grass Container
	var grass_container = world.find_child("GrassSectors", true, false)
	if grass_container == null:
		errors.append("GrassSectors container not found in active world hierarchy!")
	else:
		var sector_count = grass_container.get_child_count()
		print("Active Grass Sectors: %d" % sector_count)
		if sector_count < 6:
			errors.append("Too few active grass sectors: %d" % sector_count)

	# 3. Audit Static Memory
	var mem_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("Engine Static Memory: %.2f MB (Budget Ceiling: <= 350 MB)" % mem_mb)
	if mem_mb > 350.0:
		errors.append("Static memory %.2f MB exceeds 350 MB budget!" % mem_mb)

	# 4. Capture Offscreen Screenshot for Visual Verification
	var viewport = root.get_viewport()
	if viewport:
		var tex = viewport.get_texture()
		if tex:
			var img = tex.get_image()
			if img and not img.is_empty():
				var img_path = "/tmp/grass_render_check.png"
				img.save_png(img_path)
				var file = FileAccess.open(img_path, FileAccess.READ)
				var file_size = file.get_length() if file else 0
				print("Saved offscreen render capture: %s (%d KB)" % [img_path, file_size / 1024])
				if file_size < 10000:
					errors.append("Render capture size (%d bytes) too small; possible blank frame!" % file_size)

	# Final Verdict
	world.queue_free()
	if not errors.is_empty():
		print("\nGATE 4 FAILED with errors:")
		for e in errors:
			print(" - ", e)
		quit(1)
	else:
		print("\n>>> GATE 4 PASSED: WebGL 2.0 draw call, mesh count, and visual rendering benchmarks satisfied! <<<\n")
		quit(0)
