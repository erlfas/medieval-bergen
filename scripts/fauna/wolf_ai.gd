class_name WolfAI
extends CharacterBody3D

## Wolf AI for Medieval Bergen:
## - Roams the deep woods and mountain ridges.
## - Hunts the settler in packs or solo.
## - Critical survival mechanic: AFRAID OF FIRE (retreats if near campfires, hearths, or lit torches).
## - Can be fought off and hunted for wolf pelts and bones.

enum State { PATROL, STALK, ATTACK, FLEE_FIRE, DEAD }

@export var current_state: State = State.PATROL
@export var patrol_speed: float = 3.0
@export var chase_speed: float = 6.5
@export var detection_radius: float = 24.0
@export var attack_radius: float = 2.2
@export var fire_fear_radius: float = 9.0
@export var damage: float = 16.0
@export var health: float = 40.0
@export var pelt_yield: int = 1

var player_target: CharacterBody3D
var fire_source_position: Vector3 = Vector3.ZERO
var has_fire_threat: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var attack_cooldown: float = 0.0

func _ready() -> void:
	player_target = get_tree().get_first_node_in_group("settler") as CharacterBody3D

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if current_state == State.DEAD:
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)

	# Check for fire sources (settler holding torch or nearby hearth)
	_scan_for_fire()

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.STALK:
			_process_stalk(delta)
		State.ATTACK:
			_process_attack(delta)
		State.FLEE_FIRE:
			_process_flee(delta)

	move_and_slide()

func _scan_for_fire() -> void:
	if player_target:
		# Check if player has lit torch equipped
		var player_has_torch: bool = player_target.get("is_holding_torch") == true
		var dist_to_player := global_position.distance_to(player_target.global_position)

		if player_has_torch and dist_to_player < fire_fear_radius:
			detect_fire(player_target.global_position)
			return

	# Check for nearby lit hearths/campfires
	var hearths := get_tree().get_nodes_in_group("hearth")
	for h in hearths:
		if h is Node3D and global_position.distance_to(h.global_position) < fire_fear_radius:
			detect_fire(h.global_position)
			return

func detect_fire(source_pos: Vector3) -> void:
	fire_source_position = source_pos
	has_fire_threat = true
	current_state = State.FLEE_FIRE

func _process_patrol(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1.0)
	velocity.z = move_toward(velocity.z, 0.0, 1.0)

	if player_target and global_position.distance_to(player_target.global_position) < detection_radius:
		current_state = State.STALK

func _process_stalk(_delta: float) -> void:
	if not player_target:
		current_state = State.PATROL
		return

	if has_fire_threat:
		current_state = State.FLEE_FIRE
		return

	var dist := global_position.distance_to(player_target.global_position)
	if dist <= attack_radius:
		current_state = State.ATTACK
	elif dist > detection_radius * 1.5:
		current_state = State.PATROL
	else:
		# Move towards settler
		var dir := (player_target.global_position - global_position).normalized()
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
		if dir.length() > 0.1:
			look_at(global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)

func _process_attack(_delta: float) -> void:
	if has_fire_threat:
		current_state = State.FLEE_FIRE
		return

	if not player_target:
		current_state = State.PATROL
		return

	var dist := global_position.distance_to(player_target.global_position)
	if dist > attack_radius * 1.4:
		current_state = State.STALK
		return

	# Bite attack
	if attack_cooldown <= 0.0 and player_target.has_node("SurvivalStats"):
		var stats: SurvivalStats = player_target.get_node("SurvivalStats")
		stats.health = maxf(0.0, stats.health - damage)
		attack_cooldown = 1.2 # Time between bites

func _process_flee(_delta: float) -> void:
	var flee_dir := (global_position - fire_source_position).normalized()
	velocity.x = flee_dir.x * chase_speed * 1.3
	velocity.z = flee_dir.z * chase_speed * 1.3
	if flee_dir.length() > 0.1:
		look_at(global_position + Vector3(flee_dir.x, 0, flee_dir.z), Vector3.UP)

	if global_position.distance_to(fire_source_position) > fire_fear_radius * 2.2:
		has_fire_threat = false
		current_state = State.PATROL

func take_damage(amount: float, attacker: Node) -> void:
	if current_state == State.DEAD:
		return

	health -= amount
	if health <= 0.0:
		die(attacker)
	else:
		current_state = State.STALK

func die(killer: Node) -> void:
	current_state = State.DEAD
	velocity = Vector3.ZERO
	rotation.z = deg_to_rad(90.0)

	if killer and killer.has_node("InventoryManager"):
		var inv: InventoryManager = killer.get_node("InventoryManager")
		inv.add_resource("wolf_pelt", pelt_yield)

	get_tree().create_timer(30.0).timeout.connect(queue_free)

func on_interact(actor: Node) -> void:
	if current_state != State.DEAD:
		take_damage(25.0, actor)
