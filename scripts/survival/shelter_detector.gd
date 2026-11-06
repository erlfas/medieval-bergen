class_name ShelterDetector
extends Node3D

## Detects when the settler is inside a built shelter (under a sod roof and enclosed by walls)
## and whether the settler is near a lit stone hearth or campfire.
## Feeds is_sheltered and is_near_fire directly to SurvivalStats!

@export var survival_stats: SurvivalStats
@export var ray_distance_up: float = 6.0
@export var ray_distance_walls: float = 5.0
@export var hearth_warmth_radius: float = 5.5

var check_timer: float = 0.0

func _physics_process(delta: float) -> void:
	check_timer -= delta
	if check_timer <= 0.0:
		check_timer = 0.4 # Run check 2.5 times per second
		_evaluate_environment()

func _evaluate_environment() -> void:
	if not survival_stats:
		return

	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.5, 0)

	# 1. Check Roof Overhead (Raycast straight UP)
	var up_query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.UP * ray_distance_up)
	var up_result := space_state.intersect_ray(up_query)
	var has_roof := not up_result.is_empty()

	# 2. Check Wall Enclosure (Raycast horizontally in 4 cardinal directions)
	var wall_hits := 0
	var directions := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	for dir in directions:
		var wall_query := PhysicsRayQueryParameters3D.create(origin, origin + dir * ray_distance_walls)
		var wall_result := space_state.intersect_ray(wall_query)
		if not wall_result.is_empty():
			wall_hits += 1

	var is_fully_sheltered := has_roof and (wall_hits >= 2)
	survival_stats.is_sheltered = is_fully_sheltered

	# 3. Check Hearth / Fire Proximity
	var near_fire := false
	var hearths := get_tree().get_nodes_in_group("hearth")
	for h in hearths:
		if h is Node3D and global_position.distance_to(h.global_position) <= hearth_warmth_radius:
			near_fire = true
			break

	# Settler's lit torch also gives a warmth boost
	var settler: Node = get_parent()
	if settler and settler.get("is_holding_torch") == true:
		near_fire = true

	survival_stats.is_near_fire = near_fire
