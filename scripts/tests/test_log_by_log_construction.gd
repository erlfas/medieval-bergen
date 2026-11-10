extends SceneTree

func _init() -> void:
	print("==================================================")
	print("STARTING LOG-BY-LOG BUILDING & STEM BUCKING TESTS")
	print("==================================================")
	var passes: int = 0
	var total: int = 5

	# -------------------------------------------------------------
	# Test 1: FallenTreeStem Configuration & Visual Cut Guides
	# -------------------------------------------------------------
	print("\n[TEST 1] Verifying FallenTreeStem & Visual Cut Guidance...")
	var stem_script = load("res://scripts/environment/fallen_tree_stem.gd")
	var stem: StaticBody3D = stem_script.new()
	var test_root := Node3D.new()
	root.add_child(test_root)
	test_root.add_child(stem)
	stem._ensure_setup()

	var ring_0: MeshInstance3D = stem.cut_rings[0] if stem.cut_rings.size() > 0 else null
	var ring_1: MeshInstance3D = stem.cut_rings[1] if stem.cut_rings.size() > 1 else null
	var tracker_0: Node3D = stem.cut_trackers[0] if stem.cut_trackers.size() > 0 else null
	var label_0: Label3D = stem.cut_labels[0] if stem.cut_labels.size() > 0 else null

	var guides_ok := (ring_0 != null and ring_1 != null and tracker_0 != null and label_0 != null)
	var ring_pos_ok := (ring_0 != null and is_equal_approx(ring_0.position.z, 4.0) and ring_1 != null and is_equal_approx(ring_1.position.z, 8.0))
	var label_billboard_ok := (label_0 != null and label_0.billboard == BaseMaterial3D.BILLBOARD_ENABLED and label_0.no_depth_test == true)

	print("  - Cut guide rings created at Z=4m and Z=8m: %s" % ring_pos_ok)
	print("  - Cut tracker label billboard & no_depth_test: %s" % label_billboard_ok)
	print("  - Initial cut tracker text: %s" % (label_0.text if label_0 else "null"))

	if guides_ok and ring_pos_ok and label_billboard_ok:
		print("  ✓ PASS: FallenTreeStem properly visualizes cut guides at 4m building log intervals")
		passes += 1
	else:
		push_error("FAIL Test 1: FallenTreeStem cut guides invalid")

	# -------------------------------------------------------------
	# Test 2: Stem Bucking into Standard 4m Logs with Visual Guidance
	# -------------------------------------------------------------
	print("\n[TEST 2] Verifying Stem Bucking (3 Chops per Cut Line)...")
	var dummy_chopper := CharacterBody3D.new()
	dummy_chopper.position = Vector3(0.0, 0.0, 3.8) # Near cut zone 0
	test_root.add_child(dummy_chopper)

	# Strike 1 & 2
	stem.chop(dummy_chopper)
	stem.chop(dummy_chopper)
	var hits_2_ok: bool = (stem.cut_hits[0] == 2 and stem.cut_labels[0].text.contains("■ ■ □"))
	print("  - After 2 chops on cut 0: hits=%d, label contains [■ ■ □]: %s" % [stem.cut_hits[0], hits_2_ok])

	# Strike 3 should sever cut zone 0 and spawn a 4.0m CarryableLog
	stem.chop(dummy_chopper)
	var cut_0_done: bool = stem.cut_completed[0]
	var spawned_logs := test_root.find_children("CarryableLog_4m_*", "RigidBody3D", true, false)
	var log_0_spawned: bool = (spawned_logs.size() >= 1)
	var first_spawned_log: RigidBody3D = spawned_logs[0] if log_0_spawned else null
	var log_len_ok: bool = first_spawned_log != null and is_equal_approx(float(first_spawned_log.get("log_length")), 4.0)

	print("  - Cut 0 completed on 3rd chop: %s, 4m log spawned: %s, length: %s" % [cut_0_done, log_0_spawned, first_spawned_log.get("log_length") if first_spawned_log else "null"])

	# Sever cut zone 1
	dummy_chopper.position = Vector3(0.0, 0.0, 7.8) # Near cut zone 1
	stem.chop(dummy_chopper)
	stem.chop(dummy_chopper)
	stem.chop(dummy_chopper)

	var all_logs := test_root.find_children("CarryableLog_4m_*", "RigidBody3D", true, false)
	print("  - Total 4m logs yielded after full stem bucking: %d" % all_logs.size())

	if hits_2_ok and cut_0_done and log_0_spawned and log_len_ok and all_logs.size() == 3:
		print("  ✓ PASS: Stem cleanly bucks into 3 proper 4.0m building logs with progressive cut feedback")
		passes += 1
	else:
		push_error("FAIL Test 2: Stem bucking failed")

	test_root.free()

	# -------------------------------------------------------------
	# Test 3: Standard 4m CarryableLog Pickup & Hauling
	# -------------------------------------------------------------
	print("\n[TEST 3] Verifying 4m CarryableLog Pickup & Hauling State...")
	var test_root3 := Node3D.new()
	root.add_child(test_root3)
	var settler_script = load("res://scripts/player/settler_controller.gd")
	var test_settler: CharacterBody3D = settler_script.new()
	test_root3.add_child(test_settler)

	var log_script = load("res://scripts/environment/carryable_log.gd")
	var test_log: RigidBody3D = log_script.new()
	test_log.set("log_length", 4.0)
	test_root3.add_child(test_log)
	test_log._ensure_setup()

	var prompt_has_4m: bool = test_log.prompt_label != null and test_log.prompt_label.text.contains("4m")
	print("  - CarryableLog prompt specifies 4m building log: %s (%s)" % [prompt_has_4m, test_log.prompt_label.text if test_log.prompt_label else ""])

	test_settler.pick_up_log(test_log)
	var is_carrying_ok: bool = test_settler.is_carrying_log
	print("  - Settler is_carrying_log after pickup: %s" % is_carrying_ok)

	if prompt_has_4m and is_carrying_ok:
		print("  ✓ PASS: Settler reliably picks up 4m timber log and enters hauling state")
		passes += 1
	else:
		push_error("FAIL Test 3: 4m log pickup and hauling failed")

	test_root3.free()

	# -------------------------------------------------------------
	# Test 4: LaftehytteConstructionSite Visual Guidance System
	# -------------------------------------------------------------
	print("\n[TEST 4] Verifying LaftehytteConstructionSite & In-World Visual Guidance...")
	var test_root4 := Node3D.new()
	root.add_child(test_root4)
	var site_script = load("res://scripts/construction/laftehytte_construction_site.gd")
	var site: StaticBody3D = site_script.new()
	test_root4.add_child(site)
	site._ensure_setup()

	var total_steps: int = site.log_sequence.size()
	var target_ghost: MeshInstance3D = site.target_ghost_log
	var arrow: Node3D = site.beacon_arrow
	var beacon_lbl: Label3D = site.beacon_label

	var site_setup_ok := (total_steps == 28 and target_ghost != null and arrow != null and beacon_lbl != null)
	var ghost_no_depth: bool = site.target_ghost_log.material_override != null and site.target_ghost_log.material_override.no_depth_test == true
	var beacon_no_depth: bool = beacon_lbl != null and beacon_lbl.no_depth_test == true and beacon_lbl.billboard == BaseMaterial3D.BILLBOARD_ENABLED

	print("  - Construction site total logs sequence: %d" % total_steps)
	print("  - Step 0 target name: %s" % site.log_sequence[0]["name"])
	print("  - Ghost log unshaded & no_depth_test: %s" % ghost_no_depth)
	print("  - Beacon arrow label billboard & no_depth_test: %s" % beacon_no_depth)
	print("  - Beacon label text: %s" % (beacon_lbl.text if beacon_lbl else ""))

	if site_setup_ok and ghost_no_depth and beacon_no_depth and beacon_lbl.text.contains("Course 1"):
		print("  ✓ PASS: In-world visual guidance system cleanly directs player to active target slot")
		passes += 1
	else:
		push_error("FAIL Test 4: Construction site visual guidance invalid")

	test_root4.free()

	# -------------------------------------------------------------
	# Test 5: Sequential Log-by-Log Placement & Notch Snapping
	# -------------------------------------------------------------
	print("\n[TEST 5] Verifying Sequential Log-by-Log Placement...")
	var test_root5 := Node3D.new()
	var site5: StaticBody3D = site_script.new()
	test_root5.add_child(site5)
	site5._ensure_setup()

	var settler5: CharacterBody3D = settler_script.new()
	test_root5.add_child(settler5)
	settler5.position = site5.position + Vector3(0.0, 0.0, 2.0)
	settler5.is_carrying_log = true

	# Test placing first sill log via SettlerController
	var placed_first: bool = settler5._try_slot_carried_log_into_construction_site()
	var after_step_1: int = site5.current_step_index
	var is_still_carrying: bool = settler5.is_carrying_log

	print("  - First log placed into building: %s" % placed_first)
	print("  - Construction step advanced to: %d / %d" % [after_step_1, site5.log_sequence.size()])
	print("  - Settler carrying log consumed: %s" % (not is_still_carrying))
	print("  - Solid log child count: %d" % site5.placed_logs_container.get_child_count())

	# Now sequentially simulate placing remaining 27 logs
	var all_placed := true
	for i in range(1, site5.log_sequence.size()):
		settler5.is_carrying_log = true
		var placed: bool = site5.place_carried_log(settler5)
		if not placed:
			all_placed = false
			print("  - Failed placing log at step %d" % i)
			break

	var site_completed: bool = site5.is_completed
	var is_shelter: bool = site5.is_in_group("shelter")
	print("  - All 28 logs placed sequentially: %s" % all_placed)
	print("  - Laftehytte completed: %s, provides shelter: %s" % [site_completed, is_shelter])

	if placed_first and after_step_1 == 1 and not is_still_carrying and all_placed and site_completed and is_shelter:
		print("  ✓ PASS: House is built log-by-log, locking corner notches until shelter is completed")
		passes += 1
	else:
		push_error("FAIL Test 5: Sequential log-by-log placement failed")

	test_root5.free()

	# -------------------------------------------------------------
	# Verification Summary
	# -------------------------------------------------------------
	print("\n==================================================")
	print("LOG-BY-LOG CONSTRUCTION RESULTS: %d / %d PASSED" % [passes, total])
	print("==================================================")
	if passes == total:
		print("ALL LOG-BY-LOG BUILDING TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		print("SOME TESTS FAILED!")
		quit(1)
