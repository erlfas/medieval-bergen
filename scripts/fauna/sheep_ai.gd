class_name SheepAI
extends CharacterBody3D

## Old Norwegian Short-Tail Sheep (Villsau / Gammelnorsk sau)
## - Grazing on hillside meadows and pasture slopes near medieval farmsteads.
## - Hardened coastal breed with dense double fleece, curled horns, and nimble legs.
## - Can be sheared with [E] for raw wool (used for warm clothing and tunics).
## - Can be hunted for raw mutton and sheepskin.

enum State { GRAZING, RESTING, WANDERING, FLEEING, SHELTERING, DEAD }

@export var current_state: State = State.GRAZING
@export var walk_speed: float = 2.0
@export var run_speed: float = 6.2
@export var health: float = 25.0
@export var wool_yield: int = 3
@export var mutton_yield: int = 3
@export var home_position: Vector3 = Vector3.ZERO
@export var pasture_radius: float = 28.0
@export var fleece_color: Color = Color(0.88, 0.86, 0.82) # Natural undyed sheep wool

var wander_target: Vector3 = Vector3.ZERO
var shelter_target: Vector3 = Vector3.ZERO
var season_manager: SeasonManager
var weather_check_timer: float = 0.0
var state_timer: float = 0.0
var shear_cooldown: float = 0.0
var has_wool: bool = true
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var player_target: Node3D
var head_pivot: Node3D
var leg_nodes: Array[Node3D] = []
var fleece_mesh: MeshInstance3D
var walk_cycle: float = 0.0

func _ready() -> void:
	add_to_group("fauna")
	add_to_group("livestock")
	add_to_group("sheep")
	if home_position == Vector3.ZERO:
		home_position = global_position
	if get_tree():
		player_target = get_tree().get_first_node_in_group("settler") as Node3D
	_pick_wander_target()
	state_timer = randf_range(3.0, 8.0)
	weather_check_timer = randf_range(0.5, 2.0)
	if get_node_or_null("VisualModel") == null:
		_build_sheep_mesh()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if current_state == State.DEAD:
		move_and_slide()
		return

	shear_cooldown = maxf(0.0, shear_cooldown - delta)
	if shear_cooldown <= 0.0 and not has_wool:
		has_wool = true
		if fleece_mesh:
			fleece_mesh.visible = true

	state_timer -= delta
	weather_check_timer -= delta

	if weather_check_timer <= 0.0:
		weather_check_timer = 2.0
		_check_weather_and_shelter()

	# Check for approaching threats (wolf or sprinting settler)
	if player_target:
		var dist := global_position.distance_to(player_target.global_position)
		if dist < 4.5 and current_state != State.FLEEING:
			current_state = State.FLEEING
			state_timer = 4.0

	var wolves := get_tree().get_nodes_in_group("wolf")
	for w in wolves:
		if w is Node3D and is_instance_valid(w):
			if global_position.distance_to(w.global_position) < 14.0:
				current_state = State.FLEEING
				state_timer = 6.0
				break

	match current_state:
		State.GRAZING:
			velocity.x = move_toward(velocity.x, 0.0, 1.2)
			velocity.z = move_toward(velocity.z, 0.0, 1.2)
			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(35.0), delta * 4.0)
			if state_timer <= 0.0:
				current_state = State.WANDERING if randf() > 0.3 else State.RESTING
				if current_state == State.WANDERING:
					_pick_wander_target()
				state_timer = randf_range(4.0, 9.0)

		State.RESTING:
			velocity.x = move_toward(velocity.x, 0.0, 1.2)
			velocity.z = move_toward(velocity.z, 0.0, 1.2)
			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(5.0), delta * 3.0)
			if state_timer <= 0.0:
				current_state = State.WANDERING
				_pick_wander_target()
				state_timer = randf_range(5.0, 10.0)

		State.WANDERING:
			var dir := (wander_target - global_position)
			dir.y = 0.0
			var dist := dir.length()
			if dist > 0.3:
				dir = dir.normalized()
				velocity.x = dir.x * walk_speed
				velocity.z = dir.z * walk_speed
				var target_rot := atan2(-dir.x, -dir.z)
				rotation.y = lerp_angle(rotation.y, target_rot, delta * 4.0)
			else:
				velocity.x = 0.0
				velocity.z = 0.0

			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(12.0), delta * 4.0)

			if dist < 0.8 or state_timer <= 0.0:
				current_state = State.GRAZING
				state_timer = randf_range(5.0, 11.0)

		State.FLEEING:
			var flee_origin := player_target.global_position if player_target else home_position
			var flee_dir := (global_position - flee_origin).normalized()
			flee_dir.y = 0.0
			velocity.x = flee_dir.x * run_speed
			velocity.z = flee_dir.z * run_speed
			if flee_dir.length() > 0.1:
				var target_rot := atan2(-flee_dir.x, -flee_dir.z)
				rotation.y = lerp_angle(rotation.y, target_rot, delta * 8.0)
			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(-10.0), delta * 8.0)
			if state_timer <= 0.0:
				if _is_weather_stormy():
					current_state = State.SHELTERING
					_find_nearest_shelter()
				else:
					current_state = State.GRAZING
				state_timer = 5.0

		State.SHELTERING:
			var dir := (shelter_target - global_position)
			dir.y = 0.0
			var dist := dir.length()
			if dist > 1.4:
				dir = dir.normalized()
				velocity.x = dir.x * (walk_speed * 1.2)
				velocity.z = dir.z * (walk_speed * 1.2)
				if Vector2(dir.x, dir.z).length() > 0.1:
					var target_rot := atan2(-dir.x, -dir.z)
					rotation.y = lerp_angle(rotation.y, target_rot, delta * 4.0)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 1.5)
				velocity.z = move_toward(velocity.z, 0.0, 1.5)

			# Huddled resting under eave / rack
			if head_pivot:
				var huddle := sin(Time.get_ticks_msec() * 0.003) * deg_to_rad(3.0)
				head_pivot.rotation.x = deg_to_rad(8.0) + huddle

	_animate_limbs(delta)
	move_and_slide()

func _is_weather_stormy() -> bool:
	if season_manager == null and get_tree():
		season_manager = get_tree().get_first_node_in_group("season_manager") as SeasonManager
	if season_manager:
		return season_manager.is_precipitating or season_manager.is_raining or season_manager.is_snowing or (season_manager.current_weather in [SeasonManager.WeatherState.HEAVY_RAIN, SeasonManager.WeatherState.SNOW])
	return false

func _check_weather_and_shelter() -> void:
	if current_state == State.DEAD or current_state == State.FLEEING:
		return

	if _is_weather_stormy():
		if current_state != State.SHELTERING:
			_find_nearest_shelter()
			current_state = State.SHELTERING
	elif current_state == State.SHELTERING:
		current_state = State.GRAZING
		state_timer = randf_range(3.0, 7.0)

func _find_nearest_shelter() -> void:
	var shelters := get_tree().get_nodes_in_group("shelter")
	var best_dist := 65.0
	var chosen_pos := home_position

	for s in shelters:
		if s is Node3D and is_instance_valid(s):
			var d := global_position.distance_to(s.global_position)
			if d < best_dist:
				best_dist = d
				chosen_pos = s.global_position + Vector3(0.5, 0, 1.2)

	shelter_target = chosen_pos

func _animate_limbs(delta: float) -> void:
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	if horiz_vel > 0.2:
		var mult := 5.5 if current_state == State.FLEEING else 3.8
		walk_cycle += delta * horiz_vel * mult
		var leg_swing := sin(walk_cycle) * deg_to_rad(28.0)
		if leg_nodes.size() >= 4:
			leg_nodes[0].rotation.x = leg_swing
			leg_nodes[1].rotation.x = -leg_swing
			leg_nodes[2].rotation.x = -leg_swing
			leg_nodes[3].rotation.x = leg_swing
	else:
		walk_cycle = 0.0
		for leg in leg_nodes:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, delta * 6.0)

func _pick_wander_target() -> void:
	var angle := randf() * 2.0 * PI
	var dist := randf_range(3.0, pasture_radius * 0.8)
	wander_target = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func on_interact(actor: Node) -> void:
	if current_state == State.DEAD:
		return

	# Shearing sheep for wool
	if has_wool and actor and actor.has_node("InventoryManager"):
		var inv: InventoryManager = actor.get_node("InventoryManager")
		inv.add_resource("wool_fleece", wool_yield)
		has_wool = false
		shear_cooldown = 60.0
		if fleece_mesh:
			fleece_mesh.visible = false
		current_state = State.FLEEING
		state_timer = 2.5
	else:
		# Sheep hops away gently
		current_state = State.FLEEING
		state_timer = 2.0

func take_damage(amount: float, attacker: Node) -> void:
	if current_state == State.DEAD:
		return

	health -= amount
	current_state = State.FLEEING
	state_timer = 6.0

	if health <= 0.0:
		die(attacker)

func die(killer: Node) -> void:
	current_state = State.DEAD
	velocity = Vector3.ZERO
	rotation.z = deg_to_rad(90.0)

	if killer and killer.has_node("InventoryManager"):
		var inv: InventoryManager = killer.get_node("InventoryManager")
		inv.add_resource("raw_mutton", mutton_yield)
		inv.add_resource("wool_fleece", wool_yield if has_wool else 1)

	if get_tree():
		get_tree().create_timer(30.0).timeout.connect(queue_free)
	else:
		queue_free()

func _build_sheep_mesh() -> void:
	var visual := Node3D.new()
	visual.name = "VisualModel"
	add_child(visual)

	var mat_fleece := StandardMaterial3D.new()
	mat_fleece.albedo_color = fleece_color
	mat_fleece.roughness = 0.95

	var mat_dark_skin := StandardMaterial3D.new()
	mat_dark_skin.albedo_color = Color(0.22, 0.20, 0.18) # Dark Villsau face & legs
	mat_dark_skin.roughness = 0.85

	var mat_horn := StandardMaterial3D.new()
	mat_horn.albedo_color = Color(0.68, 0.62, 0.52) # Spiral ram horn
	mat_horn.roughness = 0.6

	# Inner body
	var body_m := MeshInstance3D.new()
	var cap_body := CapsuleMesh.new()
	cap_body.radius = 0.32
	cap_body.height = 0.9
	body_m.mesh = cap_body
	body_m.rotation.x = deg_to_rad(90.0)
	body_m.position = Vector3(0, 0.65, 0)
	body_m.material_override = mat_fleece
	visual.add_child(body_m)

	# Fluffy outer wool fleece layer
	fleece_mesh = MeshInstance3D.new()
	var box_fleece := BoxMesh.new()
	box_fleece.size = Vector3(0.72, 0.65, 1.05)
	fleece_mesh.mesh = box_fleece
	fleece_mesh.position = Vector3(0, 0.66, 0)
	fleece_mesh.material_override = mat_fleece
	visual.add_child(fleece_mesh)

	# Head Pivot
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 0.85, -0.52)
	visual.add_child(head_pivot)

	var head_m := MeshInstance3D.new()
	var box_head := BoxMesh.new()
	box_head.size = Vector3(0.26, 0.28, 0.42)
	head_m.mesh = box_head
	head_m.position = Vector3(0, 0, -0.16)
	head_m.material_override = mat_dark_skin
	head_pivot.add_child(head_m)

	# Woolly top cap on head
	var head_wool := MeshInstance3D.new()
	var box_hw := BoxMesh.new()
	box_hw.size = Vector3(0.28, 0.12, 0.26)
	head_wool.mesh = box_hw
	head_wool.position = Vector3(0, 0.15, -0.08)
	head_wool.material_override = mat_fleece
	head_pivot.add_child(head_wool)

	# Curled Villsau Horns
	for sign_x in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var tor_horn := TorusMesh.new()
		tor_horn.inner_radius = 0.08
		tor_horn.outer_radius = 0.16
		horn.mesh = tor_horn
		horn.position = Vector3(sign_x * 0.18, 0.12, -0.12)
		horn.rotation_degrees = Vector3(30, sign_x * 45, sign_x * 60)
		horn.material_override = mat_horn
		head_pivot.add_child(horn)

		# Ears
		var ear := MeshInstance3D.new()
		var box_ear := BoxMesh.new()
		box_ear.size = Vector3(0.18, 0.06, 0.08)
		ear.mesh = box_ear
		ear.position = Vector3(sign_x * 0.18, 0.06, -0.06)
		ear.rotation_degrees = Vector3(-10, 0, sign_x * 25)
		ear.material_override = mat_dark_skin
		head_pivot.add_child(ear)

	# 4 Slender Legs
	leg_nodes.clear()
	var leg_coords := [
		Vector3(-0.22, 0.45, -0.35),
		Vector3(0.22, 0.45, -0.35),
		Vector3(-0.22, 0.45, 0.35),
		Vector3(0.22, 0.45, 0.35)
	]
	for pos in leg_coords:
		var leg_pivot := Node3D.new()
		leg_pivot.position = pos
		visual.add_child(leg_pivot)
		leg_nodes.append(leg_pivot)

		var leg_m := MeshInstance3D.new()
		var cyl_leg := CylinderMesh.new()
		cyl_leg.top_radius = 0.05
		cyl_leg.bottom_radius = 0.04
		cyl_leg.height = 0.48
		leg_m.mesh = cyl_leg
		leg_m.position = Vector3(0, -0.24, 0)
		leg_m.material_override = mat_dark_skin
		leg_pivot.add_child(leg_m)

	# Collision
	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(0.8, 1.0, 1.2)
	col.shape = box_col
	col.position = Vector3(0, 0.55, 0)
	add_child(col)
