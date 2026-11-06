class_name FarmerAI
extends CharacterBody3D

## Medieval Bergen Farmer NPC AI
## - Inhabits the 1360 farmsteads (Sandviken, Hinterland, Southern Valley).
## - Wears authentic medieval wool tunics with leather belt and boots.
## - Performs daily farm chore routines:
##   * Tending garden beds (cabbage, turnips, barley)
##   * Chopping firewood at chopping block / woodpile
##   * Carrying hay bundles between stabbur and animal pastures
##   * Warming hands by the årestue central hearth
## - Responsive to daytime/night cycle and interactions from settler.

enum ChoreState {
	WALKING_TO_CHORE,
	TENDING_CROPS,
	CHOPPING_WOOD,
	CARRYING_HAY,
	WARMING_HEARTH,
	TALKING
}

@export var farmer_name: String = "Bonde"
@export var walk_speed: float = 2.4
@export var chore_state: ChoreState = ChoreState.TENDING_CROPS

# Chore waypoints (assigned by FarmsteadGenerator)
@export var crop_pos: Vector3 = Vector3.ZERO
@export var wood_pos: Vector3 = Vector3.ZERO
@export var hay_pos: Vector3 = Vector3.ZERO
@export var hearth_pos: Vector3 = Vector3.ZERO
@export var stabbur_pos: Vector3 = Vector3.ZERO

# Appearance colors (medieval wool tunics)
@export var tunic_color: Color = Color(0.45, 0.32, 0.22) # Russet wool
@export var hair_cap_color: Color = Color(0.30, 0.25, 0.22)

var current_target_pos: Vector3 = Vector3.ZERO
var target_chore_after_walk: ChoreState = ChoreState.TENDING_CROPS
var chore_timer: float = 0.0
var chop_cooldown: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var box_man_model: BoxManModel
var hay_bundle_mesh: MeshInstance3D
var time_manager: Node

var chore_cycle: Array[ChoreState] = [
	ChoreState.TENDING_CROPS,
	ChoreState.CHOPPING_WOOD,
	ChoreState.CARRYING_HAY,
	ChoreState.WARMING_HEARTH
]
var chore_cycle_index: int = 0

const GREETINGS: Array[String] = [
	"God dag, nabo! The barley is growing sturdy on this slope.",
	"Keep a lit torch if you wander the upper crags—the mountain wolves smell fear.",
	"Villsau fleece makes the warmest vadmål tunics in Bergen.",
	"The åre fire is burning warm inside. Rest your feet a moment.",
	"Turnips and cabbage are hardy against the salt wind from the fjord."
]

func _ready() -> void:
	add_to_group("npc")
	add_to_group("farmer")
	if get_tree():
		time_manager = get_tree().get_first_node_in_group("time_manager")

	_setup_box_man_model()
	_setup_hay_bundle()

	# Stagger initial chore timers so farmers aren't doing the exact same thing simultaneously
	chore_timer = randf_range(6.0, 16.0)
	chore_cycle_index = randi() % chore_cycle.size()
	target_chore_after_walk = chore_cycle[chore_cycle_index]
	_start_next_chore()

func _setup_box_man_model() -> void:
	box_man_model = get_node_or_null("BoxManModel") as BoxManModel
	if box_man_model == null:
		var model_script = load("res://scripts/player/box_man_model.gd")
		box_man_model = BoxManModel.new()
		box_man_model.name = "BoxManModel"
		box_man_model.tunic_color = tunic_color
		add_child(box_man_model)

	# Ensure collision shape exists
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
		col.shape = cap
		col.position.y = 0.9
		add_child(col)

func _setup_hay_bundle() -> void:
	# Visual golden straw hay bundle attached when carrying hay
	hay_bundle_mesh = MeshInstance3D.new()
	var box_hay := BoxMesh.new()
	box_hay.size = Vector3(0.5, 0.4, 0.7)
	hay_bundle_mesh.mesh = box_hay
	var mat_hay := StandardMaterial3D.new()
	mat_hay.albedo_color = Color(0.78, 0.68, 0.35) # Dried golden meadow hay
	mat_hay.roughness = 0.95
	hay_bundle_mesh.material_override = mat_hay
	hay_bundle_mesh.position = Vector3(0, 1.15, -0.45)
	hay_bundle_mesh.visible = false
	add_child(hay_bundle_mesh)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	chore_timer -= delta
	chop_cooldown -= delta

	# Check night / severe cold: seek shelter by the årestue hearth
	if time_manager and time_manager.get("is_night") == true:
		if chore_state != ChoreState.WARMING_HEARTH and chore_state != ChoreState.WALKING_TO_CHORE:
			_walk_to(hearth_pos, ChoreState.WARMING_HEARTH)

	match chore_state:
		ChoreState.WALKING_TO_CHORE:
			_process_walk_to_chore(delta)

		ChoreState.TENDING_CROPS:
			_process_tending_crops(delta)

		ChoreState.CHOPPING_WOOD:
			_process_chopping_wood(delta)

		ChoreState.CARRYING_HAY:
			_process_carrying_hay(delta)

		ChoreState.WARMING_HEARTH:
			_process_warming_hearth(delta)

		ChoreState.TALKING:
			velocity.x = move_toward(velocity.x, 0.0, 1.5)
			velocity.z = move_toward(velocity.z, 0.0, 1.5)
			if chore_timer <= 0.0:
				_advance_chore_cycle()

	if box_man_model:
		var horiz_vel := Vector3(velocity.x, 0, velocity.z)
		var is_carrying := (chore_state == ChoreState.CARRYING_HAY)
		if hay_bundle_mesh:
			hay_bundle_mesh.visible = is_carrying
		box_man_model.set_carrying_log(is_carrying)
		box_man_model.update_animation(delta, horiz_vel, is_on_floor(), false)

	move_and_slide()

func _walk_to(dest: Vector3, next_chore: ChoreState) -> void:
	if dest == Vector3.ZERO:
		dest = global_position
	current_target_pos = dest
	target_chore_after_walk = next_chore
	chore_state = ChoreState.WALKING_TO_CHORE

func _process_walk_to_chore(delta: float) -> void:
	var dir := (current_target_pos - global_position)
	dir.y = 0.0
	var dist := dir.length()

	if dist > 0.8:
		dir = dir.normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		var target_rot := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * 6.0)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		chore_state = target_chore_after_walk
		chore_timer = randf_range(12.0, 22.0)

func _process_tending_crops(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1.0)
	velocity.z = move_toward(velocity.z, 0.0, 1.0)

	if chore_timer <= 0.0:
		_advance_chore_cycle()

func _process_chopping_wood(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1.0)
	velocity.z = move_toward(velocity.z, 0.0, 1.0)

	if chop_cooldown <= 0.0 and box_man_model:
		box_man_model.trigger_chop()
		chop_cooldown = randf_range(1.2, 2.0)

	if chore_timer <= 0.0:
		_advance_chore_cycle()

func _process_carrying_hay(delta: float) -> void:
	# Farmer shuttles hay from stabbur / hayrick to animal pen
	var dir := (current_target_pos - global_position)
	dir.y = 0.0
	var dist := dir.length()

	if dist > 0.8:
		dir = dir.normalized()
		velocity.x = dir.x * walk_speed * 0.85
		velocity.z = dir.z * walk_speed * 0.85
		var target_rot := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * 5.0)
	else:
		# Toggle target between hay storage and animal feeder
		if current_target_pos == hay_pos and stabbur_pos != Vector3.ZERO:
			current_target_pos = stabbur_pos
		else:
			current_target_pos = hay_pos

	if chore_timer <= 0.0:
		_advance_chore_cycle()

func _process_warming_hearth(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1.0)
	velocity.z = move_toward(velocity.z, 0.0, 1.0)

	if chore_timer <= 0.0:
		_advance_chore_cycle()

func _advance_chore_cycle() -> void:
	chore_cycle_index = (chore_cycle_index + 1) % chore_cycle.size()
	_start_next_chore()

func _start_next_chore() -> void:
	var next := chore_cycle[chore_cycle_index]
	var target_pos := Vector3.ZERO

	match next:
		ChoreState.TENDING_CROPS:
			target_pos = crop_pos if crop_pos != Vector3.ZERO else global_position
		ChoreState.CHOPPING_WOOD:
			target_pos = wood_pos if wood_pos != Vector3.ZERO else global_position
		ChoreState.CARRYING_HAY:
			target_pos = hay_pos if hay_pos != Vector3.ZERO else global_position
		ChoreState.WARMING_HEARTH:
			target_pos = hearth_pos if hearth_pos != Vector3.ZERO else global_position

	_walk_to(target_pos, next)

func on_interact(actor: Node) -> void:
	chore_state = ChoreState.TALKING
	chore_timer = 4.0

	# Turn to face settler
	if actor is Node3D:
		var dir: Vector3 = ((actor as Node3D).global_position - global_position).normalized()
		dir.y = 0.0
		if dir.length() > 0.1:
			rotation.y = atan2(-dir.x, -dir.z)

	# If player has SurvivalStats and is starving, farmer gives fresh turnip/bread!
	if actor and actor.has_node("SurvivalStats"):
		var stats: SurvivalStats = actor.get_node("SurvivalStats")
		if stats.hunger < 35.0:
			stats.eat_food(25.0, true)

	# Give settler a greeting
	var msg: String = GREETINGS[randi() % GREETINGS.size()]
	print("[%s]: %s" % [farmer_name, msg])
