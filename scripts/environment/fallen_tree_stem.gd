class_name FallenTreeStem
extends StaticBody3D

## Physical fallen tree trunk with marked visual cut guides for bucking into 4.0m building logs.
## Spawned when a HarvestableTree topples and strikes the ground.
## The player chops each marked cut line (3 chops with E or LMB) to cleave standard-sized CarryableLogs.

enum TreeType { SPRUCE, BIRCH }

@export var tree_type: TreeType = TreeType.SPRUCE
@export var total_length: float = 12.0
@export var log_section_length: float = 4.0
@export var trunk_radius: float = 0.25

var stem_direction: Vector3 = Vector3.FORWARD
var sections_remaining: int = 3 # 3 x 4.0m logs

# Cut zones at Z = 4.0m and Z = 8.0m along local forward axis
var cut_hits: Array[int] = [0, 0] # Chops on cut 0 and cut 1
var cut_completed: Array[bool] = [false, false]
var cut_trackers: Array[Node3D] = []
var cut_labels: Array[Label3D] = []
var cut_rings: Array[MeshInstance3D] = []

var model_pivot: Node3D
var trunk_mesh_inst: MeshInstance3D

static var _shared_bark_spruce: StandardMaterial3D = null
static var _shared_bark_birch: StandardMaterial3D = null
static var _shared_cut_mat: StandardMaterial3D = null

func _ready() -> void:
	_ensure_setup()

func _ensure_setup() -> void:
	if model_pivot != null:
		return
	add_to_group("fallen_stem")
	add_to_group("interactable")
	add_to_group("harvestable_trees")
	_setup_materials()
	_setup_visuals_and_colliders()
	_setup_cut_guides()
	set_process(true)

func _setup_materials() -> void:
	if _shared_bark_spruce == null:
		_shared_bark_spruce = StandardMaterial3D.new()
		_shared_bark_spruce.albedo_color = Color(0.38, 0.26, 0.16)
		_shared_bark_spruce.roughness = 0.88

		_shared_bark_birch = StandardMaterial3D.new()
		_shared_bark_birch.albedo_color = Color(0.86, 0.84, 0.80)
		_shared_bark_birch.roughness = 0.75

		_shared_cut_mat = StandardMaterial3D.new()
		_shared_cut_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_cut_mat.albedo_color = Color(1.0, 0.82, 0.20, 0.95) # Radiant cut guide yellow
		_shared_cut_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_cut_mat.no_depth_test = true
		_shared_cut_mat.render_priority = 12

func _setup_visuals_and_colliders() -> void:
	model_pivot = Node3D.new()
	model_pivot.name = "ModelPivot"
	add_child(model_pivot)

	# Main horizontal trunk visual mesh
	trunk_mesh_inst = MeshInstance3D.new()
	trunk_mesh_inst.name = "TrunkMesh"
	var cyl := CylinderMesh.new()
	cyl.top_radius = trunk_radius * 0.85
	cyl.bottom_radius = trunk_radius
	cyl.height = total_length
	cyl.radial_segments = 14
	trunk_mesh_inst.mesh = cyl
	trunk_mesh_inst.material_override = _shared_bark_spruce if tree_type == TreeType.SPRUCE else _shared_bark_birch

	# Rotate cylinder so it lies along local Z axis
	trunk_mesh_inst.rotation.x = deg_to_rad(90.0)
	trunk_mesh_inst.position = Vector3(0.0, trunk_radius, total_length * 0.5)
	model_pivot.add_child(trunk_mesh_inst)

	# Collision capsule along local Z axis
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = trunk_radius
	cap.height = total_length
	col.shape = cap
	col.rotation.x = deg_to_rad(90.0)
	col.position = Vector3(0.0, trunk_radius, total_length * 0.5)
	add_child(col)

func _setup_cut_guides() -> void:
	# 2 cut zones: at 4.0m and 8.0m from the trunk base
	var cut_offsets: Array[float] = [4.0, 8.0]
	for i in range(cut_offsets.size()):
		var z_pos: float = cut_offsets[i]

		# 1. Glowing cut ring around trunk
		var ring := MeshInstance3D.new()
		ring.name = "CutRing_%d" % i
		var torus := TorusMesh.new()
		torus.inner_radius = trunk_radius * 0.98
		torus.outer_radius = trunk_radius * 1.14
		torus.rings = 16
		torus.ring_segments = 12
		ring.mesh = torus
		ring.material_override = _shared_cut_mat
		ring.rotation.x = deg_to_rad(90.0)
		ring.position = Vector3(0.0, trunk_radius, z_pos)
		model_pivot.add_child(ring)
		cut_rings.append(ring)

		# 2. 3D Billboard Tracker floating above cut ring
		var tracker := Node3D.new()
		tracker.name = "CutTracker_%d" % i
		tracker.position = Vector3(0.0, trunk_radius + 0.65, z_pos)
		model_pivot.add_child(tracker)
		cut_trackers.append(tracker)

		var lbl := Label3D.new()
		lbl.name = "CutLabel"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.render_priority = 16
		lbl.font_size = 24
		lbl.outline_size = 6
		lbl.modulate = Color(1.0, 0.92, 0.35)
		lbl.outline_modulate = Color(0.05, 0.04, 0.03, 0.95)
		lbl.position = Vector3.ZERO
		tracker.add_child(lbl)
		cut_labels.append(lbl)

		_update_cut_tracker_display(i)

func _update_cut_tracker_display(cut_idx: int) -> void:
	if cut_idx < 0 or cut_idx >= cut_labels.size():
		return
	var lbl := cut_labels[cut_idx]
	if not lbl:
		return

	if cut_completed[cut_idx]:
		lbl.visible = false
		if cut_idx < cut_rings.size() and cut_rings[cut_idx]:
			cut_rings[cut_idx].visible = false
		return

	var hits: int = cut_hits[cut_idx]
	var meter := ""
	for m in range(3):
		if m < hits:
			meter += "■ "
		else:
			meter += "□ "
	meter = meter.strip_edges()

	var sec_num := cut_idx + 1
	lbl.text = "🪵 Kappe Tømmerstokk (Cut Log %d)\nChop %d / 3  [ %s ]\n[E / LMB to Cut]" % [sec_num, hits, meter]

func _process(_delta: float) -> void:
	# Update visibility of cut trackers based on player proximity
	var player := _find_player()
	if not player:
		return

	var p_pos := player.global_position
	for i in range(cut_trackers.size()):
		if cut_completed[i]:
			continue
		var tracker := cut_trackers[i]
		if not tracker:
			continue
		var dist := tracker.global_position.distance_to(p_pos)
		# Fade tracker in when within 5.0m
		tracker.visible = dist < 5.0
		if cut_rings[i]:
			cut_rings[i].visible = dist < 12.0

func _find_player() -> Node3D:
	var settlers := get_tree().get_nodes_in_group("settler")
	if not settlers.is_empty() and settlers[0] is Node3D:
		return settlers[0] as Node3D
	return null

## Interacts with the nearest cut zone when E or LMB is pressed
func on_interact(actor: Node) -> void:
	chop(actor)

func take_damage(_amount: float = 0.0, actor: Node = null) -> void:
	chop(actor)

static func _get_pos(node: Node3D) -> Vector3:
	if not node:
		return Vector3.ZERO
	return node.global_position if node.is_inside_tree() else node.position

static func _get_xform(node: Node3D) -> Transform3D:
	if not node:
		return Transform3D.IDENTITY
	return node.global_transform if node.is_inside_tree() else node.transform

## Chops the nearest cut zone along the fallen trunk
func chop(actor: Node) -> void:
	var actor_pos := Vector3.ZERO
	if actor and actor is Node3D:
		actor_pos = _get_pos(actor as Node3D)
	else:
		actor_pos = _get_pos(self)

	# Find closest uncompleted cut zone using stem transform
	var stem_xf := _get_xform(self)
	var closest_idx := -1
	var min_dist := 999.0
	for i in range(cut_trackers.size()):
		if cut_completed[i]:
			continue
		var cut_z := 4.0 if i == 0 else 8.0
		var cut_world_pos := stem_xf * Vector3(0.0, trunk_radius, cut_z)
		var dist := cut_world_pos.distance_to(actor_pos)
		if dist < min_dist:
			min_dist = dist
			closest_idx = i

	if closest_idx == -1:
		# All cut zones severed, harvest final segment if any
		_sever_final_segment()
		return

	# Increment hits on the closest cut zone
	cut_hits[closest_idx] += 1
	_update_cut_tracker_display(closest_idx)

	# Pulse the cut ring if in tree
	if cut_rings[closest_idx] and is_inside_tree():
		var tween := create_tween()
		if tween:
			tween.tween_property(cut_rings[closest_idx], "scale", Vector3(1.3, 1.3, 1.3), 0.08)
			tween.tween_property(cut_rings[closest_idx], "scale", Vector3.ONE, 0.12)

	# 3 chops severs this section into a proper 4m CarryableLog
	if cut_hits[closest_idx] >= 3:
		_sever_cut_zone(closest_idx)

func _sever_cut_zone(cut_idx: int) -> void:
	cut_completed[cut_idx] = true
	_update_cut_tracker_display(cut_idx)

	# Spawn standard 4.0m CarryableLog at the severed section center
	var cut_offsets: Array[float] = [4.0, 8.0]
	var prev_offset: float = 0.0 if cut_idx == 0 else cut_offsets[cut_idx - 1]
	var cur_offset: float = cut_offsets[cut_idx]
	var center_offset: float = (prev_offset + cur_offset) * 0.5

	var stem_xf := _get_xform(self)
	var spawn_pos := stem_xf * Vector3(0.0, trunk_radius, center_offset)
	_spawn_carryable_log_at(spawn_pos)

	sections_remaining -= 1
	# If both cuts 0 and 1 are completed, automatically sever the final 3rd section
	if cut_completed[0] and cut_completed[1]:
		_sever_final_segment()

func _sever_final_segment() -> void:
	if sections_remaining <= 0:
		queue_free()
		return

	# The 3rd log spans from Z = 8.0m to 12.0m (center at 10.0m)
	var stem_xf := _get_xform(self)
	var spawn_pos := stem_xf * Vector3(0.0, trunk_radius, 10.0)
	_spawn_carryable_log_at(spawn_pos)
	sections_remaining = 0
	queue_free()

func _spawn_carryable_log_at(world_pos: Vector3) -> void:
	var parent := get_parent()
	if not parent:
		parent = get_tree().current_scene if get_tree() else null
	if not parent:
		return

	var log_script = load("res://scripts/environment/carryable_log.gd")
	var log_type_val = (CarryableLog.LogType.SPRUCE if tree_type == TreeType.SPRUCE else CarryableLog.LogType.BIRCH)

	var log_inst := RigidBody3D.new()
	log_inst.name = "CarryableLog_4m_%d" % [Time.get_ticks_msec() + randi() % 999]
	log_inst.set_script(log_script)
	log_inst.set("log_type", log_type_val)
	log_inst.set("timber_logs_yield", 1)
	log_inst.set("log_length", log_section_length)

	parent.add_child(log_inst)
	log_inst.global_position = world_pos
	log_inst.global_rotation = global_rotation

	# Gentle pop impulse
	log_inst.apply_impulse(Vector3(randf_range(-0.3, 0.3), 0.6, randf_range(-0.3, 0.3)))
