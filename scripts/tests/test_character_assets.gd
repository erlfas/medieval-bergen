extends SceneTree

func _init() -> void:
	print("=== Running Character Assets Verification Test ===")
	
	var models := {
		"man_without_cloths": "res://assets/character/man_without_cloths.glb",
		"cloths": "res://assets/character/cloths.glb",
		"character_helmet": "res://assets/character/character_helmet.glb",
		"character_belt": "res://assets/character/character_belt.glb",
		"sword": "res://assets/weapons/sword.glb",
		"bow": "res://assets/weapons/bow.glb",
		"arrow": "res://assets/weapons/arrow.glb"
	}
	
	var all_ok := true
	for name in models:
		var path: String = models[name]
		var res = load(path)
		if res == null:
			printerr("FAIL: Could not load " + path)
			all_ok = false
			continue
			
		var inst = res.instantiate()
		if inst == null:
			printerr("FAIL: Could not instantiate " + path)
			all_ok = false
			continue
			
		# Count meshes recursively
		var mesh_count := 0
		var face_count := 0
		var stack := [inst]
		while stack.size() > 0:
			var curr = stack.pop_back()
			if curr is MeshInstance3D and curr.mesh:
				mesh_count += 1
				face_count += curr.mesh.get_faces().size() / 3
			for child in curr.get_children():
				stack.push_back(child)
				
		print("SUCCESS: %s loaded! (meshes: %d, triangles/faces: %d)" % [name, mesh_count, face_count])
		inst.free()
		
	if all_ok:
		print("✓ ALL 7 ASSETS LOADED AND INSTANTIATED SUCCESSFULLY IN GODOT 4.3!")
		quit(0)
	else:
		printerr("Asset verification failed.")
		quit(1)
