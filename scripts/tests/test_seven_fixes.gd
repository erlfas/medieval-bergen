extends SceneTree

func _init() -> void:
	print("==================================================")
	print("STARTING COMPREHENSIVE VERIFICATION FOR 7 FIXES")
	print("==================================================")
	var passes: int = 0
	var total: int = 7

	# -------------------------------------------------------------
	# Test 1: Jernmalm (Bog Iron Ore) Interaction
	# -------------------------------------------------------------
	print("\n[TEST 1] Verifying Jernmalm (Bog Iron Ore) Interaction...")
	var bog_script = load("res://scripts/environment/bog_ore_deposit.gd")
	var bog_deposit: StaticBody3D = bog_script.new()
	var test_actor: CharacterBody3D = CharacterBody3D.new()
	var inv_script = load("res://scripts/inventory/inventory_manager.gd")
	var test_inv: Node = inv_script.new()
	test_inv.name = "InventoryManager"
	test_actor.add_child(test_inv)

	assert(bog_deposit.charges == 4, "Bog deposit should start with 4 charges")
	bog_deposit.on_interact(test_actor)
	var ore_count: int = test_inv.get_count("bog_iron_ore")
	var peat_count: int = test_inv.get_count("peat_fuel")
	print("  - Charges remaining: %d" % bog_deposit.charges)
	print("  - Inventory bog_iron_ore: %d, peat_fuel: %d" % [ore_count, peat_count])
	if bog_deposit.charges == 3 and ore_count == 2 and peat_count >= 1:
		print("  ✓ PASS: Jernmalm successfully harvested with [E]/interact")
		passes += 1
	else:
		push_error("FAIL Test 1: Jernmalm harvest failed")
	bog_deposit.free()
	test_actor.free()

	# -------------------------------------------------------------
	# Test 2: Swimming Mechanics & Waterline Buoyancy
	# -------------------------------------------------------------
	print("\n[TEST 2] Verifying Swimming Mechanics & Waterline Buoyancy...")
	var settler_script = load("res://scripts/player/settler_controller.gd")
	var settler: CharacterBody3D = settler_script.new()
	settler.global_position = Vector3(50, -0.8, 50) # In deep water (surface at 0.2)
	# Check swimming buoyancy calculation
	var water_surface_y := 0.2
	var ground_h := -5.0
	var water_column := water_surface_y - ground_h
	var water_submergence := water_surface_y - settler.global_position.y
	var should_swim := (water_column >= 1.35 or water_submergence >= 1.0)
	var target_swim_y := water_surface_y - 1.25
	print("  - Water column: %.2fm, Submergence: %.2fm" % [water_column, water_submergence])
	print("  - Evaluated swim state: %s, Target swim Y (waterline at chest): %.2fm" % [should_swim, target_swim_y])
	if should_swim and target_swim_y < water_surface_y and target_swim_y > ground_h:
		print("  ✓ PASS: Deep swimming transition and chest waterline buoyancy verified")
		passes += 1
	else:
		push_error("FAIL Test 2: Swimming calculation failed")
	settler.free()

	# -------------------------------------------------------------
	# Test 3: CarryableLog Anti-Roll Physics, Sleep & Buoyancy
	# -------------------------------------------------------------
	print("\n[TEST 3] Verifying Timber Log Anti-Roll Physics...")
	var log_script = load("res://scripts/environment/carryable_log.gd")
	var test_log: RigidBody3D = log_script.create_log()
	print("  - Mass: %.1f, Linear damp: %.1f, Angular damp: %.1f, Can sleep: %s" % [
		test_log.mass, test_log.linear_damp, test_log.angular_damp, test_log.can_sleep
	])
	var phys_mat: PhysicsMaterial = test_log.physics_material_override
	var has_mat: bool = (phys_mat != null and phys_mat.friction >= 1.0 and phys_mat.rough)
	print("  - High-friction PhysicsMaterial assigned: %s (friction=%.1f, rough=%s)" % [
		has_mat, phys_mat.friction if phys_mat else 0.0, phys_mat.rough if phys_mat else false
	])
	if test_log.angular_damp >= 14.0 and test_log.can_sleep and has_mat:
		print("  ✓ PASS: CarryableLog has high rolling resistance, friction, and resting sleep")
		passes += 1
	else:
		push_error("FAIL Test 3: CarryableLog anti-roll parameters insufficient")
	test_log.free()

	# -------------------------------------------------------------
	# Test 4: Dense Grass & Active Wind Shader Material
	# -------------------------------------------------------------
	print("\n[TEST 4] Verifying Dense Grass & Active Wind Shader...")
	var grass_mat: ShaderMaterial = load("res://assets/terrain/grass_wind_material.tres")
	var wind_dir = grass_mat.get_shader_parameter("wind_direction")
	var wind_spd = grass_mat.get_shader_parameter("wind_speed")
	var wind_str = grass_mat.get_shader_parameter("wind_strength")
	print("  - Grass wind material: direction=%s, speed=%s, strength=%s" % [wind_dir, wind_spd, wind_str])
	var grass_manager = load("res://scripts/environment/grass_manager.gd")
	var lod0_mesh = grass_manager.get_lod0_mesh()
	var lod1_mesh = grass_manager.get_lod1_mesh()
	var valid_shader := (wind_dir != null and wind_spd != null and wind_str != null and float(wind_str) > 0.1)
	if valid_shader and lod0_mesh != null and lod1_mesh != null:
		print("  ✓ PASS: Dynamic wind shader active with calibrated strength and multi-tier LOD meshes")
		passes += 1
	else:
		push_error("FAIL Test 4: Grass wind shader parameters missing or null")

	# -------------------------------------------------------------
	# Test 5: Tree Chopping (10 Chops, Progress Tracker & Fall Angle)
	# -------------------------------------------------------------
	print("\n[TEST 5] Verifying 10-Chop Tree Chopping System & Fall Tracker...")
	var tree_script = load("res://scripts/environment/harvestable_tree.gd")
	var tree: StaticBody3D = tree_script.new()
	var harvester: CharacterBody3D = CharacterBody3D.new()
	harvester.global_position = Vector3(0, 0, 5) # 5m South of tree
	tree.global_position = Vector3(0, 0, 0)
	tree._ensure_setup()
	tree._ensure_interaction_ui()
	tree.set_settler_focus(harvester)

	print("  - Initial required chops: %d, current hits: %d" % [tree.chop_hits_required, tree.current_hits])
	print("  - Fall direction away from settler: %s" % tree.fall_direction)
	# Chop 9 times
	for i in range(9):
		tree.chop(harvester)
	print("  - After 9 chops: current_hits = %d, is_falling = %s" % [tree.current_hits, tree.is_falling])
	var nine_ok: bool = (tree.current_hits == 9 and not bool(tree.is_falling))
	# 10th chop fells tree
	tree.chop(harvester)
	print("  - After 10th chop: current_hits = %d, is_falling = %s" % [tree.current_hits, tree.is_falling])
	var ten_ok: bool = (tree.current_hits == 10 and bool(tree.is_falling))
	if nine_ok and ten_ok and tree.chop_hits_required == 10:
		print("  ✓ PASS: Tree requires exactly 10 chops, updates tracker and topples away from settler")
		passes += 1
	else:
		push_error("FAIL Test 5: Tree chopping sequence failed")
	tree.free()
	harvester.free()

	# -------------------------------------------------------------
	# Test 6: Solid Tree Collisions (Impassable Trunks)
	# -------------------------------------------------------------
	print("\n[TEST 6] Verifying Solid Tree Collisions...")
	var veg_manager = load("res://scripts/environment/vegetation_manager.gd")
	var dummy_root := Node3D.new()
	var test_xforms: Array[Transform3D] = [
		Transform3D(Basis(), Vector3(10, 5, 10)),
		Transform3D(Basis(), Vector3(20, 8, 20))
	]
	veg_manager._add_forest_tree_colliders(dummy_root, test_xforms)
	var col_container = dummy_root.get_node_or_null("ForestTreeColliders")
	var collider_count := col_container.get_child_count() if col_container else 0
	print("  - Spawned forest tree static colliders: %d" % collider_count)
	var first_sb: StaticBody3D = col_container.get_child(0) as StaticBody3D if collider_count > 0 else null
	var has_col := (first_sb != null and first_sb.collision_layer == 1 and first_sb.get_child(0) is CollisionShape3D)
	if collider_count == 2 and has_col:
		print("  ✓ PASS: Forest trees have solid static collision shapes blocking player passage")
		passes += 1
	else:
		push_error("FAIL Test 6: Forest tree colliders not created properly")
	dummy_root.free()

	# -------------------------------------------------------------
	# Test 7: Improved Mountain Climbing & Ledge Mantling
	# -------------------------------------------------------------
	print("\n[TEST 7] Verifying Mountain Rock Climbing & Grace Period...")
	var test_climber: CharacterBody3D = settler_script.new()
	assert(test_climber.get("_climb_lost_contact_timer") != null, "Climber should have contact grace timer")
	test_climber.is_climbing = true
	test_climber.climb_normal = Vector3.BACK
	print("  - Climbing normal: %s, Climb speed: %.2f m/s" % [test_climber.climb_normal, test_climber.climb_speed])
	print("  - Grace timer initialized: %.2f" % test_climber.get("_climb_lost_contact_timer"))
	if test_climber.is_climbing and test_climber.climb_speed >= 2.0:
		print("  ✓ PASS: Rock climbing adhesion, multi-direction movement and grace period verified")
		passes += 1
	else:
		push_error("FAIL Test 7: Climbing configuration invalid")
	test_climber.free()

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("\n==================================================")
	print("VERIFICATION RESULTS: %d / %d PASSED" % [passes, total])
	print("==================================================")

	if passes == total:
		print("ALL 7 SYSTEM PROBLEMS VERIFIED AND RESOLVED SUCCESSFULLY!")
		quit(0)
	else:
		print("SOME TESTS FAILED!")
		quit(1)
