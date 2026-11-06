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

@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025

@export_group("Camera View")
@export var is_third_person: bool = true
@export var target_cam_distance: float = 3.2
@export var cam_height_offset: float = 0.45
@export var cam_follow_damping: float = 2.4     ## Gentle follow damping when turning
@export var character_turn_speed: float = 11.0   ## Smooth character body turning

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_raycast: RayCast3D = $Head/InteractRayCast
@onready var survival_stats: SurvivalStats = $SurvivalStats
@onready var inventory: InventoryManager = $InventoryManager
@onready var player_builder: PlayerBuilder = $PlayerBuilder

var box_man_model: Node3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var is_holding_torch: bool = false
var is_carrying_log: bool = false
var torch_light: OmniLight3D
var terrain_generator: BergenTerrainGenerator

var cam_yaw: float = 0.0
var cam_pitch: float = deg_to_rad(-8.0)
var current_cam_distance: float = 3.2
var mouse_orbit_timer: float = 0.0

func _enter_tree() -> void:
	_ensure_box_man_model()

func _ready() -> void:
	add_to_group("settler")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_tree():
		terrain_generator = get_tree().get_first_node_in_group("terrain_generator") as BergenTerrainGenerator

	_ensure_box_man_model()
	_create_torch_light()

	# Snap settler vertically to terrain surface
	if terrain_generator:
		var ground_h := terrain_generator.sample_height(global_position.x, global_position.z)
		global_position.y = maxf(global_position.y, ground_h + 0.1)

	# Configure camera and raycast to be top_level for smooth independent orbit & follow
	if camera:
		camera.top_level = true
	if interact_raycast:
		interact_raycast.top_level = true

	current_cam_distance = target_cam_distance if is_third_person else 0.0
	cam_yaw = rotation.y
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

func _create_torch_light() -> void:
	torch_light = OmniLight3D.new()
	torch_light.name = "TorchLight"
	torch_light.light_color = Color(1.0, 0.65, 0.28) # Warm fire glow
	torch_light.light_energy = 1.4
	torch_light.omni_range = 14.0
	torch_light.shadow_enabled = true
	torch_light.visible = false
	head.add_child(torch_light)

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
			var gh := terrain_generator.sample_height(target_pos.x, target_pos.z)
			target_pos.y = gh + 0.3
		log_inst.global_position = target_pos
		log_inst.rotation.y = randf_range(0.0, TAU)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse Look Orbit
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * mouse_sensitivity
		cam_pitch -= event.relative.y * mouse_sensitivity
		cam_pitch = clampf(cam_pitch, deg_to_rad(-65.0), deg_to_rad(70.0))
		mouse_orbit_timer = 0.55 # Active user orbit overrides auto-alignment

		if not is_third_person:
			rotation.y = cam_yaw
			head.rotation.x = cam_pitch

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

	# Interaction Key (E) - pick up or drop log, or interact with objects
	if event.is_action_pressed("interact"):
		if is_carrying_log:
			drop_log()
		else:
			_perform_interaction()

	# Toggle Torch [F]
	if event.is_action_pressed("toggle_torch"):
		toggle_torch()

	# Attack / Chop (Left Click when NOT in build mode and NOT carrying log)
	if event.is_action_pressed("place_build_piece") and (not player_builder or not player_builder.is_build_mode):
		if not is_carrying_log:
			_perform_attack_or_chop()

	# Quick Eat / Roast [H]
	if event.is_action_pressed("eat_food"):
		_try_eat()

func toggle_torch() -> void:
	if is_carrying_log:
		return # Cannot hold torch while carrying a log
	is_holding_torch = not is_holding_torch
	if torch_light:
		torch_light.visible = is_holding_torch

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		var stamina_cost := 16.0 if is_carrying_log else 12.0
		if survival_stats.consume_stamina(stamina_cost):
			velocity.y = jump_velocity

	# Sprinting (carrying a log prevents high-speed sprinting)
	var can_sprint := not is_carrying_log and survival_stats.stamina > 5.0
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and can_sprint
	var base_speed := walk_speed * (0.85 if is_carrying_log else 1.0)
	var speed := sprint_speed if is_sprinting else base_speed

	if is_sprinting:
		survival_stats.consume_stamina(10.0 * delta)

	# Movement direction relative to camera facing direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var cam_forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var cam_right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var direction := (cam_right * input_dir.x - cam_forward * input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

		# Smooth character rotation towards movement direction in third-person
		if is_third_person:
			var target_heading := atan2(-direction.x, -direction.z)
			rotation.y = lerp_angle(rotation.y, target_heading, delta * character_turn_speed)

			# Gentle camera damping follow: smoothly align behind the character when turning & walking
			if mouse_orbit_timer > 0.0:
				mouse_orbit_timer -= delta
			else:
				cam_yaw = lerp_angle(cam_yaw, rotation.y, delta * cam_follow_damping)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		if mouse_orbit_timer > 0.0:
			mouse_orbit_timer -= delta

	move_and_slide()

	# Terrain floor safety clamp to guarantee the settler never falls through the heightmap
	if terrain_generator:
		var ground_h := terrain_generator.sample_height(global_position.x, global_position.z)
		if global_position.y < ground_h:
			global_position.y = ground_h
			if velocity.y < 0.0:
				velocity.y = 0.0

	# Procedural box man animations (swing limbs, breathing, chopping, carrying log)
	if box_man_model:
		var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
		box_man_model.update_animation(delta, horiz_vel, is_on_floor(), is_holding_torch and not is_carrying_log)

	# Smooth camera positioning and collision avoidance
	current_cam_distance = lerpf(current_cam_distance, target_cam_distance, delta * 10.0)
	_update_camera(delta)

	# Check terrain freshwater stream drinking zone
	if terrain_generator:
		var near_stream := terrain_generator.is_freshwater_stream(global_position)
		if near_stream and Input.is_action_just_pressed("interact") and not is_carrying_log:
			survival_stats.drink_water(true)

func _update_camera(_delta: float) -> void:
	if not camera or not head:
		return

	if current_cam_distance < 0.3 or not is_third_person:
		# First-person view
		camera.global_position = head.global_position
		var fp_rot := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
		camera.global_basis = fp_rot
		if box_man_model:
			box_man_model.visible = false

		if interact_raycast:
			interact_raycast.global_transform = camera.global_transform
			interact_raycast.target_position = Vector3(0, 0, -3.5)
	else:
		# Third-person view: smooth orbit & spring follow behind character with collision safety
		if box_man_model:
			box_man_model.visible = true

		var pivot_pos := global_position + Vector3(0.0, 1.45, 0.0)
		var cam_rot := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
		var desired_offset := cam_rot * Vector3(0.0, cam_height_offset, current_cam_distance)
		var desired_pos := pivot_pos + desired_offset

		var final_cam_pos := desired_pos

		# Raycast check against mountains/terrain/obstacles to prevent clipping
		var world_3d := get_world_3d()
		if world_3d and is_inside_tree():
			var space_state := world_3d.direct_space_state
			if space_state:
				var query := PhysicsRayQueryParameters3D.create(pivot_pos, desired_pos)
				query.exclude = [self.get_rid()]
				var hit := space_state.intersect_ray(query)

				if not hit.is_empty():
					var hit_dist: float = (hit.position - pivot_pos).length()
					var safe_dist := maxf(0.45, hit_dist - 0.25)
					var safe_offset := cam_rot * Vector3(0.0, cam_height_offset * (safe_dist / maxf(current_cam_distance, 0.01)), safe_dist)
					final_cam_pos = pivot_pos + safe_offset

		camera.global_position = final_cam_pos
		camera.global_basis = cam_rot

		if interact_raycast:
			interact_raycast.global_transform = camera.global_transform
			interact_raycast.target_position = Vector3(0, 0, -4.5)

## Picks up a physical carryable log into arms
func pick_up_log(log_node: Node) -> void:
	if is_carrying_log:
		return
	is_carrying_log = true
	carrying_state_changed.emit(true)
	if is_holding_torch:
		toggle_torch()

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

func _perform_interaction() -> void:
	if is_carrying_log:
		drop_log()
		return

	# 1. Direct raycast interaction (crosshair target)
	if interact_raycast and interact_raycast.is_colliding():
		var target := interact_raycast.get_collider()
		if target and target.has_method("on_interact"):
			target.on_interact(self)
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

func _perform_attack_or_chop() -> void:
	if is_carrying_log:
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

func _try_eat() -> void:
	if not inventory or not survival_stats:
		return

	if inventory.get_count("cooked_meat") > 0:
		inventory.items["cooked_meat"] -= 1
		survival_stats.eat_food(40.0, true)
	elif inventory.get_count("raw_venison") > 0:
		# If near fire, roast it!
		if survival_stats.is_near_fire:
			inventory.items["raw_venison"] -= 1
			survival_stats.eat_food(45.0, true)
		else:
			# Eat raw (risk food poisoning)
			inventory.items["raw_venison"] -= 1
			survival_stats.eat_food(20.0, false)
