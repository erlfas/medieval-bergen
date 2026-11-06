class_name SettlerController
extends CharacterBody3D

## First-person settler controller with survival interactions:
## - Chopping trees
## - Drinking from freshwater mountain streams
## - Brandishing pine-tar torch [F] (emits light, warms player, repels wolves)
## - Hunting deer and defending against wolves
## - Piece-by-piece building placement

@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_raycast: RayCast3D = $Head/InteractRayCast
@onready var survival_stats: SurvivalStats = $SurvivalStats
@onready var inventory: InventoryManager = $InventoryManager
@onready var player_builder: PlayerBuilder = $PlayerBuilder

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var is_holding_torch: bool = false
var torch_light: OmniLight3D
var terrain_generator: BergenTerrainGenerator

func _ready() -> void:
	add_to_group("settler")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	terrain_generator = get_tree().get_first_node_in_group("terrain_generator") as BergenTerrainGenerator
	_create_torch_light()
	if terrain_generator:
		var ground_h := terrain_generator.sample_height(global_position.x, global_position.z)
		global_position.y = maxf(global_position.y, ground_h + 0.1)

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
		head.rotation.x = clampf(head.rotation.x, -deg_to_rad(85), deg_to_rad(85))

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

	# Check terrain freshwater stream drinking zone
	if terrain_generator:
		var near_stream := terrain_generator.is_freshwater_stream(global_position)
		if near_stream and Input.is_action_just_pressed("interact"):
			survival_stats.drink_water(true)

func _perform_interaction() -> void:
	if interact_raycast and interact_raycast.is_colliding():
		var target := interact_raycast.get_collider()
		if target.has_method("on_interact"):
			target.on_interact(self)

func _perform_attack_or_chop() -> void:
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
