class_name SettlerController
extends CharacterBody3D

## Settler controller for Medieval Bergen 1360:
## - Controllable gray box man with head, torso, animated arms/hands, and legs/boots
## - Smooth third-person follow camera with gentle damping, mouse look orbit, and collision safety
## - Third-person / First-person camera toggle [V] and mouse wheel zoom
## - Physical log carrying: pick up with [E], hold in front, drop with [E] or [G]
## - Survival interactions: tree chopping, freshwater drinking, wolf defense, hunting
## - Pine-tar torch [F] with warm light and wolf deterrence
## - Piece-by-piece modular construction system [B] and full Log Cabin assembly
## - Cabin Builder's Guide [C] for medieval architectural instructions

signal carrying_state_changed(is_carrying: bool)

const EquipmentManager = preload("res://scripts/player/equipment_manager.gd")

@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025

@export_group("Kinematic Movement & Inertia (Stage 1)")
@export var ground_acceleration: float = 15.0
@export var ground_deceleration: float = 24.0
@export var braking_deceleration: float = 34.0
@export var air_acceleration: float = 5.0
@export var jump_buffer_time: float = 0.14
@export var coyote_time: float = 0.12
@export var fall_gravity_multiplier: float = 1.35
@export var slope_speed_factor: float = 0.35

@export_group("Follow-Behind Camera & WASD Steering")
@export var is_third_person: bool = true
@export var target_cam_distance: float = 3.2
@export var cam_height_offset: float = 0.45
@export var character_turn_speed: float = 11.0   ## Smooth character body turning
@export var steering_speed: float = 3.2          ## Angular yaw speed when steering with A/D (rad/sec, ~183 deg/s)
@export var reverse_speed: float = 2.6           ## Walk speed when walking backward with S (m/s)
@export var cam_follow_yaw_speed: float = 10.0   ## Smooth rotational lag for follow-behind camera
@export var cam_vertical_smooth_speed: float = 14.0 ## Damping for vertical terrain steps & bumps

@export_group("Swimming & Water (Task 2)")
@export var swim_speed: float = 2.8
@export var swim_sprint_speed: float = 4.4
@export var water_surface_offset: float = 0.2  ## Buoyancy surface position: y = sea_level + 0.2

@export_group("Mountain Climbing & Rope (Task 7)")
@export var climb_speed: float = 2.4
@export var rope_climb_speed: float = 3.2
@export var rope_rappel_speed: float = 4.8

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_raycast: RayCast3D = $Head/InteractRayCast
@onready var survival_stats: Node = $SurvivalStats
@onready var inventory: Node = $InventoryManager
@onready var player_builder: Node = $PlayerBuilder
@onready var equipment: Node = $EquipmentManager

var box_man_model: Node3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var is_holding_torch: bool = false
var is_carrying_log: bool = false
var torch_light: OmniLight3D
var terrain_generator: Node

# State flags for swimming and mountain climbing
var is_swimming: bool = false
var is_wading: bool = false
var is_climbing: bool = false
var climb_normal: Vector3 = Vector3.BACK
var is_on_rope: bool = false
var active_rope: Node = null
var _climb_cooldown: float = 0.0
var _climb_lost_contact_timer: float = 0.0
var _ripple_timer: float = 0.0

var cam_yaw: float = 0.0
var cam_pitch: float = deg_to_rad(-8.0)
var current_cam_distance: float = 3.2
var _smoothed_pivot_y: float = 0.0
var _current_safe_dist: float = 3.2

# Camera trauma / screen shake system (impacts, tree topples, ground slams)
var camera_trauma: float = 0.0
var _trauma_timer: float = 0.0

## Adds procedural camera trauma/shake [0.0, 1.0]
func add_camera_trauma(amount: float) -> void:
	camera_trauma = clampf(camera_trauma + amount, 0.0, 1.0)

# Stage 1 Kinematic jump buffering & coyote timers
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

static var _shared_ripple_mesh: TorusMesh

func _spawn_water_ripple(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var ripple := MeshInstance3D.new()
	if _shared_ripple_mesh == null:
		_shared_ripple_mesh = TorusMesh.new()
		_shared_ripple_mesh.inner_radius = 0.20
		_shared_ripple_mesh.outer_radius = 0.35
		_shared_ripple_mesh.rings = 16
		_shared_ripple_mesh.ring_segments = 6
	ripple.mesh = _shared_ripple_mesh

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.65)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ripple.material_override = mat

	ripple.position = pos
	var parent_node := get_parent()
	if parent_node:
		parent_node.add_child(ripple)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ripple, "scale", Vector3(3.2, 1.0, 3.2), 0.65).from(Vector3(0.5, 1.0, 0.5))
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.65)
	tween.chain().tween_callback(ripple.queue_free)

func _enter_tree() -> void:
	_ensure_box_man_model()

func _ready() -> void:
	add_to_group("settler")
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# CharacterBody3D floor snap and anti-snag slope configuration
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(48.0)
	if get_tree():
		terrain_generator = get_tree().get_first_node_in_group("terrain_generator")

	_ensure_box_man_model()
	_ensure_equipment_manager()
	_create_torch_light()

	# Snap settler vertically to terrain surface
	if terrain_generator:
		var ground_h: float = float(terrain_generator.sample_height(global_position.x, global_position.z))
		global_position.y = maxf(global_position.y, ground_h + 0.1)

	# Configure camera and raycast to be top_level for smooth independent orbit & follow
	if camera:
		camera.top_level = true
	if interact_raycast:
		interact_raycast.top_level = true
		interact_raycast.add_exception(self)

	current_cam_distance = target_cam_distance if is_third_person else 0.0
	_current_safe_dist = current_cam_distance
	cam_yaw = rotation.y
	_smoothed_pivot_y = global_position.y + 1.45
	_update_camera(0.0)

	# Spawn initial starter carryable logs near settler for immediate testing
	call_deferred("_spawn_starter_logs")


func _ensure_box_man_model() -> void:
	box_man_model = get_node_or_null("BoxManModel")
	if box_man_model == null:
		var script_model = load("res://scripts/player/box_man_model.gd")
		var node: Node3D = Node3D.new()
		node.name = "BoxManModel"
		node.set_script(script_model)
		add_child(node)
		if node.has_method("_build_box_man") and node.get("torso_node") == null:
			node._build_box_man()
		box_man_model = node
	elif box_man_model.has_method("_build_box_man") and box_man_model.get("torso_node") == null:
		box_man_model._build_box_man()

func _ensure_equipment_manager() -> void:
	if equipment == null:
		equipment = get_node_or_null("EquipmentManager") as EquipmentManager
	if equipment == null:
		var eq_script = load("res://scripts/player/equipment_manager.gd")
		if eq_script:
			var node := Node.new()
			node.name = "EquipmentManager"
			node.set_script(eq_script)
			add_child(node)
			equipment = node as EquipmentManager

func _create_torch_light() -> void:
	torch_light = OmniLight3D.new()
	torch_light.name = "TorchLight"
	torch_light.light_color = Color(1.0, 0.65, 0.28) # Warm fire glow
	torch_light.light_energy = 1.4
	torch_light.omni_range = 14.0
	torch_light.shadow_enabled = false
	if head:
		head.add_child(torch_light)
	else:
		add_child(torch_light)

func _spawn_starter_logs() -> void:
	var existing_logs := get_tree().get_nodes_in_group("carryable_log")
	if existing_logs.size() >= 2:
		return

	var carryable_log_script = load("res://scripts/environment/carryable_log.gd")
	if not carryable_log_script:
		return

	var scene_root := get_parent()
	if not scene_root:
		return

	var spawn_offsets := [
		Vector3(1.8, 0.4, -2.0),
		Vector3(-2.2, 0.4, -1.8),
		Vector3(0.5, 0.4, -3.2)
	]
	for offset in spawn_offsets:
		var log_inst: RigidBody3D = carryable_log_script.create_log()
		scene_root.add_child(log_inst)
		var target_pos: Vector3 = global_position + offset
		if terrain_generator:
			var gh: float = float(terrain_generator.sample_height(target_pos.x, target_pos.z))
			target_pos.y = gh + 0.3
		log_inst.global_position = target_pos
		log_inst.rotation.y = randf_range(0.0, TAU)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse Look & Pitch: vertical look angle and optional mouse yaw steering
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_pitch -= event.relative.y * mouse_sensitivity
		cam_pitch = clampf(cam_pitch, deg_to_rad(-65.0), deg_to_rad(70.0))

		# Mouse yaw rotates character facing directly; follow-behind camera tracks behind smoothly
		rotation.y -= event.relative.x * mouse_sensitivity
		if not is_third_person:
			head.rotation.x = cam_pitch
			cam_yaw = rotation.y

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Toggle Camera View [V]
	if event.is_action_pressed("toggle_camera_view"):
		is_third_person = not is_third_person
		target_cam_distance = 3.2 if is_third_person else 0.0

	# Mouse wheel zoom in / out
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_cam_distance = clampf(target_cam_distance - 0.4, 0.0, 6.0)
			is_third_person = target_cam_distance > 0.35
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_cam_distance = clampf(target_cam_distance + 0.4, 0.0, 6.0)
			is_third_person = target_cam_distance > 0.35

	# Drop log with [G]
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_G:
			if is_carrying_log:
				drop_log()
		elif event.physical_keycode == KEY_C:
			var hud_bar = get_tree().get_first_node_in_group("hud_building_bar")
			if hud_bar and hud_bar.has_method("toggle_cabin_guide"):
				hud_bar.toggle_cabin_guide()
		elif event.physical_keycode == KEY_K:
			_place_campfire()

	# Hotbar Slot Selection [1], [2], [3], [4], [5]
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_1:
			if equipment: equipment.select_slot(1)
		elif event.physical_keycode == KEY_2:
			if equipment: equipment.select_slot(2)
		elif event.physical_keycode == KEY_3:
			if equipment: equipment.select_slot(3)
		elif event.physical_keycode == KEY_4:
			if equipment: equipment.select_slot(4)
		elif event.physical_keycode == KEY_5:
			if equipment: equipment.select_slot(5)
		elif event.physical_keycode == KEY_6:
			if equipment: equipment.select_slot(6)
		elif event.physical_keycode == KEY_7:
			if equipment: equipment.select_slot(7)

	# Interaction Key (E) - pick up or drop log, or interact with objects
	if event.is_action_pressed("interact"):
		if is_carrying_log:
			if not _try_slot_carried_log_into_construction_site():
				drop_log()
		else:
			_perform_interaction()

	# Toggle Torch [F]
	if event.is_action_pressed("toggle_torch"):
		toggle_torch()

	# Climbing Rope Tool [R] (when NOT building) or [T] (Task 7)
	if (event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_R and (not player_builder or not player_builder.is_build_mode) or event.physical_keycode == KEY_T)) or event.is_action_pressed("deploy_rope"):
		_handle_climbing_rope_tool()

	# Primary Item Use / Attack / Bow Aim & Release / Slot Carried Log (Left Click)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if is_carrying_log:
			if event.pressed:
				_try_slot_carried_log_into_construction_site()
		elif not player_builder or not player_builder.is_build_mode:
			if equipment:
				if equipment.current_slot == EquipmentManager.Slot.BOW:
					if event.pressed:
						equipment.start_bow_aim()
					else:
						equipment.release_bow(camera)
				elif event.pressed:
					var target_tree: Node = _get_target_or_focused_tree()
					if target_tree:
						_chop_tree(target_tree)
					else:
						equipment.use_primary(interact_raycast, camera)
			elif event.pressed:
				var target_tree: Node = _get_target_or_focused_tree()
				if target_tree:
					_chop_tree(target_tree)
				else:
					_perform_attack_or_chop()

	# Cancel bow aim with Right Click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if equipment and equipment.is_aiming_bow:
			equipment.cancel_bow_aim()

	# Quick Eat / Roast [H]
	if event.is_action_pressed("eat_food"):
		_try_eat()

func toggle_torch() -> void:
	if is_carrying_log:
		return # Cannot hold torch while carrying a log
	if equipment:
		if equipment.current_slot == EquipmentManager.Slot.TORCH:
			equipment.select_slot(EquipmentManager.Slot.AXE)
		else:
			equipment.select_slot(EquipmentManager.Slot.TORCH)
	else:
		is_holding_torch = not is_holding_torch
		if torch_light:
			torch_light.visible = is_holding_torch

func _physics_process(delta: float) -> void:
	if _climb_cooldown > 0.0:
		_climb_cooldown -= delta

	# Jump buffer timer and coyote timer update
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	elif _jump_buffer_timer > 0.0:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	if is_on_floor() and not is_swimming and not is_climbing and not is_on_rope:
		_coyote_timer = coyote_time
	elif _coyote_timer > 0.0:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	# WASD Steering & Drive Inputs
	# A: +1.0 (turn left), D: -1.0 (turn right)
	var turn_input := Input.get_axis("move_right", "move_left")
	# W: +1.0 (forward), S: -1.0 (backward)
	var drive_input := Input.get_axis("move_backward", "move_forward")

	var is_aiming: bool = (equipment != null and bool(equipment.get("is_aiming_bow")))
	var is_strafing: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or is_aiming

	# Continuous yaw steering with A/D (allows full 360-degree rotation purely with keyboard)
	if not is_climbing and not is_on_rope:
		if is_strafing:
			# In strafe mode, mouse or heading controls yaw
			pass
		elif absf(turn_input) > 0.01:
			rotation.y += turn_input * steering_speed * delta

	# Calculate movement direction
	var forward_vec := -global_transform.basis.z
	var right_vec := global_transform.basis.x
	var direction := Vector3.ZERO

	if is_strafing:
		var raw_strafe := (forward_vec * drive_input - right_vec * turn_input)
		if raw_strafe.length_squared() > 0.001:
			direction = raw_strafe.normalized()
	else:
		if drive_input > 0.01:
			direction = forward_vec
		elif drive_input < -0.01:
			direction = -forward_vec

	var sea_level := 0.0
	var water_surface_y := sea_level + water_surface_offset
	if terrain_generator:
		sea_level = terrain_generator.sea_level
		if terrain_generator.has_method("sample_water_height"):
			water_surface_y = terrain_generator.sample_water_height(global_position.x, global_position.z) + water_surface_offset
		else:
			water_surface_y = sea_level + water_surface_offset

	var ground_h := sea_level - 10.0
	if terrain_generator:
		ground_h = terrain_generator.sample_height(global_position.x, global_position.z)

	# -------------------------------------------------------------
	# 1. WATER, WADING & SWIMMING STATE TRANSITION (Stage 4)
	# -------------------------------------------------------------
	var water_submergence := water_surface_y - global_position.y
	var water_column := water_surface_y - ground_h

	if is_swimming:
		# If already swimming, stay swimming until reaching shallow water where feet touch bottom
		if water_column < 0.90 and is_on_floor():
			is_swimming = false
			is_wading = water_submergence > 0.08
		else:
			is_swimming = true
			is_wading = false
			is_climbing = false
			is_on_rope = false
			active_rope = null
	else:
		if water_submergence > 0.08 and water_column > 0.12:
			# Deep swimming engages when water depth > 1.35m or character is submerged > 1.0m
			if water_column >= 1.35 or water_submergence >= 1.0 or not is_on_floor():
				is_swimming = true
				is_wading = false
				is_climbing = false
				is_on_rope = false
				active_rope = null
			else:
				is_wading = true
				is_swimming = false
		else:
			is_wading = false
			is_swimming = false

	# -------------------------------------------------------------
	# 2. MOUNTAIN CLIFF DETECTION & ROCK CLIMBING ENGAGE (Task 7)
	# -------------------------------------------------------------
	if _climb_cooldown <= 0.0 and not is_climbing and not is_swimming and not is_on_rope and not is_carrying_log:
		var moving_into_cliff := drive_input > 0.2
		var jump_pressed := Input.is_action_just_pressed("jump")
		if jump_pressed or moving_into_cliff:
			var cliff_info := _check_steep_cliff()
			if not cliff_info.is_empty():
				is_climbing = true
				climb_normal = cliff_info.normal
				velocity = Vector3.ZERO

	# -------------------------------------------------------------
	# 3. MOVEMENT BY STATE
	# -------------------------------------------------------------
	if is_on_rope and active_rope and is_instance_valid(active_rope):
		# CLIMBING ROPE TOOL / RAPPELLING (Task 7)
		var rope_target: Vector3 = active_rope.get_closest_point(global_position)
		global_position.x = lerpf(global_position.x, rope_target.x, delta * 12.0)
		global_position.z = lerpf(global_position.z, rope_target.z, delta * 12.0)

		var vert_input := drive_input
		if vert_input > 0.1:
			# Climb UP rope
			velocity.y = rope_climb_speed
		elif vert_input < -0.1:
			# Rappel DOWN rope smoothly (hold sprint for fast rappel)
			var rappel_spd := rope_rappel_speed * (1.5 if Input.is_action_pressed("sprint") else 1.0)
			velocity.y = -rappel_spd
		else:
			velocity.y = 0.0

		velocity.x = 0.0
		velocity.z = 0.0

		# Disengage / jump off rope
		if Input.is_action_just_pressed("jump"):
			is_on_rope = false
			velocity = -global_transform.basis.z * 3.5 + Vector3.UP * 2.5
			active_rope = null

		# Check top anchor reached -> step up onto ledge
		elif global_position.y >= active_rope.get_top_position().y - 0.2 and vert_input > 0.1:
			global_position = active_rope.get_top_position() + Vector3(0.0, 0.2, 0.0) - global_transform.basis.z * 0.8
			is_on_rope = false
			active_rope = null
			velocity = Vector3.ZERO

		# Check bottom ground reached -> step off rope
		elif global_position.y <= active_rope.get_bottom_position().y + 0.3 and vert_input < -0.1:
			is_on_rope = false
			active_rope = null
			velocity = Vector3.ZERO

	elif is_climbing:
		# Check if cliff contact is maintained - grace period prevents premature fall on uneven terrain
		var track_info := _check_steep_cliff()
		if track_info.is_empty():
			_climb_lost_contact_timer += delta
			if _climb_lost_contact_timer > 0.35:
				is_climbing = false
				_climb_lost_contact_timer = 0.0
				_climb_cooldown = 0.3
				velocity = Vector3.DOWN * 2.5
		else:
			_climb_lost_contact_timer = 0.0
			climb_normal = track_info.normal
			# Wall distance adhesion: maintain snug ~0.42m distance to rock face
			if track_info.has("position"):
				var hit_p: Vector3 = track_info.position
				var ideal_pos := hit_p + climb_normal * 0.42
				global_position.x = lerpf(global_position.x, ideal_pos.x, delta * 8.0)
				global_position.z = lerpf(global_position.z, ideal_pos.z, delta * 8.0)

		# FREEFORM ROCK CLIMBING
		# W climbs UP, S climbs DOWN, A climbs LEFT, D climbs RIGHT
		var cliff_right := Vector3.UP.cross(climb_normal).normalized()
		var climb_move := Vector3.UP * drive_input - cliff_right * turn_input

		if climb_move != Vector3.ZERO:
			velocity = climb_move.normalized() * climb_speed
			survival_stats.consume_stamina(6.0 * delta)
		else:
			velocity = Vector3.ZERO
			survival_stats.consume_stamina(1.5 * delta)

		# Orient settler to face directly into the cliff
		var target_facing := atan2(-climb_normal.x, -climb_normal.z)
		rotation.y = lerp_angle(rotation.y, target_facing, delta * 12.0)

		# Exhaustion slip if stamina depletes
		if survival_stats.stamina <= 0.0:
			is_climbing = false
			_climb_lost_contact_timer = 0.0
			_climb_cooldown = 1.0
			velocity = climb_normal * 1.5 + Vector3.DOWN * 2.0

		# Push off / Jump off cliff face
		if Input.is_action_just_pressed("jump"):
			is_climbing = false
			_climb_lost_contact_timer = 0.0
			_climb_cooldown = 0.45
			velocity = climb_normal * 4.2 + Vector3.UP * 3.6

		# Vault/Mantle onto top ledge if reached
		if drive_input > 0.1:
			var forward_into_cliff := -climb_normal
			var ledge_test_origin := global_position + Vector3(0.0, 1.7, 0.0) + forward_into_cliff * 0.75
			var ledge_query := PhysicsRayQueryParameters3D.create(ledge_test_origin, ledge_test_origin + Vector3.DOWN * 1.8)
			ledge_query.exclude = [get_rid()]
			var space_state := get_world_3d().direct_space_state
			if space_state:
				var ledge_hit := space_state.intersect_ray(ledge_query)
				if not ledge_hit.is_empty():
					var l_norm: Vector3 = ledge_hit.normal
					if l_norm.angle_to(Vector3.UP) < deg_to_rad(45.0):
						global_position = ledge_hit.position + Vector3(0.0, 0.1, 0.0)
						is_climbing = false
						_climb_lost_contact_timer = 0.0
						_climb_cooldown = 0.5
						velocity = Vector3.ZERO

		# Reached ground at base of cliff
		if drive_input < -0.2 and is_on_floor():
			is_climbing = false
			_climb_lost_contact_timer = 0.0
			_climb_cooldown = 0.2

	elif is_swimming:
		# SWIMMING MECHANICS (Dynamic Wave Buoyancy)
		# Buoyancy keeps character afloat dynamically with waterline at chest height
		var target_swim_y := water_surface_y - 1.25
		if global_position.y < target_swim_y:
			var depth := target_swim_y - global_position.y
			velocity.y = lerpf(velocity.y, depth * 7.0 + 0.8, delta * 6.5)
			global_position.y = lerpf(global_position.y, target_swim_y, delta * 4.5)
		elif global_position.y > target_swim_y + 0.35:
			velocity.y -= gravity * delta * 0.70
		else:
			velocity.y = lerpf(velocity.y, 0.0, delta * 7.0)
			global_position.y = lerpf(global_position.y, target_swim_y, delta * 4.5)

		# Jump: treading boost or leaping onto shallow shoreline
		if Input.is_action_just_pressed("jump"):
			_spawn_water_ripple(Vector3(global_position.x, water_surface_y + 0.02, global_position.z))
			if ground_h >= water_surface_y - 1.1:
				velocity.y = 4.8
				if direction != Vector3.ZERO:
					velocity += direction * 3.6
			else:
				velocity.y = 2.6

		# Swim speed & gentle water drag
		var current_swim_speed := swim_speed
		var is_swim_sprinting: bool = Input.is_action_pressed("sprint") and (survival_stats != null and float(survival_stats.get("stamina")) > 5.0)
		if is_swim_sprinting:
			current_swim_speed = swim_sprint_speed
			if survival_stats:
				survival_stats.consume_stamina(6.5 * delta)
		elif survival_stats:
			survival_stats.consume_stamina(1.8 * delta)

		if is_carrying_log:
			current_swim_speed *= 0.65

		if direction != Vector3.ZERO:
			velocity.x = move_toward(velocity.x, direction.x * current_swim_speed, delta * 8.0)
			velocity.z = move_toward(velocity.z, direction.z * current_swim_speed, delta * 8.0)
			if is_third_person and is_strafing:
				var target_heading := atan2(-direction.x, -direction.z)
				rotation.y = lerp_angle(rotation.y, target_heading, delta * character_turn_speed)

			# Swimming stroke surface ripples
			_ripple_timer -= delta
			if _ripple_timer <= 0.0:
				_ripple_timer = 0.45
				_spawn_water_ripple(Vector3(global_position.x, water_surface_y + 0.02, global_position.z))
		else:
			# Gentle water drag deceleration
			velocity.x = move_toward(velocity.x, 0.0, delta * 4.5)
			velocity.z = move_toward(velocity.z, 0.0, delta * 4.5)

		# Cold Bergen water increases wetness
		if survival_stats:
			survival_stats.wetness = minf(100.0, survival_stats.wetness + 25.0 * delta)

	else:
		# NORMAL GROUND / AIR MOVEMENT (Stage 1 Kinematic Physics & Stage 4 Wading)
		var on_floor := is_on_floor()

		# Snappier gravity curve: heavier fall gravity for physical, responsive jump arcs
		if not on_floor:
			var current_gravity := gravity * (fall_gravity_multiplier if velocity.y < 0.0 else 1.0)
			velocity.y -= current_gravity * delta

		# Coyote time & Jump buffering
		if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
			var stamina_cost := 16.0 if is_carrying_log else 12.0
			if survival_stats.consume_stamina(stamina_cost):
				velocity.y = jump_velocity
				_jump_buffer_timer = 0.0
				_coyote_timer = 0.0

		# Sprinting (only when moving forward)
		var can_sprint: bool = not is_carrying_log and (survival_stats != null and float(survival_stats.get("stamina")) > 5.0) and drive_input > 0.0
		is_sprinting = Input.is_action_pressed("sprint") and on_floor and can_sprint
		var base_speed := walk_speed * (0.85 if is_carrying_log else 1.0)
		var speed := base_speed
		if drive_input > 0.01:
			speed = sprint_speed if is_sprinting else base_speed
		elif drive_input < -0.01:
			speed = reverse_speed

		if is_sprinting and direction != Vector3.ZERO:
			survival_stats.consume_stamina(10.0 * delta)

		# Shallow Wading Drag & Wetness (Stage 4)
		if is_wading:
			var wading_drag := clampf(1.0 - (water_submergence / 1.1) * 0.45, 0.55, 0.95)
			speed *= wading_drag
			if survival_stats:
				survival_stats.wetness = minf(100.0, survival_stats.wetness + 14.0 * delta)

			# Surface wake ripples when wading in shallow surf
			if direction != Vector3.ZERO:
				_ripple_timer -= delta
				if _ripple_timer <= 0.0:
					_ripple_timer = 0.38
					_spawn_water_ripple(Vector3(global_position.x, water_surface_y + 0.02, global_position.z))

		# Slope incline speed modulation
		var slope_mult := 1.0
		if on_floor:
			var floor_norm := get_floor_normal()
			var slope_ang := floor_norm.angle_to(Vector3.UP)
			if slope_ang > 0.05 and direction != Vector3.ZERO:
				var slope_h_dir := Vector3(floor_norm.x, 0.0, floor_norm.z).normalized()
				var uphill_dot := direction.dot(-slope_h_dir)
				slope_mult = clampf(1.0 + uphill_dot * sin(slope_ang) * slope_speed_factor * (-1.0 if uphill_dot > 0.0 else 0.4), 0.65, 1.15)

		var target_speed := speed * slope_mult
		var target_horiz := direction * target_speed

		if on_floor:
			if direction != Vector3.ZERO:
				# Active direction reversal braking check
				var curr_h := Vector2(velocity.x, velocity.z)
				var targ_h := Vector2(target_horiz.x, target_horiz.z)
				var is_braking := curr_h.length() > 0.8 and curr_h.normalized().dot(targ_h.normalized()) < -0.2
				var accel_rate := braking_deceleration if is_braking else ground_acceleration

				velocity.x = move_toward(velocity.x, target_horiz.x, accel_rate * delta)
				velocity.z = move_toward(velocity.z, target_horiz.z, accel_rate * delta)

				# In strafe mode, character turns to face strafe/aim direction
				if is_third_person and is_strafing:
					var target_heading := atan2(-direction.x, -direction.z)
					rotation.y = lerp_angle(rotation.y, target_heading, delta * character_turn_speed)
			else:
				# Ground friction deceleration
				velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
				velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
		else:
			# Airborne momentum preservation with gentle air steering
			if direction != Vector3.ZERO:
				velocity.x = move_toward(velocity.x, target_horiz.x, air_acceleration * delta)
				velocity.z = move_toward(velocity.z, target_horiz.z, air_acceleration * delta)
			else:
				# Subtle air drag
				velocity.x = move_toward(velocity.x, 0.0, 1.2 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 1.2 * delta)

	move_and_slide()

	# Terrain floor safety clamp (when on dry land)
	if terrain_generator and not is_climbing and not is_on_rope and not is_swimming:
		if global_position.y < ground_h:
			global_position.y = ground_h
			if velocity.y < 0.0:
				velocity.y = 0.0

	# Procedural box man animations (Stage 2)
	if box_man_model:
		var horiz_vel := Vector3(velocity.x, velocity.y if (is_climbing or is_on_rope) else 0.0, velocity.z)
		box_man_model.update_animation(delta, horiz_vel, is_on_floor() and not is_swimming, is_holding_torch and not is_carrying_log, is_swimming, is_climbing, is_on_rope, velocity.y)

	# Smooth camera positioning and collision avoidance (with over-shoulder bow aiming zoom)
	var desired_cam_dist := target_cam_distance
	if equipment and equipment.is_aiming_bow:
		desired_cam_dist = 1.8 if is_third_person else 0.0
	current_cam_distance = lerpf(current_cam_distance, desired_cam_dist, delta * 12.0)
	_update_camera(delta)

	# Update interactable focus (CarryableLog prompt, HarvestableTree chop tracker & fall angle)
	_update_focused_interactables()

var _focused_log: Node = null
var _focused_tree: Node = null

func _update_focused_interactables() -> void:
	var hit_log: Node = null
	var hit_tree: Node = null

	if interact_raycast and interact_raycast.is_colliding():
		var col := interact_raycast.get_collider()
		if col:
			if col.is_in_group("carryable_log") and col.has_method("set_settler_focus"):
				hit_log = col
			elif col.is_in_group("harvestable_trees") or (col.has_method("chop") and col.has_method("set_settler_focus")):
				hit_tree = col

	# Proximity check for nearby trees within 4.8m ahead of settler
	if hit_tree == null and is_inside_tree():
		var trees := get_tree().get_nodes_in_group("harvestable_trees")
		var closest_d := 4.8
		var forward_h := -global_transform.basis.z
		forward_h.y = 0.0
		if forward_h.length_squared() > 0.01:
			forward_h = forward_h.normalized()
			for t in trees:
				if t is Node3D and is_instance_valid(t) and t.has_method("chop"):
					var to_tree: Vector3 = t.global_position - global_position
					var dy: float = absf(to_tree.y)
					to_tree.y = 0.0
					var d := to_tree.length()
					if dy < 3.5 and d < closest_d:
						if d < 2.5 or forward_h.dot(to_tree.normalized()) > 0.05:
							closest_d = d
							hit_tree = t

	# Manage log focus
	if _focused_log != hit_log:
		if _focused_log and is_instance_valid(_focused_log) and _focused_log.has_method("set_settler_focus"):
			_focused_log.set_settler_focus(null)
		_focused_log = hit_log
		if _focused_log and is_instance_valid(_focused_log):
			_focused_log.set_settler_focus(self)

	# Manage tree focus (shows 10-chop progress tracker and fall angle trajectory indicator)
	if _focused_tree != hit_tree:
		if _focused_tree and is_instance_valid(_focused_tree) and _focused_tree.has_method("set_settler_focus"):
			_focused_tree.set_settler_focus(null)
		_focused_tree = hit_tree
		if _focused_tree and is_instance_valid(_focused_tree):
			_focused_tree.set_settler_focus(self)
	elif _focused_tree and is_instance_valid(_focused_tree) and _focused_tree.has_method("set_settler_focus"):
		_focused_tree.set_settler_focus(self)

## Detects steep rocky cliff faces (>= 45° slope) ahead of settler
func _check_steep_cliff() -> Dictionary:
	var world_3d := get_world_3d()
	if not world_3d:
		return {}
	var space_state := world_3d.direct_space_state
	if not space_state:
		return {}

	var forward_dir := -climb_normal if is_climbing else -global_transform.basis.z
	var ray_origins := [
		global_position + Vector3(0.0, 1.05, 0.0), # Chest
		global_position + Vector3(0.0, 1.60, 0.0), # Head / reach
		global_position + Vector3(0.0, 0.40, 0.0)  # Knees
	]

	# 1. Multi-point forward raycast check within 1.35m
	for origin in ray_origins:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + forward_dir * 1.35)
		query.exclude = [get_rid()]
		var hit := space_state.intersect_ray(query)

		if not hit.is_empty():
			var norm: Vector3 = hit.normal
			var slope_angle := norm.angle_to(Vector3.UP)
			if slope_angle >= deg_to_rad(45.0):
				return {"hit": true, "normal": norm, "position": hit.position, "distance": (hit.position as Vector3).distance_to(origin)}

	# 2. Physics wall collision check
	if is_on_wall():
		var wall_n := get_wall_normal()
		if wall_n.angle_to(Vector3.UP) >= deg_to_rad(45.0):
			return {"hit": true, "normal": wall_n, "position": global_position - wall_n * 0.45, "distance": 0.45}

	# 3. Direct terrain slope sampling (for initial climb latching or when near terrain)
	if terrain_generator:
		var px := global_position.x
		var pz := global_position.z
		var h_center: float = float(terrain_generator.sample_height(px, pz))
		# Allow sampling when on ground or climbing steep contour
		if absf(global_position.y - h_center) < 2.5 or is_climbing:
			var step_dist: float = 0.75
			var h_fwd: float = float(terrain_generator.sample_height(px + forward_dir.x * step_dist, pz + forward_dir.z * step_dist))
			var rise: float = h_fwd - h_center
			var slope_deg: float = rad_to_deg(atan2(rise, step_dist))
			if slope_deg >= 45.0:
				var estimated_norm := Vector3(-forward_dir.x, 0.25, -forward_dir.z).normalized()
				return {"hit": true, "normal": estimated_norm, "position": global_position + forward_dir * 0.55, "distance": 0.55}

	return {}

## Places or throws an anchor rope on a cliff edge or rock face (Task 7)
func _handle_climbing_rope_tool() -> void:
	# If currently on rope, disengage
	if is_on_rope:
		is_on_rope = false
		active_rope = null
		return

	# If near an existing anchor, retrieve it
	var ropes := get_tree().get_nodes_in_group("climbing_rope")
	for r in ropes:
		if is_instance_valid(r) and r.has_method("get_top_position"):
			var top_p: Vector3 = r.get_top_position()
			if global_position.distance_to(top_p) < 2.5:
				r.retrieve_rope(self)
				return

	# Ensure player has rope in inventory
	if inventory:
		if inventory.get_count("climbing_rope") <= 0:
			inventory.add_resource("climbing_rope", 1)
		inventory.items["climbing_rope"] -= 1
		inventory.inventory_changed.emit(inventory.items)

	var scene_root := get_parent()
	if not scene_root and get_tree():
		scene_root = get_tree().current_scene if get_tree().current_scene else get_tree().root

	var world_3d := get_world_3d()
	if not world_3d:
		return
	var space_state := world_3d.direct_space_state

	var cam_fwd := -camera.global_transform.basis.z if camera else -global_transform.basis.z
	var anchor_pos := global_position
	var wall_norm := global_transform.basis.z

	# Raycast check forward / downward
	var ray_query := PhysicsRayQueryParameters3D.create(camera.global_position if camera else global_position + Vector3.UP * 1.5, (camera.global_position if camera else global_position) + cam_fwd * 20.0)
	ray_query.exclude = [get_rid()]
	var cam_hit := space_state.intersect_ray(ray_query)

	if not cam_hit.is_empty():
		anchor_pos = cam_hit.position + Vector3(0.0, 0.2, 0.0)
		wall_norm = cam_hit.normal
	else:
		# Place at edge ahead of settler
		anchor_pos = global_position + (-global_transform.basis.z * 1.2) + Vector3(0.0, 0.1, 0.0)
		wall_norm = global_transform.basis.z

	var rope_script = load("res://scripts/environment/climbing_rope.gd")
	if rope_script:
		var rope_inst: Node = rope_script.create_rope(anchor_pos, wall_norm, space_state)
		scene_root.add_child(rope_inst)

## Grabs hold of a hanging climbing rope for climbing or rappelling
func _grab_rope(rope: Node) -> void:
	if is_carrying_log:
		drop_log()
	is_on_rope = true
	active_rope = rope
	is_climbing = false
	is_swimming = false
	velocity = Vector3.ZERO

func _update_camera(delta: float) -> void:
	if not camera or not head:
		return

	# Smooth FOV zoom when aiming bow and dynamic widening during sprint
	var base_fov := 79.0 if is_sprinting else 75.0
	var target_fov := 52.0 if (equipment and equipment.is_aiming_bow) else base_fov
	camera.fov = lerpf(camera.fov, target_fov, delta * 10.0)

	if current_cam_distance < 0.3 or not is_third_person:
		# First-person view: aligned with character heading and pitch
		cam_yaw = rotation.y
		camera.global_position = head.global_position
		var fp_rot := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
		camera.global_basis = fp_rot
		if box_man_model:
			box_man_model.visible = false

		if interact_raycast:
			interact_raycast.global_transform = camera.global_transform
			interact_raycast.target_position = Vector3(0, 0, -5.0)
	else:
		# Third-person view: follow behind character back
		if box_man_model:
			box_man_model.visible = true

		# Smooth rotational follow behind settler
		var target_yaw := rotation.y
		cam_yaw = lerp_angle(cam_yaw, target_yaw, delta * cam_follow_yaw_speed)

		# Vertical elevation smoothing: damp sudden terrain steps
		var target_pivot_y := global_position.y + 1.45
		if _smoothed_pivot_y == 0.0:
			_smoothed_pivot_y = target_pivot_y
		else:
			_smoothed_pivot_y = lerpf(_smoothed_pivot_y, target_pivot_y, delta * cam_vertical_smooth_speed)

		var pivot_pos := Vector3(global_position.x, _smoothed_pivot_y, global_position.z)
		var cam_rot := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
		var is_aiming: bool = bool(equipment and equipment.get("is_aiming_bow"))
		var shoulder_x := 0.45 if is_aiming else 0.0
		var desired_offset := cam_rot * Vector3(shoulder_x, cam_height_offset, current_cam_distance)
		var desired_pos := pivot_pos + desired_offset

		# Raycast check against mountains/terrain/obstacles to prevent clipping
		var target_safe_dist := current_cam_distance
		var world_3d := get_world_3d()
		if world_3d and is_inside_tree():
			var space_state := world_3d.direct_space_state
			if space_state:
				var query := PhysicsRayQueryParameters3D.create(pivot_pos, desired_pos)
				query.exclude = [self.get_rid()]
				var hit := space_state.intersect_ray(query)

				if not hit.is_empty():
					var hit_dist: float = (hit.position - pivot_pos).length()
					target_safe_dist = maxf(0.45, hit_dist - 0.25)

		# Smooth occlusion distance adjustment (fast in, smooth out)
		var dist_speed := 22.0 if target_safe_dist < _current_safe_dist else 8.0
		_current_safe_dist = lerpf(_current_safe_dist, target_safe_dist, delta * dist_speed)

		var safe_ratio := _current_safe_dist / maxf(current_cam_distance, 0.01)
		var final_offset := cam_rot * Vector3(shoulder_x * safe_ratio, cam_height_offset * safe_ratio, _current_safe_dist)
		var final_cam_pos := pivot_pos + final_offset

		camera.global_position = final_cam_pos
		camera.global_basis = cam_rot

		if interact_raycast:
			interact_raycast.global_transform = camera.global_transform
			interact_raycast.target_position = Vector3(0, 0, -(current_cam_distance + 5.5))

	# Procedural camera trauma shake (non-linear quadratic falloff)
	if camera_trauma > 0.001:
		_trauma_timer += delta * 28.0
		camera_trauma = maxf(0.0, camera_trauma - delta * 1.6)
		var shake_factor := camera_trauma * camera_trauma
		var shake_offset := Vector3(
			sin(_trauma_timer * 1.1) * 0.05 * shake_factor,
			cos(_trauma_timer * 1.6) * 0.07 * shake_factor,
			sin(_trauma_timer * 2.1) * 0.03 * shake_factor
		)
		var shake_rot := Vector3(
			cos(_trauma_timer * 1.4) * deg_to_rad(2.2) * shake_factor,
			sin(_trauma_timer * 1.8) * deg_to_rad(1.8) * shake_factor,
			cos(_trauma_timer * 2.3) * deg_to_rad(3.0) * shake_factor
		)
		camera.global_position += shake_offset
		camera.global_basis = camera.global_basis * Basis.from_euler(shake_rot)

## Picks up a physical carryable log into arms
func pick_up_log(log_node: Node) -> void:
	if is_carrying_log:
		return
	if is_holding_torch or (equipment and equipment.current_slot == EquipmentManager.Slot.TORCH):
		toggle_torch()
	is_carrying_log = true
	carrying_state_changed.emit(true)

	if log_node and is_instance_valid(log_node):
		log_node.queue_free()

	if box_man_model:
		box_man_model.set_carrying_log(true)

## Drops the carried log on the ground in front of the settler
func drop_log() -> void:
	if not is_carrying_log:
		return
	is_carrying_log = false
	carrying_state_changed.emit(false)

	if box_man_model:
		box_man_model.set_carrying_log(false)

	# Spawn physical CarryableLog in front of settler
	var carryable_log_script = load("res://scripts/environment/carryable_log.gd")
	if carryable_log_script:
		var scene_root: Node = get_parent()
		if not scene_root and get_tree():
			scene_root = get_tree().current_scene if get_tree().current_scene else get_tree().root
		if scene_root:
			var log_inst: RigidBody3D = carryable_log_script.create_log()
			scene_root.add_child(log_inst)
			var forward_vec := -global_transform.basis.z
			var drop_pos := global_position + forward_vec * 1.35 + Vector3(0, 0.45, 0)
			log_inst.global_position = drop_pos
			log_inst.rotation.y = rotation.y + deg_to_rad(90.0)
			log_inst.linear_velocity = forward_vec * 1.5 + Vector3(0, -0.2, 0)

## Consumes carried log directly into building construction
func consume_carried_log() -> void:
	if not is_carrying_log:
		return
	is_carrying_log = false
	carrying_state_changed.emit(false)
	if box_man_model:
		box_man_model.set_carrying_log(false)

## Attempts to place the carried log into a nearby construction site slot
func _try_slot_carried_log_into_construction_site() -> bool:
	if not is_carrying_log:
		return false
	var sites: Array = []
	if is_inside_tree() and get_tree():
		sites = get_tree().get_nodes_in_group("construction_site")
	elif get_parent():
		for child in get_parent().get_children():
			if child.is_in_group("construction_site"):
				sites.append(child)

	var my_pos: Vector3 = global_position if is_inside_tree() else position
	var closest_site: Node = null
	var min_d := 5.0
	for s in sites:
		if s and is_instance_valid(s) and s.has_method("can_place_log"):
			if s.can_place_log(self):
				var s_node := s as Node3D
				var s_pos: Vector3 = s_node.global_position if (s_node and s_node.is_inside_tree()) else (s_node.position if s_node else Vector3.ZERO)
				var d: float = my_pos.distance_to(s_pos)
				if d < min_d:
					min_d = d
					closest_site = s
	if closest_site:
		return closest_site.place_carried_log(self)
	return false

func _perform_interaction() -> void:
	if is_carrying_log:
		if not _try_slot_carried_log_into_construction_site():
			drop_log()
		return

	# 0. Check for nearby hanging climbing rope within 2.2m (Task 7)
	var ropes := get_tree().get_nodes_in_group("climbing_rope")
	for r in ropes:
		if is_instance_valid(r) and r.has_method("get_closest_point"):
			var closest_p: Vector3 = r.get_closest_point(global_position)
			if global_position.distance_to(closest_p) < 2.0:
				_grab_rope(r)
				return

	# 1. Direct raycast interaction (crosshair target)
	if interact_raycast and interact_raycast.is_colliding():
		var target := interact_raycast.get_collider()
		if target:
			if target.has_method("chop"):
				target.chop(self)
				if box_man_model:
					box_man_model.trigger_chop()
				return
			elif target.has_method("on_interact"):
				target.on_interact(self)
				if box_man_model and target.is_in_group("harvestable_trees"):
					box_man_model.trigger_chop()
				return

	# 2. Forgiving proximity pickup: check for nearby carryable logs within 2.6m
	var logs := get_tree().get_nodes_in_group("carryable_log")
	var closest_log: Node3D = null
	var closest_dist: float = 2.6
	for l in logs:
		if l is Node3D and is_instance_valid(l):
			var dist := global_position.distance_to(l.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_log = l
	if closest_log:
		pick_up_log(closest_log)
		return

	# 3. Forgiving proximity interaction for Bog Iron Ore Deposits within 3.2m
	var bog_ores := get_tree().get_nodes_in_group("bog_ore_deposit")
	var closest_ore: Node = null
	var closest_ore_dist: float = 3.2
	for ore in bog_ores:
		if ore is Node3D and is_instance_valid(ore):
			var dist := global_position.distance_to(ore.global_position)
			if dist < closest_ore_dist:
				closest_ore_dist = dist
				closest_ore = ore
	if closest_ore and closest_ore.has_method("on_interact"):
		closest_ore.on_interact(self)
		return

	# 4. Tree chopping with [E] when focused or looking at a tree
	var tree_to_chop: Node = _get_target_or_focused_tree()
	if tree_to_chop and is_instance_valid(tree_to_chop) and tree_to_chop.has_method("chop"):
		_chop_tree(tree_to_chop)
		return

	# 5. Freshwater stream drinking & backpack reservoir refill
	if terrain_generator and not is_swimming and terrain_generator.is_freshwater_stream(global_position):
		survival_stats.drink_water(true)
		if equipment:
			equipment.refill_reservoir(100.0)
		return

	# 6. If holding Water Bottle / Drinking Horn (Slot 2), pressing [E] drinks from reservoir
	if equipment and int(equipment.get("current_slot")) == 2:
		equipment.drink_from_reservoir()

func _perform_attack_or_chop() -> void:
	if is_carrying_log:
		return

	if equipment:
		equipment.use_primary(interact_raycast, camera)
		return

	if box_man_model:
		box_man_model.trigger_chop()

	if interact_raycast and interact_raycast.is_colliding():
		var target := interact_raycast.get_collider()
		if target.has_method("take_damage"):
			target.take_damage(25.0, self)
			survival_stats.consume_stamina(12.0)
		elif target.has_method("on_interact"):
			target.on_interact(self)

func _get_target_or_focused_tree() -> Node:
	if interact_raycast and interact_raycast.is_colliding():
		var col := interact_raycast.get_collider()
		if col and (col.is_in_group("harvestable_trees") or col.has_method("chop")):
			var to_col: Vector3 = col.global_position - global_position
			to_col.y = 0.0
			if to_col.length() < 5.2:
				return col
	if _focused_tree and is_instance_valid(_focused_tree) and _focused_tree.has_method("chop"):
		var to_f: Vector3 = _focused_tree.global_position - global_position
		to_f.y = 0.0
		if to_f.length() < 5.2:
			return _focused_tree
	if is_inside_tree():
		var trees := get_tree().get_nodes_in_group("harvestable_trees")
		var closest: Node = null
		var min_d := 4.8
		var forward_h := -global_transform.basis.z
		forward_h.y = 0.0
		if forward_h.length_squared() > 0.01:
			forward_h = forward_h.normalized()
		for t in trees:
			if t is Node3D and is_instance_valid(t) and t.has_method("chop"):
				var to_t: Vector3 = t.global_position - global_position
				var dy: float = absf(to_t.y)
				to_t.y = 0.0
				var d := to_t.length()
				if dy < 3.5 and d < min_d:
					if d < 2.5 or (forward_h.length_squared() > 0.01 and forward_h.dot(to_t.normalized()) > 0.05):
						min_d = d
						closest = t
		return closest
	return null

func _chop_tree(target_tree: Node) -> void:
	if not target_tree or not is_instance_valid(target_tree) or not target_tree.has_method("chop"):
		return
	if equipment and equipment.attack_cooldown > 0.0:
		return
	if equipment:
		equipment.attack_cooldown = 0.40
		if equipment.current_slot != EquipmentManager.Slot.AXE:
			equipment.select_slot(EquipmentManager.Slot.AXE)
	if box_man_model:
		box_man_model.trigger_chop()
	target_tree.chop(self)

func _try_eat() -> void:
	if not inventory or not survival_stats:
		return

	if inventory.get_count("cooked_venison") > 0:
		inventory.consume_resources({"cooked_venison": 1})
		survival_stats.eat_food(48.0, true)
	elif inventory.get_count("cooked_beef") > 0:
		inventory.consume_resources({"cooked_beef": 1})
		survival_stats.eat_food(46.0, true)
	elif inventory.get_count("roasted_mutton") > 0:
		inventory.consume_resources({"roasted_mutton": 1})
		survival_stats.eat_food(42.0, true)
	elif inventory.get_count("cooked_meat") > 0:
		inventory.consume_resources({"cooked_meat": 1})
		survival_stats.eat_food(40.0, true)
	elif inventory.get_count("cooked_fish") > 0:
		inventory.consume_resources({"cooked_fish": 1})
		survival_stats.eat_food(36.0, true)
	elif inventory.get_count("roasted_hare") > 0:
		inventory.consume_resources({"roasted_hare": 1})
		survival_stats.eat_food(35.0, true)
	elif inventory.get_count("stockfish") > 0:
		inventory.consume_resources({"stockfish": 1})
		survival_stats.eat_food(32.0, true)
	elif inventory.get_count("rye_bread") > 0:
		inventory.consume_resources({"rye_bread": 1})
		survival_stats.eat_food(28.0, true)
	elif inventory.get_count("fresh_milk") > 0:
		inventory.consume_resources({"fresh_milk": 1})
		survival_stats.eat_food(18.0, true)
		survival_stats.drink_water(true)
	elif inventory.get_count("raw_venison") > 0:
		inventory.consume_resources({"raw_venison": 1})
		if survival_stats.is_near_fire:
			survival_stats.eat_food(45.0, true)
		else:
			survival_stats.eat_food(20.0, false)
	elif inventory.get_count("raw_beef") > 0:
		inventory.consume_resources({"raw_beef": 1})
		if survival_stats.is_near_fire:
			survival_stats.eat_food(44.0, true)
		else:
			survival_stats.eat_food(19.0, false)
	elif inventory.get_count("raw_hare") > 0:
		inventory.consume_resources({"raw_hare": 1})
		if survival_stats.is_near_fire:
			survival_stats.eat_food(35.0, true)
		else:
			survival_stats.eat_food(16.0, false)
	elif inventory.get_count("raw_mutton") > 0:
		inventory.consume_resources({"raw_mutton": 1})
		if survival_stats.is_near_fire:
			survival_stats.eat_food(38.0, true)
		else:
			survival_stats.eat_food(18.0, false)

func _place_campfire() -> void:
	if not inventory:
		return

	var has_stones: bool = int(inventory.get_count("stone")) >= 3
	var has_wood: bool = int(inventory.get_count("firewood")) >= 2 or int(inventory.get_count("timber_log")) >= 1

	if not (has_stones and has_wood):
		var hud_bar = get_tree().get_first_node_in_group("hud_building_bar")
		if hud_bar and hud_bar.has_method("_show_placement_error"):
			hud_bar._show_placement_error("Trenger 3 stein og 1 tømmer (eller 2 ved) for å bygge bål [K]!")
		return

	# Consume placement cost
	inventory.consume_resources({"stone": 3})
	if inventory.get_count("firewood") >= 2:
		inventory.consume_resources({"firewood": 2})
	else:
		inventory.consume_resources({"timber_log": 1})

	# Calculate ground position 2.2m ahead of settler
	var forward := -global_transform.basis.z.normalized()
	forward.y = 0.0
	var place_pos := global_position + forward * 2.2
	if terrain_generator:
		place_pos.y = terrain_generator.sample_height(place_pos.x, place_pos.z)

	var campfire_script = load("res://scripts/survival/campfire_interactable.gd")
	if campfire_script:
		var cf: Node3D = campfire_script.new()
		var scene_root := get_parent() if get_parent() else get_tree().current_scene
		scene_root.add_child(cf)
		cf.global_position = place_pos
