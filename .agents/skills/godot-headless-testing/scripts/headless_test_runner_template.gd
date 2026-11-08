extends SceneTree

## Reusable Headless GDScript Test Runner Template for Godot 4
##
## Usage:
##   /shared/user/.gemini/godot_bin/godot --headless -s res://path/to/this_test.gd

var total_tests: int = 0
var passes: int = 0
var fails: int = 0

func _init() -> void:
	print("\n" + "=".repeat(60))
	print("STARTING HEADLESS GAMEPLAY TEST HARNESS")
	print("=".repeat(60))

	# Run individual test cases here
	run_test("Example Interaction Test", _example_interaction_test)
	run_test("Example Physics Properties Test", _example_physics_test)

	print("\n" + "=".repeat(60))
	print("TEST RUN COMPLETE: %d / %d PASSED" % [passes, total_tests])
	print("=".repeat(60))

	if fails > 0:
		print("❌ TEST SUITE FAILED (%d failures)" % fails)
		quit(1)
	else:
		print("✓ ALL TESTS PASSED SUCCESSFULLY!")
		quit(0)

func run_test(test_name: String, test_callable: Callable) -> void:
	total_tests += 1
	print("\n[TEST %d] %s..." % [total_tests, test_name])
	var success: bool = false
	if test_callable.is_valid():
		success = bool(test_callable.call())
	
	if success:
		passes += 1
		print("  ✓ PASS: %s" % test_name)
	else:
		fails += 1
		push_error("  ❌ FAIL: %s" % test_name)

func _example_interaction_test() -> bool:
	# Verify interactable node logic
	var dummy := Node3D.new()
	dummy.add_to_group("interactable")
	var is_in_grp: bool = dummy.is_in_group("interactable")
	dummy.free()
	return is_in_grp

func _example_physics_test() -> bool:
	# Verify physics material dampening
	var body := RigidBody3D.new()
	body.angular_damp = 18.0
	body.linear_damp = 5.0
	body.can_sleep = true
	var ok: bool = (body.angular_damp >= 10.0 and body.can_sleep)
	body.free()
	return ok
