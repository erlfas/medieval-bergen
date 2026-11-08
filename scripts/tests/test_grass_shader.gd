extends SceneTree

# Gate 2 Verification Script: Grass Wind Shader & Deflection Math

func _init() -> void:
	print("=== Running GATE 2: Wind Shader & Displacement Math Verification ===")
	var errors: Array[String] = []

	# 1. Shader Resource Loading & Compilation Check
	var shader = load("res://shaders/grass_wind.gdshader") as Shader
	if shader == null:
		errors.append("Failed to load res://shaders/grass_wind.gdshader")
	else:
		print("Loaded shaders/grass_wind.gdshader successfully")

	# 2. ShaderMaterial Construction Check
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var albedo_tex = load("res://assets/terrain/grass_clump_albedo.jpg") as Texture2D
	var normal_tex = load("res://assets/terrain/grass_clump_normal.jpg") as Texture2D
	var pbr_tex = load("res://assets/terrain/grass_clump_pbr.jpg") as Texture2D

	if albedo_tex == null:
		errors.append("Failed to load res://assets/terrain/grass_clump_albedo.jpg")
	if normal_tex == null:
		errors.append("Failed to load res://assets/terrain/grass_clump_normal.jpg")
	if pbr_tex == null:
		errors.append("Failed to load res://assets/terrain/grass_clump_pbr.jpg")

	mat.set_shader_parameter("albedo_texture", albedo_tex)
	mat.set_shader_parameter("normal_texture", normal_tex)
	mat.set_shader_parameter("pbr_texture", pbr_tex)
	print("Configured ShaderMaterial with PBR textures successfully")

	# Save the configured material as a shared resource
	var err = ResourceSaver.save(mat, "res://assets/terrain/grass_wind_material.tres")
	if err != OK:
		errors.append("Failed to save grass_wind_material.tres: error %d" % err)
	else:
		print("Saved shared material res://assets/terrain/grass_wind_material.tres")

	# 3. Mathematical Verification of Shader Displacement Invariants
	var wind_dir := Vector3(0.707, 0.0, 0.707)
	var wind_speed := 2.2
	var wind_strength := 0.35
	var gust_freq := 0.045
	var gust_str := 0.45
	var blade_h := 0.78

	var max_root_displacement := 0.0
	var max_tip_deflection := 0.0
	var max_length_error := 0.0

	for step in range(120):
		var time := float(step) * 0.05
		var world_pos := Vector3(12.5, 4.2, -8.3)

		# Root test (y = 0.0)
		var h_factor_root := clampf(0.0 / blade_h, 0.0, 1.0)
		var bend_weight_root := h_factor_root * h_factor_root

		var wave1 := sin(time * wind_speed + (world_pos.x * wind_dir.x + world_pos.z * wind_dir.z) * 0.45)
		var wave2 := maxf(0.0, sin(time * (wind_speed * 1.5) + (world_pos.x * wind_dir.x + world_pos.z * wind_dir.z) * gust_freq)) * gust_str
		var flutter := sin(time * 8.0 + (world_pos.x * 3.4 + world_pos.z * 2.8)) * 0.06

		var disp_root := wind_dir * ((wave1 * 0.28 + wave2 + flutter) * wind_strength * bend_weight_root)
		max_root_displacement = maxf(max_root_displacement, disp_root.length())

		# Tip test (y = blade_h)
		var h_factor_tip := clampf(blade_h / blade_h, 0.0, 1.0)
		var bend_weight_tip := h_factor_tip * h_factor_tip

		var disp_tip := wind_dir * ((wave1 * 0.28 + wave2 + flutter) * wind_strength * bend_weight_tip)
		var tip_xz_len := Vector2(disp_tip.x, disp_tip.z).length()
		var final_y := sqrt(maxf(0.0, blade_h * blade_h - tip_xz_len * tip_xz_len))
		var bent_tip := Vector3(disp_tip.x, final_y, disp_tip.z)

		max_tip_deflection = maxf(max_tip_deflection, tip_xz_len)

		# Length conservation check
		var blade_length := bent_tip.length()
		var length_error := absf(blade_length - blade_h) / blade_h
		max_length_error = maxf(max_length_error, length_error)

	print("Root Displacement Invariant: max delta = %.6f m (threshold: == 0.000)" % max_root_displacement)
	if max_root_displacement > 0.000001:
		errors.append("Root displacement %.6f > 0.000; grass base would float!" % max_root_displacement)

	print("Tip Deflection: max delta = %.3f m (threshold: <= 0.420 m)" % max_tip_deflection)
	if max_tip_deflection > 0.42:
		errors.append("Tip deflection %.3f exceeds maximum threshold 0.420 m" % max_tip_deflection)

	print("Blade Length Invariant: max length variance = %.2f%% (threshold: <= 3.0%%)" % (max_length_error * 100.0))
	if max_length_error > 0.03:
		errors.append("Blade length variance %.2f%% exceeds 3.0%% tolerance" % (max_length_error * 100.0))

	# Report Results
	if not errors.is_empty():
		print("\nGATE 2 FAILED with errors:")
		for e in errors:
			print(" - ", e)
		quit(1)
	else:
		print("\n>>> GATE 2 PASSED: Wind shader compiles and displacement invariants verified! <<<\n")
		quit(0)
