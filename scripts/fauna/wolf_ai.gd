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
@export var min_mountain_altitude: float = 80.0
@export var mountain_home: Vector3 = Vector3(320.0, 110.0, 200.0)

var player_target: CharacterBody3D
var fire_source_position: Vector3 = Vector3.ZERO
var has_fire_threat: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var attack_cooldown: float = 0.0
var patrol_timer: float = 0.0
var wander_target: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("wolf")
	add_to_group("fauna")
	if mountain_home == Vector3(320.0, 110.0, 200.0) and global_position.y > 50.0:
		mountain_home = global_position
	if get_tree():
		player_target = get_tree().get_first_node_in_group("settler") as CharacterBody3D
	_pick_mountain_patrol_target()
	if get_node_or_null("VisualModel") == null and get_node_or_null("CollisionShape3D") == null:
		_build_wolf_mesh()

func _build_wolf_mesh() -> void:
	var visual := Node3D.new()
	visual.name = "VisualModel"
	add_child(visual)

	var mat_wolf := StandardMaterial3D.new()
	mat_wolf.albedo_color = Color(0.32, 0.33, 0.35) # Scandinavian timber wolf grey
	mat_wolf.roughness = 0.85

	var mi_body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.2
	mi_body.mesh = cap
	mi_body.rotation.x = deg_to_rad(90.0)
	mi_body.position.y = 0.65
	mi_body.material_override = mat_wolf
	visual.add_child(mi_body)

	var mi_head := MeshInstance3D.new()
	var box_head := BoxMesh.new()
	box_head.size = Vector3(0.24, 0.28, 0.4)
	mi_head.mesh = box_head
	mi_head.position = Vector3(0, 0.9, -0.6)
	mi_head.material_override = mat_wolf
	visual.add_child(mi_head)

	var col := CollisionShape3D.new()
	var cap_col := CapsuleShape3D.new()
	cap_col.radius = 0.4
	cap_col.height = 1.2
	col.shape = cap_col
	col.position.y = 0.65
	add_child(col)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if current_state == State.DEAD:
		move_and_slide()
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	patrol_timer -= delta

	# Check for fire sources (settler holding torch or nearby hearth)
	_scan_for_fire()

	# High Crags Altitude Confinement: if wolf wanders below minimum altitude, head back uphill
	if global_position.y < min_mountain_altitude - 2.0 and not has_fire_threat:
		_retreat_to_mountain(delta)
		move_and_slide()
		return

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

func _retreat_to_mountain(delta: float) -> void:
	# Head back towards high crag
	var uphill_dir := (mountain_home - global_position).normalized()
	uphill_dir.y = 0.0
	velocity.x = uphill_dir.x * patrol_speed * 1.2
	velocity.z = uphill_dir.z * patrol_speed * 1.2
	if uphill_dir.length() > 0.1:
		var target_rot := atan2(-uphill_dir.x, -uphill_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * 4.0)

func _pick_mountain_patrol_target() -> void:
	var angle := randf() * 2.0 * PI
	var dist := randf_range(8.0, 35.0)
	wander_target = mountain_home + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

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

func _process_patrol(delta: float) -> void:
	var dir := (wander_target - global_position)
	dir.y = 0.0
	var dist := dir.length()
	if dist > 1.2:
		dir = dir.normalized()
		velocity.x = dir.x * patrol_speed
		velocity.z = dir.z * patrol_speed
		var target_rot := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * 3.5)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1.0)
		velocity.z = move_toward(velocity.z, 0.0, 1.0)
		if patrol_timer <= 0.0:
			_pick_mountain_patrol_target()
			patrol_timer = randf_range(4.0, 9.0)

	if player_target and global_position.distance_to(player_target.global_position) < detection_radius:
		if player_target.global_position.y >= min_mountain_altitude - 10.0:
			current_state = State.STALK

func _process_stalk(delta: float) -> void:
	if not player_target:
		current_state = State.PATROL
		return

	if has_fire_threat:
		current_state = State.FLEE_FIRE
		return

	# Disengage stalk if player flees down to the lowlands
	if player_target.global_position.y < min_mountain_altitude - 8.0:
		current_state = State.PATROL
		_pick_mountain_patrol_target()
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
			var target_rot := atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot, delta * 5.0)

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
	if Vector2(flee_dir.x, flee_dir.z).length() > 0.1:
		rotation.y = atan2(-flee_dir.x, -flee_dir.z)

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
