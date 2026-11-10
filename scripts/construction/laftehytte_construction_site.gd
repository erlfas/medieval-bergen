class_name LaftehytteConstructionSite
extends StaticBody3D

## In-world log-by-log construction site for an authentic Norwegian Laftehytte (Årestue).
## Instead of building a house in one instant step, the settler must fell trees,
## section them into 4m logs, haul them to the site, and slot them log-by-log.
## Provides high-visibility 3D in-world guidance:
## - A pulsing unshaded emerald target ghost log showing exact position and corner notch alignment
## - A floating 3D beacon arrow hovering above the active notch
## - A dynamic prompt: "⬇ Place Log: Course X - Wall Y [E / LMB]"

signal log_placed(step_index: int, total_steps: int, log_name: String)
signal construction_completed()

@export var cabin_width: float = 4.0
@export var cabin_depth: float = 4.0

var current_step_index: int = 0
var is_completed: bool = false
var log_sequence: Array[Dictionary] = []

# Visual guidance nodes
var guidance_root: Node3D
var target_ghost_log: MeshInstance3D
var beacon_arrow: Node3D
var beacon_label: Label3D
var beacon_mesh: MeshInstance3D

var placed_logs_container: Node3D
var solid_col_container: Node3D

static var _shared_ghost_mat: StandardMaterial3D = null
static var _shared_beacon_mat: StandardMaterial3D = null
static var _shared_solid_log_mesh: CylinderMesh = null
static var _shared_solid_log_mat: StandardMaterial3D = null

func _ready() -> void:
	_ensure_setup()

func _ensure_setup() -> void:
	if guidance_root != null:
		return
	add_to_group("construction_site")
	add_to_group("interactable")
	_build_log_sequence()
	_setup_materials()
	_setup_containers()
	_setup_guidance_visuals()
	_update_guidance_for_current_step()
	set_process(true)

func _setup_materials() -> void:
	if _shared_ghost_mat == null:
		_shared_ghost_mat = StandardMaterial3D.new()
		_shared_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_ghost_mat.albedo_color = Color(0.22, 0.95, 0.45, 0.55) # Radiant translucent emerald
		_shared_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_ghost_mat.no_depth_test = true
		_shared_ghost_mat.render_priority = 14

		_shared_beacon_mat = StandardMaterial3D.new()
		_shared_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_beacon_mat.albedo_color = Color(1.0, 0.85, 0.20, 0.95) # Golden beacon
		_shared_beacon_mat.no_depth_test = true
		_shared_beacon_mat.render_priority = 16

		_shared_solid_log_mesh = CylinderMesh.new()
		_shared_solid_log_mesh.top_radius = 0.19
		_shared_solid_log_mesh.bottom_radius = 0.21
		_shared_solid_log_mesh.height = 4.0
		_shared_solid_log_mesh.radial_segments = 14

		_shared_solid_log_mat = StandardMaterial3D.new()
		_shared_solid_log_mat.albedo_color = Color(0.42, 0.28, 0.16) # Rich weathered spruce heartwood
		_shared_solid_log_mat.roughness = 0.86

func _setup_containers() -> void:
	placed_logs_container = Node3D.new()
	placed_logs_container.name = "PlacedLogsContainer"
	add_child(placed_logs_container)

	solid_col_container = Node3D.new()
	solid_col_container.name = "SolidCollisionContainer"
	add_child(solid_col_container)

	# Pre-place 4 dry fieldstone corner plinths (Grunnmur corner stones)
	var half_w := cabin_width * 0.5
	var half_d := cabin_depth * 0.5
	var corners := [
		Vector3(-half_w, 0.15, -half_d),
		Vector3(half_w, 0.15, -half_d),
		Vector3(half_w, 0.15, half_d),
		Vector3(-half_w, 0.15, half_d),
	]
	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.55, 0.35, 0.55)
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.45, 0.44, 0.42)
	stone_mat.roughness = 0.92

	for c_pos in corners:
		var st := MeshInstance3D.new()
		st.mesh = stone_mesh
		st.material_override = stone_mat
		st.position = c_pos
		placed_logs_container.add_child(st)

func _build_log_sequence() -> void:
	log_sequence.clear()
	var half_w := cabin_width * 0.5
	var half_d := cabin_depth * 0.5
	var log_diam := 0.28

	# COURSE 1: Sill Logs (Syllstokker) - 4 logs resting on corner stones
	# South sill (door threshold)
	log_sequence.append({
		"name": "Course 1: South Sill (Syllstokk Sør)",
		"pos": Vector3(0.0, 0.28, half_d),
		"rot_y": 0.0,
		"length": cabin_width,
		"course": 1,
		"wall": "South"
	})
	# North sill
	log_sequence.append({
		"name": "Course 1: North Sill (Syllstokk Nord)",
		"pos": Vector3(0.0, 0.28, -half_d),
		"rot_y": 0.0,
		"length": cabin_width,
		"course": 1,
		"wall": "North"
	})
	# East sill (perpendicular)
	log_sequence.append({
		"name": "Course 1: East Sill (Syllstokk Øst)",
		"pos": Vector3(half_w, 0.40, 0.0),
		"rot_y": deg_to_rad(90.0),
		"length": cabin_depth,
		"course": 1,
		"wall": "East"
	})
	# West sill
	log_sequence.append({
		"name": "Course 1: West Sill (Syllstokk Vest)",
		"pos": Vector3(-half_w, 0.40, 0.0),
		"rot_y": deg_to_rad(90.0),
		"length": cabin_depth,
		"course": 1,
		"wall": "West"
	})

	# COURSES 2 through 6: Laftevegg Walls (4 logs per course, alternating overlap)
	for c in range(2, 7):
		var y_base := 0.40 + float(c - 1) * log_diam
		var y_side := y_base + log_diam * 0.5

		# East wall log
		log_sequence.append({
			"name": "Course %d: East Wall Log (Østvegg)" % c,
			"pos": Vector3(half_w, y_side, 0.0),
			"rot_y": deg_to_rad(90.0),
			"length": cabin_depth,
			"course": c,
			"wall": "East"
		})
		# West wall log
		log_sequence.append({
			"name": "Course %d: West Wall Log (Vestvegg)" % c,
			"pos": Vector3(-half_w, y_side, 0.0),
			"rot_y": deg_to_rad(90.0),
			"length": cabin_depth,
			"course": c,
			"wall": "West"
		})
		# North wall log
		log_sequence.append({
			"name": "Course %d: North Wall Log (Bakvegg)" % c,
			"pos": Vector3(0.0, y_base, -half_d),
			"rot_y": 0.0,
			"length": cabin_width,
			"course": c,
			"wall": "North"
		})
		# South wall log (leaves door opening in middle on courses 2-4)
		log_sequence.append({
			"name": "Course %d: South Wall Log (Forvegg)" % c,
			"pos": Vector3(0.0, y_base, half_d),
			"rot_y": 0.0,
			"length": cabin_width,
			"course": c,
			"wall": "South"
		})

	# COURSE 7: Triangular Gables & Ridge Beam (Laftegavl & Mønsås)
	var y_gable1 := 0.40 + 5.0 * log_diam
	log_sequence.append({
		"name": "Course 7: West Gable Lower Log (Gavl Vest)",
		"pos": Vector3(-half_w, y_gable1 + 0.28, 0.0),
		"rot_y": deg_to_rad(90.0),
		"length": 3.0,
		"course": 7,
		"wall": "Gable"
	})
	log_sequence.append({
		"name": "Course 7: East Gable Lower Log (Gavl Øst)",
		"pos": Vector3(half_w, y_gable1 + 0.28, 0.0),
		"rot_y": deg_to_rad(90.0),
		"length": 3.0,
		"course": 7,
		"wall": "Gable"
	})
	log_sequence.append({
		"name": "Course 7: Upper Gable Apex Logs (Gavltopp)",
		"pos": Vector3(-half_w, y_gable1 + 0.56, 0.0),
		"rot_y": deg_to_rad(90.0),
		"length": 1.8,
		"course": 7,
		"wall": "Gable"
	})
	# Central Ridge Beam (Mønsås)
	log_sequence.append({
		"name": "Course 7: Heavy Ridge Beam (Mønsås)",
		"pos": Vector3(0.0, y_gable1 + 0.85, 0.0),
		"rot_y": 0.0,
		"length": cabin_width + 0.4,
		"course": 7,
		"wall": "Ridge"
	})

func _setup_guidance_visuals() -> void:
	guidance_root = Node3D.new()
	guidance_root.name = "GuidanceRoot"
	add_child(guidance_root)

	# 1. Pulsing target ghost log
	target_ghost_log = MeshInstance3D.new()
	target_ghost_log.name = "TargetGhostLog"
	target_ghost_log.mesh = _shared_solid_log_mesh
	target_ghost_log.material_override = _shared_ghost_mat
	# Orient horizontally along local X
	target_ghost_log.rotation.z = deg_to_rad(90.0)
	guidance_root.add_child(target_ghost_log)

	# 2. Floating 3D beacon arrow hovering above the target slot
	beacon_arrow = Node3D.new()
	beacon_arrow.name = "BeaconArrow"
	guidance_root.add_child(beacon_arrow)

	beacon_mesh = MeshInstance3D.new()
	beacon_mesh.name = "ArrowMesh"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.25
	cone.height = 0.55
	cone.radial_segments = 8
	beacon_mesh.mesh = cone
	beacon_mesh.material_override = _shared_beacon_mat
	beacon_mesh.rotation.x = deg_to_rad(180.0) # Pointing down
	beacon_arrow.add_child(beacon_mesh)

	# Billboard text label
	beacon_label = Label3D.new()
	beacon_label.name = "BeaconLabel"
	beacon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	beacon_label.no_depth_test = true
	beacon_label.render_priority = 18
	beacon_label.font_size = 24
	beacon_label.outline_size = 6
	beacon_label.modulate = Color(1.0, 0.90, 0.25)
	beacon_label.outline_modulate = Color(0.05, 0.04, 0.03, 0.95)
	beacon_label.position = Vector3(0.0, 0.55, 0.0)
	beacon_arrow.add_child(beacon_label)

func _update_guidance_for_current_step() -> void:
	if is_completed or current_step_index >= log_sequence.size():
		is_completed = true
		if guidance_root:
			guidance_root.visible = false
		add_to_group("shelter")
		construction_completed.emit()
		return

	var step: Dictionary = log_sequence[current_step_index]
	var target_pos: Vector3 = step["pos"]
	var target_rot_y: float = step["rot_y"]
	var step_name: String = step["name"]
	var log_len: float = step.get("length", 4.0)

	# Update ghost log transform
	if target_ghost_log:
		target_ghost_log.position = target_pos
		target_ghost_log.rotation = Vector3(0.0, target_rot_y, deg_to_rad(90.0))
		target_ghost_log.scale = Vector3(1.0, log_len / 4.0, 1.0)

	# Update beacon arrow position (hovering 1.4m above target slot)
	if beacon_arrow:
		beacon_arrow.position = target_pos + Vector3(0.0, 1.4, 0.0)

	if beacon_label:
		beacon_label.text = "⬇ PLACE LOG (%d/%d):\n%s\n[E / LMB to Fit Log]" % [current_step_index + 1, log_sequence.size(), step_name]

func _process(_delta: float) -> void:
	if is_completed:
		return

	var time_ms := Time.get_ticks_msec()

	# 1. Pulse ghost log alpha
	if target_ghost_log and _shared_ghost_mat:
		var pulse := 0.45 + 0.30 * sin(float(time_ms) * 0.005)
		_shared_ghost_mat.albedo_color.a = pulse

	# 2. Bob beacon arrow vertically
	if beacon_arrow and current_step_index < log_sequence.size():
		var base_y: float = log_sequence[current_step_index]["pos"].y + 1.4
		beacon_arrow.position.y = base_y + 0.12 * sin(float(time_ms) * 0.004)

	# 3. Check settler proximity and carried log state
	var settler := _find_player()
	if settler:
		var is_carrying: bool = settler.get("is_carrying_log") == true
		var t_pos: Vector3 = log_sequence[current_step_index]["pos"]
		var target_world: Vector3 = global_transform * t_pos
		var dist := settler.global_position.distance_to(target_world)

		if is_carrying:
			# If carrying a log, glow brighter
			if _shared_beacon_mat:
				_shared_beacon_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.98) # Bright emerald
			if dist < 3.2:
				beacon_label.modulate = Color(0.35, 1.0, 0.45)
				beacon_label.text = "⬇ [E / LMB] SNAP LOG INTO NOTCH!\n%s" % log_sequence[current_step_index]["name"]
			else:
				beacon_label.modulate = Color(1.0, 0.90, 0.25)
				beacon_label.text = "⬇ CARRY LOG HERE (%d/%d):\n%s" % [current_step_index + 1, log_sequence.size(), log_sequence[current_step_index]["name"]]
		else:
			if _shared_beacon_mat:
				_shared_beacon_mat.albedo_color = Color(1.0, 0.82, 0.22, 0.95) # Amber
			beacon_label.modulate = Color(1.0, 0.85, 0.35)
			beacon_label.text = "⬇ NEED 4m TIMBER LOG (%d/%d):\n%s\n[Chop tree and bring 4m log]" % [current_step_index + 1, log_sequence.size(), log_sequence[current_step_index]["name"]]

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		remove_from_group("construction_site")
		remove_from_group("interactable")
		remove_from_group("shelter")

static func _get_pos(node: Node3D) -> Vector3:
	if not node:
		return Vector3.ZERO
	return node.global_position if node.is_inside_tree() else node.position

static func _get_xform(node: Node3D) -> Transform3D:
	if not node:
		return Transform3D.IDENTITY
	return node.global_transform if node.is_inside_tree() else node.transform

func _find_player() -> Node3D:
	if not is_inside_tree():
		return null
	var settlers := get_tree().get_nodes_in_group("settler")
	if not settlers.is_empty() and settlers[0] is Node3D:
		return settlers[0] as Node3D
	return null

## Checks if settler can place a carried log into the active slot
func can_place_log(actor: Node) -> bool:
	if is_completed or current_step_index >= log_sequence.size():
		return false
	if not actor or actor.get("is_carrying_log") != true:
		return false

	var t_pos: Vector3 = log_sequence[current_step_index]["pos"]
	var target_world: Vector3 = _get_xform(self) * t_pos
	var actor_node := actor as Node3D
	if actor_node:
		var dist := _get_pos(actor_node).distance_to(target_world)
		return dist < 4.5
	return true

## Slots the carried log into the active notch, advancing construction
func place_carried_log(actor: Node) -> bool:
	if not can_place_log(actor):
		return false

	# Consume the log carried by the settler
	if actor.has_method("consume_carried_log"):
		actor.consume_carried_log()

	var step: Dictionary = log_sequence[current_step_index]
	_spawn_solid_log(step)

	var prev_name: String = step["name"]
	var prev_idx := current_step_index
	current_step_index += 1

	log_placed.emit(prev_idx + 1, log_sequence.size(), prev_name)
	_update_guidance_for_current_step()
	return true

func _spawn_solid_log(step: Dictionary) -> void:
	var pos: Vector3 = step["pos"]
	var rot_y: float = step["rot_y"]
	var log_len: float = step.get("length", 4.0)

	var log_mesh := MeshInstance3D.new()
	log_mesh.name = "SolidLog_%d" % current_step_index
	if is_equal_approx(log_len, 4.0):
		log_mesh.mesh = _shared_solid_log_mesh
	else:
		var custom_cyl := CylinderMesh.new()
		custom_cyl.top_radius = 0.19
		custom_cyl.bottom_radius = 0.21
		custom_cyl.height = log_len
		custom_cyl.radial_segments = 14
		log_mesh.mesh = custom_cyl

	log_mesh.material_override = _shared_solid_log_mat
	log_mesh.position = pos
	log_mesh.rotation = Vector3(0.0, rot_y, deg_to_rad(90.0))
	placed_logs_container.add_child(log_mesh)

	# Add physical collision for this placed log
	var col := CollisionShape3D.new()
	col.name = "Col_%d" % current_step_index
	var cap := CapsuleShape3D.new()
	cap.radius = 0.20
	cap.height = log_len
	col.shape = cap
	col.position = pos
	col.rotation = Vector3(0.0, rot_y, deg_to_rad(90.0))
	solid_col_container.add_child(col)

	# Spawn visual woodchip placement puff if inside tree
	if is_inside_tree():
		_spawn_placement_feedback(_get_xform(self) * pos)

func _spawn_placement_feedback(world_pos: Vector3) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 7
	label.modulate = Color(0.3, 1.0, 0.45)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	label.text = "🪵 NOTCH LOCKED! (Lafteknute Festet)"

	var parent := get_parent()
	if not parent:
		parent = get_tree().current_scene if get_tree() else null
	if parent and parent.is_inside_tree():
		parent.add_child(label)
		label.global_position = world_pos + Vector3(0.0, 0.6, 0.0)
		var tween := label.create_tween()
		if tween:
			tween.tween_property(label, "global_position:y", label.global_position.y + 0.8, 0.85)
			tween.parallel().tween_property(label, "modulate:a", 0.0, 0.85)
			tween.tween_callback(label.queue_free)

## Interacts with the construction site when settler presses E or LMB
func on_interact(actor: Node) -> void:
	if actor and actor.get("is_carrying_log") == true:
		place_carried_log(actor)
