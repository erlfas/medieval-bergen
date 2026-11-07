class_name DeerAI
extends CharacterBody3D

## Red Deer (Hjort) AI for Medieval Bergen:
## - Peaceful herbivore grazing on meadows and forest clearings
## - Skittish: detects settler scent/movement and flees into the hills
## - Can be hunted for raw venison and deer hide

enum State { GRAZING, WANDERING, ALERT, FLEEING, DEAD }

@export var current_state: State = State.GRAZING
@export var walk_speed: float = 2.2
@export var run_speed: float = 8.0
@export var detection_radius: float = 18.0
@export var health: float = 35.0
@export var venison_yield: int = 4
@export var hide_yield: int = 2

var player_target: CharacterBody3D
var wander_target: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var alert_cooldown: float = 0.0
var threat_position: Vector3 = Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	add_to_group("deer")
	add_to_group("fauna")
	_pick_wander_target()
	player_target = get_tree().get_first_node_in_group("settler") as CharacterBody3D

func receive_herd_alarm(alarm_origin: Vector3) -> void:
	if current_state != State.DEAD:
		threat_position = alarm_origin
		current_state = State.FLEEING
		state_timer = randf_range(4.0, 7.0)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if current_state == State.DEAD:
		return

	alert_cooldown -= delta

	if player_target:
		var dist := global_position.distance_to(player_target.global_position)
		if dist < detection_radius and current_state != State.FLEEING:
			threat_position = player_target.global_position
			current_state = State.FLEEING
			_broadcast_herd_alarm()

	state_timer -= delta
	match current_state:
		State.GRAZING:
			velocity.x = move_toward(velocity.x, 0.0, 1.0)
			velocity.z = move_toward(velocity.z, 0.0, 1.0)
			if state_timer <= 0.0:
				current_state = State.WANDERING
				_pick_wander_target()
				state_timer = randf_range(3.0, 7.0)

		State.WANDERING:
			var dir := (wander_target - global_position).normalized()
			velocity.x = dir.x * walk_speed
			velocity.z = dir.z * walk_speed
			if Vector2(dir.x, dir.z).length() > 0.1:
				rotation.y = atan2(-dir.x, -dir.z)
			if global_position.distance_to(wander_target) < 1.5 or state_timer <= 0.0:
				current_state = State.GRAZING
				state_timer = randf_range(4.0, 8.0)

		State.FLEEING:
			_broadcast_herd_alarm()

			var threat := player_target.global_position if player_target else threat_position
			var flee_dir := (global_position - threat).normalized()
			flee_dir.y = 0.0

			# Flocking: Cohesion & Separation from nearby herd deer
			var align_sum := Vector3.ZERO
			var sep_sum := Vector3.ZERO
			var neighbors := 0

			for d in get_tree().get_nodes_in_group("deer"):
				if d != self and is_instance_valid(d) and d is CharacterBody3D and d.get("current_state") != State.DEAD:
					var dist_d := global_position.distance_to(d.global_position)
					if dist_d < 18.0:
						var vel_norm: Vector3 = (d as CharacterBody3D).velocity.normalized()
						if vel_norm.length_squared() > 0.01:
							align_sum += vel_norm
							neighbors += 1
					if dist_d < 3.2 and dist_d > 0.05:
						sep_sum += (global_position - d.global_position).normalized() * (3.2 - dist_d)

			var flock_dir := flee_dir * 0.65
			if neighbors > 0:
				flock_dir += (align_sum / float(neighbors)).normalized() * 0.25
			if sep_sum.length_squared() > 0.01:
				flock_dir += sep_sum.normalized() * 0.15

			flock_dir = flock_dir.normalized()
			velocity.x = flock_dir.x * run_speed
			velocity.z = flock_dir.z * run_speed

			if Vector2(flock_dir.x, flock_dir.z).length() > 0.1:
				rotation.y = atan2(-flock_dir.x, -flock_dir.z)

			if player_target and global_position.distance_to(player_target.global_position) > detection_radius * 1.8:
				current_state = State.GRAZING
				state_timer = 5.0

func _broadcast_herd_alarm() -> void:
	if alert_cooldown > 0.0:
		return
	alert_cooldown = 3.5
	for d in get_tree().get_nodes_in_group("deer"):
		if d != self and is_instance_valid(d) and d.has_method("receive_herd_alarm"):
			if global_position.distance_to(d.global_position) < 28.0:
				d.receive_herd_alarm(global_position)

	move_and_slide()

func _pick_wander_target() -> void:
	var angle := randf() * 2.0 * PI
	var dist := randf_range(6.0, 18.0)
	wander_target = global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func take_damage(amount: float, attacker: Node) -> void:
	if current_state == State.DEAD:
		return

	health -= amount
	current_state = State.FLEEING

	if health <= 0.0:
		die(attacker)

func die(killer: Node) -> void:
	current_state = State.DEAD
	velocity = Vector3.ZERO
	rotation.z = deg_to_rad(90.0) # Fall over onto side

	# Reward hunter with venison and hide
	if killer and killer.has_node("InventoryManager"):
		var inv: InventoryManager = killer.get_node("InventoryManager")
		inv.add_resource("raw_venison", venison_yield)
		inv.add_resource("deer_hide", hide_yield)

	# Delete carcass after 30 seconds
	get_tree().create_timer(30.0).timeout.connect(queue_free)

func on_interact(actor: Node) -> void:
	if current_state != State.DEAD:
		take_damage(20.0, actor)
