class_name SettlerController
extends CharacterBody3D

## Settler controller for Medieval Bergen 1360:
## - Controllable gray box man with head, torso, animated arms/hands, and legs/boots
## - Third-person / First-person camera toggle [V] and mouse wheel zoom
## - Survival interactions: tree chopping, freshwater drinking, wolf defense, hunting
## - Pine-tar torch [F] with warm light and wolf deterrence
## - Piece-by-piece modular construction system [B]

@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025

@export_group("Camera View")
@export var is_third_person: bool = true
@export var target_cam_distance: float = 3.2
@export var cam_height_offset: float = 0.35

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_raycast: RayCast3D = $Head/InteractRayCast
@onready var survival_stats: SurvivalStats = $SurvivalStats
@onready var inventory: InventoryManager = $InventoryManager
@onready var player_builder: PlayerBuilder = $PlayerBuilder

var box_man_model: BoxManModel
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var is_holding_torch: bool = false
var torch_light: OmniLight3D
var terrain_generator: BergenTerrainGenerator
var current_cam_distance: float = 3.2

func _ready() -> void:
	add_to_group("settler")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	terrain_generator = get_tree().get_first_node_in_group("terrain_generator") as BergenTerrainGenerator

	_ensure_box_man_model()
	_create_torch_light()

	# Snap settler vertically to terrain surface
	if terrain_generator:
		var ground_h := terrain_generator.sample_height(global_position.x, global_position.z)
		global_position.y = maxf(global_position.y, ground_h + 0.1)

	current_cam_distance = target_cam_distance if is_third_person else 0.0
	_update_camera(0.0)

func _ensure_box_man_model() -> void:
	box_man_model = get_node_or_null("BoxManModel") as BoxManModel
	if box_man_model == null:
		var script_model = load("res://scripts/player/box_man_model.gd")
		box_man_model = Node3D.new()
		box_man_model.name = "BoxManModel"
		box_man_model.set_script(script_model)
		add_child(box_man_model)

func _create_torch_light() -> void:
	torch_light = OmniLight3D.new()
	torch_light.name = "TorchLight"
	torch_light.light_color = Color(1.0, 0.65, 0.28) # Warm fire glow
	torch_light.light_energy = 1.4
	torch_light.omni_range = 14.0
	torch_light.shadow_enabled = true
	torch_light.visible = false
	head.add_child(torch_light)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -deg_to_rad(80), deg_to_rad(80))

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

	# Interaction Key (E)
	if event.is_action_pressed("interact"):
		_perform_interaction()

	# Toggle Torch [F]
	if event.is_action_pressed("toggle_torch"):
		toggle_torch()

	# Attack / Action (Left Click when NOT in build mode)
	if event.is_action_pressed("place_build_piece") and (not player_builder or not player_builder.is_build_mode):
		_perform_attack_or_chop()

	# Quick Eat / Roast [H]
	if event.is_action_pressed("eat_food"):
		_try_eat()

func toggle_torch() -> void:
	is_holding_torch = not is_holding_torch
	if torch_light:
		torch_light.visible = is_holding_torch

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if survival_stats.consume_stamina(12.0):
			velocity.y = jump_velocity

	# Sprinting
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and survival_stats.stamina > 5.0
	var speed := sprint_speed if is_sprinting else walk_speed

	if is_sprinting:
		survival_stats.consume_stamina(10.0 * delta)

	# Movement direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

	# Terrain floor safety clamp to guarantee the settler never falls through the heightmap
	if terrain_generator:
		var ground_h := terrain_generator.sample_height(global_position.x, global_position.z)
		if global_position.y < ground_h:
			global_position.y = ground_h
			if velocity.y < 0.0:
				velocity.y = 0.0

	# Procedural box man animations (swing limbs, breathing, chopping)
	if box_man_model:
		var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
		box_man_model.update_animation(delta, horiz_vel, is_on_floor(), is_holding_torch)

	# Smooth camera positioning
	current_cam_distance = lerpf(current_cam_distance, target_cam_distance, delta * 10.0)
	_update_camera(delta)

	# Check terrain freshwater stream drinking zone
	if terrain_generator:
		var near_stream := terrain_generator.is_freshwater_stream(global_position)
		if near_stream and Input.is_action_just_pressed("interact"):
			survival_stats.drink_water(true)

func _update_camera(_delta: float) -> void:
	if not camera or not head:
		return

	if current_cam_distance < 0.3:
		# First-person view
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		if box_man_model:
			box_man_model.visible = false
	else:
		# Third-person view: position camera behind the settler
		if box_man_model:
			box_man_model.visible = true

		var desired_pos := Vector3(0.0, cam_height_offset, current_cam_distance)
		var from_pos := head.global_position
		var to_pos := head.to_global(desired_pos)

		# Raycast check to prevent camera from clipping inside mountains/obstacles
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
		query.exclude = [self.get_rid()]
		var hit := space_state.intersect_ray(query)

		if not hit.is_empty():
			var hit_local := head.to_local(hit.position)
			var safe_dist := maxf(0.4, hit_local.length() - 0.25)
			camera.position = Vector3(0.0, cam_height_offset * (safe_dist / current_cam_distance), safe_dist)
		else:
			camera.position = desired_pos

		camera.rotation = Vector3(deg_to_rad(-5.0), 0.0, 0.0)

func _perform_interaction() -> void:
	if interact_raycast and interact_raycast.is_colliding():
		var target := interact_raycast.get_collider()
		if target.has_method("on_interact"):
			target.on_interact(self)

func _perform_attack_or_chop() -> void:
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
