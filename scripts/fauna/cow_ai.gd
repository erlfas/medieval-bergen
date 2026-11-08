class_name CowAI
extends CharacterBody3D

## Docile Norwegian Red/Brown Cattle (Vestlandsk Raudkolle / Norsk Rødt Fe)
## - Grazing inside or adjacent to medieval farmstead pastures.
## - Very docile, slow-moving herbivore, chewing cud and grazing on sweet grass.
## - Can be milked by the settler with [E] for fresh milk (restores hunger & thirst).
## - Can be harvested for hearty beef and thick cattle hide / leather.

enum State { GRAZING, CHEWING_CUD, WANDERING, ALERT, SHELTERING, DEAD }

@export var current_state: State = State.GRAZING
@export var walk_speed: float = 1.4
@export var health: float = 60.0
@export var beef_yield: int = 5
@export var leather_yield: int = 3
@export var home_position: Vector3 = Vector3.ZERO
@export var pasture_radius: float = 20.0

var wander_target: Vector3 = Vector3.ZERO
var shelter_target: Vector3 = Vector3.ZERO
var season_manager: SeasonManager
var weather_check_timer: float = 0.0
var state_timer: float = 0.0
var milk_cooldown: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var head_pivot: Node3D
var tail_pivot: Node3D
var leg_nodes: Array[Node3D] = []
var walk_cycle: float = 0.0

func _ready() -> void:
	add_to_group("fauna")
	add_to_group("livestock")
	add_to_group("cow")
	if home_position == Vector3.ZERO:
		home_position = global_position
	_pick_wander_target()
	state_timer = randf_range(4.0, 10.0)
	weather_check_timer = randf_range(0.5, 2.0)
	if get_node_or_null("VisualModel") == null:
		_build_cow_mesh()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if current_state == State.DEAD:
		move_and_slide()
		return

	milk_cooldown = maxf(0.0, milk_cooldown - delta)
	state_timer -= delta
	weather_check_timer -= delta

	if weather_check_timer <= 0.0:
		weather_check_timer = 2.0
		_check_weather_and_shelter()

	match current_state:
		State.GRAZING:
			velocity.x = move_toward(velocity.x, 0.0, 1.0)
			velocity.z = move_toward(velocity.z, 0.0, 1.0)
			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(30.0), delta * 3.0)
			if state_timer <= 0.0:
				current_state = State.CHEWING_CUD if randf() > 0.4 else State.WANDERING
				if current_state == State.WANDERING:
					_pick_wander_target()
				state_timer = randf_range(5.0, 12.0)

		State.CHEWING_CUD:
			velocity.x = move_toward(velocity.x, 0.0, 1.0)
			velocity.z = move_toward(velocity.z, 0.0, 1.0)
			if head_pivot:
				var cud_chew := sin(Time.get_ticks_msec() * 0.008) * deg_to_rad(4.0)
				head_pivot.rotation.x = deg_to_rad(5.0) + cud_chew
				head_pivot.rotation.z = cud_chew * 0.5
			if state_timer <= 0.0:
				current_state = State.WANDERING
				_pick_wander_target()
				state_timer = randf_range(6.0, 14.0)

		State.WANDERING:
			var dir := (wander_target - global_position)
			dir.y = 0.0
			var dist := dir.length()
			if dist > 0.4:
				dir = dir.normalized()
				velocity.x = dir.x * walk_speed
				velocity.z = dir.z * walk_speed
				var target_rot := atan2(-dir.x, -dir.z)
				rotation.y = lerp_angle(rotation.y, target_rot, delta * 3.0)
			else:
				velocity.x = 0.0
				velocity.z = 0.0

			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(10.0), delta * 4.0)

			if dist < 1.0 or state_timer <= 0.0:
				current_state = State.GRAZING
				state_timer = randf_range(6.0, 15.0)

		State.ALERT:
			velocity.x = move_toward(velocity.x, 0.0, 1.5)
			velocity.z = move_toward(velocity.z, 0.0, 1.5)
			if head_pivot:
				head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(-15.0), delta * 6.0)
			if state_timer <= 0.0:
				current_state = State.GRAZING
				state_timer = 5.0

		State.SHELTERING:
			var dir := (shelter_target - global_position)
			dir.y = 0.0
			var dist := dir.length()
			if dist > 1.8:
				dir = dir.normalized()
				velocity.x = dir.x * (walk_speed * 1.15)
				velocity.z = dir.z * (walk_speed * 1.15)
				if Vector2(dir.x, dir.z).length() > 0.1:
					var target_rot := atan2(-dir.x, -dir.z)
					rotation.y = lerp_angle(rotation.y, target_rot, delta * 3.5)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 1.5)
				velocity.z = move_toward(velocity.z, 0.0, 1.5)

			# Huddle posture: head tucked slightly down, gentle breathing motion
			if head_pivot:
				var huddle_nod := sin(Time.get_ticks_msec() * 0.002) * deg_to_rad(4.0)
				head_pivot.rotation.x = deg_to_rad(15.0) + huddle_nod

	# Animate legs when walking
	_animate_limbs(delta)

	move_and_slide()

func _check_weather_and_shelter() -> void:
	if current_state == State.DEAD:
		return
	if season_manager == null and get_tree():
		season_manager = get_tree().get_first_node_in_group("season_manager") as SeasonManager

	var is_stormy := false
	if season_manager:
		is_stormy = season_manager.is_precipitating or season_manager.is_raining or season_manager.is_snowing or (season_manager.current_weather in [SeasonManager.WeatherState.HEAVY_RAIN, SeasonManager.WeatherState.SNOW])

	if is_stormy:
		if current_state != State.SHELTERING and current_state != State.ALERT:
			_find_nearest_shelter()
			current_state = State.SHELTERING
	elif current_state == State.SHELTERING:
		current_state = State.GRAZING
		state_timer = randf_range(4.0, 8.0)

func _find_nearest_shelter() -> void:
	var shelters := get_tree().get_nodes_in_group("shelter")
	var best_dist := 60.0
	var chosen_pos := home_position

	for s in shelters:
		if s is Node3D and is_instance_valid(s):
			var d := global_position.distance_to(s.global_position)
			if d < best_dist:
				best_dist = d
				chosen_pos = s.global_position + Vector3(0, 0, 1.8)

	shelter_target = chosen_pos

func _animate_limbs(delta: float) -> void:
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	if horiz_vel > 0.2:
		walk_cycle += delta * horiz_vel * 3.2
		var leg_swing := sin(walk_cycle) * deg_to_rad(22.0)
		if leg_nodes.size() >= 4:
			leg_nodes[0].rotation.x = leg_swing
			leg_nodes[1].rotation.x = -leg_swing
			leg_nodes[2].rotation.x = -leg_swing
			leg_nodes[3].rotation.x = leg_swing
	else:
		walk_cycle = 0.0
		for leg in leg_nodes:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, delta * 6.0)

	if tail_pivot:
		tail_pivot.rotation.z = sin(Time.get_ticks_msec() * 0.003) * deg_to_rad(15.0)

func _pick_wander_target() -> void:
	var angle := randf() * 2.0 * PI
	var dist := randf_range(2.0, pasture_radius * 0.7)
	wander_target = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func on_interact(actor: Node) -> void:
	if current_state == State.DEAD:
		return

	# Milk cow interaction
	if milk_cooldown <= 0.0 and actor and actor.has_node("InventoryManager"):
		var inv: InventoryManager = actor.get_node("InventoryManager")
		inv.add_resource("fresh_milk", 1)
		milk_cooldown = 45.0 # Cooldown until next milking

		# If player has SurvivalStats, drinking fresh milk is nourishing!
		if actor.has_node("SurvivalStats"):
			var stats: SurvivalStats = actor.get_node("SurvivalStats")
			stats.hunger = minf(100.0, stats.hunger + 15.0)
			stats.thirst = minf(100.0, stats.thirst + 25.0)
		
		# Gentle reaction
		current_state = State.ALERT
		state_timer = 2.5
	else:
		# Just gentle patting
		current_state = State.ALERT
		state_timer = 2.0

func take_damage(amount: float, attacker: Node) -> void:
	if current_state == State.DEAD:
		return

	health -= amount
	current_state = State.ALERT
	state_timer = 3.5

	# Flee a bit if attacked
	if attacker is Node3D:
		var flee_dir: Vector3 = (global_position - (attacker as Node3D).global_position).normalized()
		wander_target = global_position + flee_dir * 12.0
		current_state = State.WANDERING
		state_timer = 5.0

	if health <= 0.0:
		die(attacker)

func die(killer: Node) -> void:
	current_state = State.DEAD
	velocity = Vector3.ZERO
	rotation.z = deg_to_rad(90.0)

	if killer and killer.has_node("InventoryManager"):
		var inv: InventoryManager = killer.get_node("InventoryManager")
		inv.add_resource("raw_beef", beef_yield)
		inv.add_resource("cattle_hide", leather_yield)

	if get_tree():
		get_tree().create_timer(30.0).timeout.connect(queue_free)
	else:
		queue_free()

func _build_cow_mesh() -> void:
	var visual := Node3D.new()
	visual.name = "VisualModel"
	add_child(visual)

	var mat_hide := StandardMaterial3D.new()
	mat_hide.albedo_color = Color(0.48, 0.22, 0.14) # Norwegian red/brown coat
	mat_hide.roughness = 0.88

	var mat_white := StandardMaterial3D.new()
	mat_white.albedo_color = Color(0.92, 0.90, 0.86) # White markings
	mat_white.roughness = 0.9

	var mat_snout := StandardMaterial3D.new()
	mat_snout.albedo_color = Color(0.72, 0.54, 0.52) # Pinkish leather muzzle
	mat_snout.roughness = 0.7

	var mat_horn := StandardMaterial3D.new()
	mat_horn.albedo_color = Color(0.82, 0.78, 0.68) # Bone / horn
	mat_horn.roughness = 0.6

	var mat_hoof := StandardMaterial3D.new()
	mat_hoof.albedo_color = Color(0.20, 0.18, 0.16) # Dark horn hoof
	mat_hoof.roughness = 0.8

	# Torso
	var body_m := MeshInstance3D.new()
	var box_body := BoxMesh.new()
	box_body.size = Vector3(1.1, 1.05, 1.9)
	body_m.mesh = box_body
	body_m.position = Vector3(0, 1.15, 0)
	body_m.material_override = mat_hide
	visual.add_child(body_m)

	# White belly / side patch
	var patch_m := MeshInstance3D.new()
	var box_patch := BoxMesh.new()
	box_patch.size = Vector3(1.12, 0.6, 0.9)
	patch_m.mesh = box_patch
	patch_m.position = Vector3(0, 1.05, 0.1)
	patch_m.material_override = mat_white
	visual.add_child(patch_m)

	# Head Pivot & Neck
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 1.45, -0.9)
	visual.add_child(head_pivot)

	var head_m := MeshInstance3D.new()
	var box_head := BoxMesh.new()
	box_head.size = Vector3(0.5, 0.55, 0.75)
	head_m.mesh = box_head
	head_m.position = Vector3(0, 0.05, -0.32)
	head_m.material_override = mat_hide
	head_pivot.add_child(head_m)

	# Muzzle / Snout
	var muzzle_m := MeshInstance3D.new()
	var box_muzzle := BoxMesh.new()
	box_muzzle.size = Vector3(0.42, 0.32, 0.32)
	muzzle_m.mesh = box_muzzle
	muzzle_m.position = Vector3(0, -0.06, -0.72)
	muzzle_m.material_override = mat_snout
	head_pivot.add_child(muzzle_m)

	# Horns (Left & Right)
	for sign_x in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var cone_horn := CylinderMesh.new()
		cone_horn.top_radius = 0.02
		cone_horn.bottom_radius = 0.06
		cone_horn.height = 0.28
		horn.mesh = cone_horn
		horn.position = Vector3(sign_x * 0.22, 0.35, -0.35)
		horn.rotation_degrees = Vector3(15, 0, sign_x * 35)
		horn.material_override = mat_horn
		head_pivot.add_child(horn)

		# Ears
		var ear := MeshInstance3D.new()
		var box_ear := BoxMesh.new()
		box_ear.size = Vector3(0.24, 0.09, 0.12)
		ear.mesh = box_ear
		ear.position = Vector3(sign_x * 0.32, 0.18, -0.22)
		ear.rotation_degrees = Vector3(0, 0, sign_x * 20)
		ear.material_override = mat_hide
		head_pivot.add_child(ear)

	# Tail
	tail_pivot = Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0, 1.55, 0.95)
	visual.add_child(tail_pivot)

	var tail_m := MeshInstance3D.new()
	var cyl_tail := CylinderMesh.new()
	cyl_tail.top_radius = 0.03
	cyl_tail.bottom_radius = 0.04
	cyl_tail.height = 0.65
	tail_m.mesh = cyl_tail
	tail_m.position = Vector3(0, -0.32, 0)
	tail_m.material_override = mat_hide
	tail_pivot.add_child(tail_m)

	# 4 Sturdy Legs
	leg_nodes.clear()
	var leg_coords := [
		Vector3(-0.38, 0.72, -0.65), # Front-Left
		Vector3(0.38, 0.72, -0.65),  # Front-Right
		Vector3(-0.38, 0.72, 0.65),  # Back-Left
		Vector3(0.38, 0.72, 0.65)   # Back-Right
	]
	for pos in leg_coords:
		var leg_pivot := Node3D.new()
		leg_pivot.position = pos
		visual.add_child(leg_pivot)
		leg_nodes.append(leg_pivot)

		var leg_mesh := MeshInstance3D.new()
		var box_leg := BoxMesh.new()
		box_leg.size = Vector3(0.24, 0.75, 0.24)
		leg_mesh.mesh = box_leg
		leg_mesh.position = Vector3(0, -0.37, 0)
		leg_mesh.material_override = mat_hide
		leg_pivot.add_child(leg_mesh)

		var hoof_mesh := MeshInstance3D.new()
		var box_hoof := BoxMesh.new()
		box_hoof.size = Vector3(0.26, 0.14, 0.26)
		hoof_mesh.mesh = box_hoof
		hoof_mesh.position = Vector3(0, -0.74, 0)
		hoof_mesh.material_override = mat_hoof
		leg_pivot.add_child(hoof_mesh)

	# Main Capsule CollisionShape3D
	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(1.2, 1.5, 2.1)
	col.shape = box_col
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
