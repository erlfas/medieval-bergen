class_name RabbitAI
extends CharacterBody3D

## Norwegian Mountain Hare (Jærhare / Fjellhare)
## - Small, fast, agile hares hopping in brush, forest clearings, and farm perimeter.
## - Extremely skittish: detects predators (wolves, settler) from afar and darts away.
## - Distinct hopping locomotion with rhythmic vertical leaps.
## - Can be hunted with bows/traps/axe for tender hare meat and soft warm hare fur.

enum State { IDLE_SNIFFING, FORAGING, HOPPING, ALERT, FLEEING, DEAD }

@export var current_state: State = State.IDLE_SNIFFING
@export var hop_speed: float = 3.2
@export var flee_speed: float = 8.5
@export var health: float = 12.0
@export var meat_yield: int = 2
@export var fur_yield: int = 2
@export var home_position: Vector3 = Vector3.ZERO
@export var roam_radius: float = 35.0

var wander_target: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var hop_cycle: float = 0.0
var is_mid_hop: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 1.2
var player_target: Node3D
var ears_pivot: Node3D
var head_pivot: Node3D

func _ready() -> void:
	add_to_group("fauna")
	add_to_group("rabbit")
	add_to_group("prey")
	if home_position == Vector3.ZERO:
		home_position = global_position
	if get_tree():
		player_target = get_tree().get_first_node_in_group("settler") as Node3D
	_pick_wander_target()
	state_timer = randf_range(2.0, 5.0)
	if get_node_or_null("VisualModel") == null:
		_build_rabbit_mesh()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if current_state == State.DEAD:
		move_and_slide()
		return

	state_timer -= delta

	# Check for threats (settler or wolf)
	var threat_pos := Vector3.ZERO
	var has_threat := false

	if player_target:
		var dist := global_position.distance_to(player_target.global_position)
		if dist < 12.0:
			has_threat = true
			threat_pos = player_target.global_position

	if not has_threat:
		var wolves := get_tree().get_nodes_in_group("wolf")
		for w in wolves:
			if w is Node3D and is_instance_valid(w):
				if global_position.distance_to(w.global_position) < 18.0:
					has_threat = true
					threat_pos = w.global_position
					break

	if has_threat and current_state != State.FLEEING:
		current_state = State.FLEEING
		state_timer = randf_range(4.0, 7.0)

	match current_state:
		State.IDLE_SNIFFING:
			velocity.x = move_toward(velocity.x, 0.0, 2.0)
			velocity.z = move_toward(velocity.z, 0.0, 2.0)
			if head_pivot:
				var twitch := sin(Time.get_ticks_msec() * 0.02) * deg_to_rad(6.0)
				head_pivot.rotation.x = twitch
			if state_timer <= 0.0:
				current_state = State.HOPPING if randf() > 0.4 else State.FORAGING
				if current_state == State.HOPPING:
					_pick_wander_target()
				state_timer = randf_range(2.5, 6.0)

		State.FORAGING:
			velocity.x = move_toward(velocity.x, 0.0, 2.0)
			velocity.z = move_toward(velocity.z, 0.0, 2.0)
			if head_pivot:
				head_pivot.rotation.x = deg_to_rad(25.0) + sin(Time.get_ticks_msec() * 0.01) * deg_to_rad(4.0)
			if state_timer <= 0.0:
				current_state = State.HOPPING
				_pick_wander_target()
				state_timer = randf_range(3.0, 6.0)

		State.HOPPING:
			var dir := (wander_target - global_position)
			dir.y = 0.0
			var dist := dir.length()
			if dist > 0.4:
				dir = dir.normalized()
				var target_rot := atan2(-dir.x, -dir.z)
				rotation.y = lerp_angle(rotation.y, target_rot, delta * 6.0)

				# Hopping rhythm
				hop_cycle += delta * 6.5
				if sin(hop_cycle) > 0.3:
					velocity.x = dir.x * hop_speed
					velocity.z = dir.z * hop_speed
					if is_on_floor() and not is_mid_hop:
						velocity.y = 2.4
						is_mid_hop = true
				else:
					velocity.x = move_toward(velocity.x, 0.0, 1.5)
					velocity.z = move_toward(velocity.z, 0.0, 1.5)
					if is_on_floor():
						is_mid_hop = false
			else:
				velocity.x = 0.0
				velocity.z = 0.0
				current_state = State.IDLE_SNIFFING
				state_timer = randf_range(2.0, 5.0)

		State.FLEEING:
			var flee_dir := (global_position - threat_pos).normalized()
			flee_dir.y = 0.0
			if flee_dir.length() > 0.1:
				var target_rot := atan2(-flee_dir.x, -flee_dir.z)
				rotation.y = lerp_angle(rotation.y, target_rot, delta * 12.0)

				# Fast zig-zag burst hops
				hop_cycle += delta * 14.0
				velocity.x = flee_dir.x * flee_speed
				velocity.z = flee_dir.z * flee_speed
				if is_on_floor() and sin(hop_cycle) > 0.4:
					velocity.y = 3.6

			if state_timer <= 0.0 and (threat_pos == Vector3.ZERO or global_position.distance_to(threat_pos) > 22.0):
				current_state = State.IDLE_SNIFFING
				state_timer = 3.0

	move_and_slide()

func _pick_wander_target() -> void:
	var angle := randf() * 2.0 * PI
	var dist := randf_range(2.0, roam_radius * 0.6)
	wander_target = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func on_interact(_actor: Node) -> void:
	if current_state != State.DEAD:
		current_state = State.FLEEING
		state_timer = 5.0

func take_damage(amount: float, attacker: Node) -> void:
	if current_state == State.DEAD:
		return

	health -= amount
	current_state = State.FLEEING
	state_timer = 8.0

	if health <= 0.0:
		die(attacker)

func die(killer: Node) -> void:
	current_state = State.DEAD
	velocity = Vector3.ZERO
	rotation.z = deg_to_rad(90.0)

	if killer and killer.has_node("InventoryManager"):
		var inv: InventoryManager = killer.get_node("InventoryManager")
		inv.add_resource("raw_hare", meat_yield)
		inv.add_resource("hare_fur", fur_yield)

	if get_tree():
		get_tree().create_timer(30.0).timeout.connect(queue_free)
	else:
		queue_free()

func _build_rabbit_mesh() -> void:
	var visual := Node3D.new()
	visual.name = "VisualModel"
	add_child(visual)

	var mat_fur := StandardMaterial3D.new()
	mat_fur.albedo_color = Color(0.62, 0.54, 0.44) # Tawny earth hare brown
	mat_fur.roughness = 0.92

	var mat_ear_inner := StandardMaterial3D.new()
	mat_ear_inner.albedo_color = Color(0.85, 0.72, 0.70) # Pale pink inner ear
	mat_ear_inner.roughness = 0.85

	var mat_belly := StandardMaterial3D.new()
	mat_belly.albedo_color = Color(0.88, 0.86, 0.82) # Pale underbelly & tail
	mat_belly.roughness = 0.9

	# Main Body
	var body_m := MeshInstance3D.new()
	var cap_body := CapsuleMesh.new()
	cap_body.radius = 0.16
	cap_body.height = 0.48
	body_m.mesh = cap_body
	body_m.rotation.x = deg_to_rad(65.0)
	body_m.position = Vector3(0, 0.22, 0)
	body_m.material_override = mat_fur
	visual.add_child(body_m)

	# Fluffy White Tail
	var tail_m := MeshInstance3D.new()
	var sph_tail := SphereMesh.new()
	sph_tail.radius = 0.08
	sph_tail.height = 0.16
	tail_m.mesh = sph_tail
	tail_m.position = Vector3(0, 0.22, 0.22)
	tail_m.material_override = mat_belly
	visual.add_child(tail_m)

	# Head Pivot
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 0.32, -0.18)
	visual.add_child(head_pivot)

	var head_m := MeshInstance3D.new()
	var box_head := BoxMesh.new()
	box_head.size = Vector3(0.16, 0.16, 0.22)
	head_m.mesh = box_head
	head_m.position = Vector3(0, 0, -0.06)
	head_m.material_override = mat_fur
	head_pivot.add_child(head_m)

	# Long Hare Ears
	ears_pivot = Node3D.new()
	ears_pivot.name = "EarsPivot"
	ears_pivot.position = Vector3(0, 0.08, 0)
	head_pivot.add_child(ears_pivot)

	for sign_x in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var box_ear := BoxMesh.new()
		box_ear.size = Vector3(0.05, 0.26, 0.03)
		ear.mesh = box_ear
		ear.position = Vector3(sign_x * 0.05, 0.13, 0)
		ear.rotation_degrees = Vector3(-12, 0, sign_x * 10)
		ear.material_override = mat_fur
		ears_pivot.add_child(ear)

		var ear_in := MeshInstance3D.new()
		var box_in := BoxMesh.new()
		box_in.size = Vector3(0.03, 0.22, 0.01)
		ear_in.mesh = box_in
		ear_in.position = Vector3(sign_x * 0.05, 0.13, -0.015)
		ear_in.rotation_degrees = Vector3(-12, 0, sign_x * 10)
		ear_in.material_override = mat_ear_inner
		ears_pivot.add_child(ear_in)

	# Hind legs
	for sign_x in [-1.0, 1.0]:
		var h_leg := MeshInstance3D.new()
		var box_hl := BoxMesh.new()
		box_hl.size = Vector3(0.08, 0.16, 0.22)
		h_leg.mesh = box_hl
		h_leg.position = Vector3(sign_x * 0.14, 0.14, 0.1)
		h_leg.material_override = mat_fur
		visual.add_child(h_leg)

	# Collision
	var col := CollisionShape3D.new()
	var cap_col := CapsuleShape3D.new()
	cap_col.radius = 0.2
	cap_col.height = 0.5
	col.shape = cap_col
	col.position = Vector3(0, 0.24, 0)
	add_child(col)
