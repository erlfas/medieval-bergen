extends SceneTree

func _init() -> void:
	print("==================================================")
	print("STARTING COMPREHENSIVE TREE CHOPPING & TRACKER TESTS")
	print("==================================================")
	var passes: int = 0
	var total: int = 5

	# -------------------------------------------------------------
	# Test 1: HarvestableTree Configuration & 3D Progress Tracker
	# -------------------------------------------------------------
	print("\n[TEST 1] Verifying HarvestableTree & Progress Tracker Next to Tree...")
	var tree_script = load("res://scripts/environment/harvestable_tree.gd")
	var tree: StaticBody3D = tree_script.new()
	var settler_script = load("res://scripts/player/settler_controller.gd")
	var settler: CharacterBody3D = settler_script.new()
	settler.global_position = Vector3(0, 0, 3)
	tree.global_position = Vector3(0, 0, 0)
	tree._ensure_setup()
	tree.set_settler_focus(settler)

	var tracker: Node3D = tree.get_node_or_null("ProgressTracker")
	var tracker_label: Label3D = tracker.get_node_or_null("ChopCounterLabel") if tracker else null
	var bar_bg: MeshInstance3D = tracker.get_node_or_null("ProgressBarBG") if tracker else null
	var bar_fill: MeshInstance3D = tracker.get_node_or_null("ProgressBarFill") if tracker else null

	var tracker_ok := (tracker != null and tracker_label != null and bar_bg != null and bar_fill != null)
	var tracker_pos_ok := tracker != null and (absf(tracker.position.x) > 0.5 or tracker.position.length() > 0.5)
	var label_billboard_ok := tracker_label != null and tracker_label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and tracker_label.no_depth_test == true

	var bg_mat: StandardMaterial3D = bar_bg.material_override if bar_bg else null
	var fill_mat: StandardMaterial3D = bar_fill.material_override if bar_fill else null
	var mats_ok := bg_mat != null and fill_mat != null and bg_mat.no_depth_test == true and fill_mat.no_depth_test == true and bg_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and fill_mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED

	print("  - Tracker node created: %s, position: %s" % [tracker != null, tracker.position if tracker else "null"])
	print("  - Tracker label billboard & no_depth_test: %s" % label_billboard_ok)
	print("  - Progress bar materials (billboard & no_depth_test): %s" % mats_ok)
	print("  - Required chops: %d" % tree.chop_hits_required)

	if tracker_ok and tracker_pos_ok and label_billboard_ok and mats_ok and tree.chop_hits_required == 10:
		print("  ✓ PASS: Progress tracker is configured next to tree with billboard and no-depth-test materials")
		passes += 1
	else:
		push_error("FAIL Test 1: Progress tracker configuration invalid")

	# -------------------------------------------------------------
	# Test 2: Exactly 10 Chops to Fell & Progress Bar Increments
	# -------------------------------------------------------------
	print("\n[TEST 2] Verifying 10 Chops Progression & Felling...")
	var progressive_ok := true
	for i in range(1, 10):
		tree.chop(settler)
		if tree.current_hits != i or tree.is_falling:
			progressive_ok = false
			print("  - Failed at chop %d: hits=%d, is_falling=%s" % [i, tree.current_hits, tree.is_falling])
			break
		if not tracker_label.text.contains(str(i) + " / 10"):
			progressive_ok = false
			print("  - Label missing progress count %d/10: %s" % [i, tracker_label.text])
			break

	# 10th chop must fell the tree
	tree.chop(settler)
	var fell_ok: bool = (tree.current_hits == 10 and bool(tree.is_falling))
	print("  - After 10 chops: current_hits=%d, is_falling=%s, tracker_visible=%s" % [tree.current_hits, tree.is_falling, tracker.visible if tracker else false])

	if progressive_ok and fell_ok and not tracker.visible:
		print("  ✓ PASS: Exactly 10 chops required to fell tree, progress updates on each hit")
		passes += 1
	else:
		push_error("FAIL Test 2: Tree 10-chop progression or felling failed")

	tree.free()
	settler.free()

	# -------------------------------------------------------------
	# Test 3: SettlerController Dual Input (E and Left Mouse Button)
	# -------------------------------------------------------------
	print("\n[TEST 3] Verifying Settler Dual Input (E and LMB)...")
	var test_settler: CharacterBody3D = settler_script.new()
	var test_tree: StaticBody3D = tree_script.new()
	test_tree.global_position = Vector3(0, 0, 0)
	test_settler.global_position = Vector3(0, 0, 2.0) # 2.0m South of tree
	test_tree._ensure_setup()

	# Test tree detection
	test_settler.set("_focused_tree", test_tree)
	var detected_tree = test_settler._get_target_or_focused_tree()
	var detect_ok: bool = (detected_tree == test_tree)
	print("  - Detected tree target in range: %s" % (detected_tree != null))

	# Test Left Mouse Button chopping helper
	test_settler._chop_tree(test_tree)
	print("  - After Settler _chop_tree: tree current_hits = %d" % test_tree.current_hits)
	var lmb_ok: bool = (test_tree.current_hits == 1)

	# Test direct chop with E
	test_tree.chop(test_settler)
	print("  - After direct chop: tree current_hits = %d" % test_tree.current_hits)
	var e_ok: bool = (test_tree.current_hits == 2)

	if detect_ok and lmb_ok and e_ok:
		print("  ✓ PASS: SettlerController reliably identifies tree and executes chop via E and LMB")
		passes += 1
	else:
		push_error("FAIL Test 3: SettlerController dual input chopping failed")

	test_tree.free()
	test_settler.free()

	# -------------------------------------------------------------
	# Test 4: Forest MultiMesh Colliders are Interactive & Choppable
	# -------------------------------------------------------------
	print("\n[TEST 4] Verifying Forest MultiMesh Tree Colliders are Interactive...")
	var veg_manager = load("res://scripts/environment/vegetation_manager.gd")
	var dummy_root := Node3D.new()
	var mm_inst := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = CylinderMesh.new()
	mm.instance_count = 2
	var xforms: Array[Transform3D] = [
		Transform3D(Basis(), Vector3(10, 5, 10)),
		Transform3D(Basis(), Vector3(20, 8, 20))
	]
	mm.set_instance_transform(0, xforms[0])
	mm.set_instance_transform(1, xforms[1])
	mm_inst.multimesh = mm
	dummy_root.add_child(mm_inst)
	veg_manager._add_forest_tree_colliders(dummy_root, xforms, mm_inst, 1)

	var col_container = dummy_root.get_node_or_null("ForestTreeColliders")
	var child_count := col_container.get_child_count() if col_container else 0
	var first_tree: StaticBody3D = col_container.get_child(0) as StaticBody3D if child_count > 0 else null
	var is_harvestable := (first_tree != null and first_tree.has_method("chop") and first_tree.is_in_group("harvestable_trees"))

	print("  - Forest tree collider count: %d" % child_count)
	print("  - Forest tree has chop() and is in harvestable_trees: %s" % is_harvestable)

	# Test chopping the forest tree collider
	var dummy_chopper := CharacterBody3D.new()
	dummy_chopper.global_position = Vector3(10, 0, 12)
	for c in range(10):
		first_tree.chop(dummy_chopper)

	var mm_link_ok: bool = (first_tree.multimesh_instance == mm_inst and first_tree.multimesh_index == 0)
	var felled_ok: bool = (first_tree.current_hits == 10 and bool(first_tree.is_falling))
	print("  - Forest tree linked to MultiMesh: %s, felled on 10th chop: %s" % [mm_link_ok, felled_ok])

	if child_count == 2 and is_harvestable and mm_link_ok and felled_ok:
		print("  ✓ PASS: Forest canopy tree colliders are fully interactive HarvestableTrees linked to MultiMesh")
		passes += 1
	else:
		push_error("FAIL Test 4: Forest tree collider interactivity failed")

	dummy_chopper.free()
	dummy_root.free()

	# -------------------------------------------------------------
	# Test 5: Focus Persistence while Settler is in Proximity
	# -------------------------------------------------------------
	print("\n[TEST 5] Verifying Focus Persistence in Proximity...")
	var prox_tree: StaticBody3D = tree_script.new()
	var prox_settler: CharacterBody3D = settler_script.new()
	prox_settler.global_position = Vector3(0, 0, 2.5)
	prox_tree.global_position = Vector3(0, 0, 0)
	prox_tree._ensure_setup()
	prox_tree.set_settler_focus(prox_settler)

	# Simulate 3 seconds passing while settler is still 2.5m away
	for step in range(30):
		prox_tree._process(0.1)

	var still_focused: bool = (prox_tree.focus_timer > 0.0 and prox_tree.focused_settler == prox_settler)
	print("  - Focus timer after 3 seconds in range: %.2f (maintained: %s)" % [prox_tree.focus_timer, still_focused])

	# Move settler far away (10m)
	prox_settler.global_position = Vector3(0, 0, 10.0)
	# Process 4 seconds
	for step in range(40):
		prox_tree._process(0.1)

	var timed_out: bool = (prox_tree.focus_timer <= 0.0 and prox_tree.focused_settler == null)
	print("  - Focus timer after settler leaves: %.2f (timed out: %s)" % [prox_tree.focus_timer, timed_out])

	if still_focused and timed_out:
		print("  ✓ PASS: Focus persists while settler remains in range and fades out when settler leaves")
		passes += 1
	else:
		push_error("FAIL Test 5: Focus persistence test failed")

	prox_tree.free()
	prox_settler.free()

	# -------------------------------------------------------------
	# Final Verification Summary
	# -------------------------------------------------------------
	print("\n==================================================")
	print("TEST RESULTS: %d / %d PASSED" % [passes, total])
	print("==================================================")
	if passes == total:
		print("ALL TREE CHOPPING AND TRACKER TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		print("SOME TESTS FAILED!")
		quit(1)
