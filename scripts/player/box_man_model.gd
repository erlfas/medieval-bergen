class_name BoxManModel
extends Node3D

## Simple procedural gray box man model for the Bergen 1360 settler:
## - Torso with medieval wool tunic & belt
## - Head with brow / visor indicating facing direction
## - Left & Right arms with hands (torch in left hand, iron axe in right hand)
## - Left & Right legs with boots
## - Procedural limb swing animations for walking, sprinting, jumping, idle breathing, and chopping

@export var tunic_color: Color = Color(0.46, 0.48, 0.52) # Slate grey wool
@export var skin_color: Color = Color(0.68, 0.68, 0.70)  # Light stone grey
@export var belt_color: Color = Color(0.24, 0.22, 0.20)  # Dark leather
@export var boot_color: Color = Color(0.28, 0.28, 0.30)  # Charcoal leather boots
@export var axe_wood_color: Color = Color(0.42, 0.28, 0.16)
@export var iron_color: Color = Color(0.65, 0.68, 0.72)

# Node references for animation
var torso_node: Node3D
var head_node: Node3D
var left_arm_pivot: Node3D
var right_arm_pivot: Node3D
var left_leg_pivot: Node3D
var right_leg_pivot: Node3D
var torch_mesh: Node3D
var axe_mesh: Node3D
var carried_log_node: Node3D

var walk_cycle: float = 0.0
var chop_timer: float = 0.0
var is_chopping: bool = false
var has_torch: bool = false
var is_carrying_log: bool = false

func _ready() -> void:
	_build_box_man()

func _build_box_man() -> void:
	# Shared materials
	var mat_tunic := StandardMaterial3D.new()
	mat_tunic.albedo_color = tunic_color
	mat_tunic.roughness = 0.9

	var mat_skin := StandardMaterial3D.new()
	mat_skin.albedo_color = skin_color
	mat_skin.roughness = 0.8

	var mat_belt := StandardMaterial3D.new()
	mat_belt.albedo_color = belt_color
	mat_belt.roughness = 0.7

	var mat_boot := StandardMaterial3D.new()
	mat_boot.albedo_color = boot_color
	mat_boot.roughness = 0.85

	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = iron_color
	mat_iron.metallic = 0.8
	mat_iron.roughness = 0.35

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = axe_wood_color
	mat_wood.roughness = 0.8

	# 1. Torso
	torso_node = Node3D.new()
	torso_node.name = "TorsoNode"
	torso_node.position = Vector3(0, 1.05, 0)
	add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var box_torso := BoxMesh.new()
	box_torso.size = Vector3(0.44, 0.60, 0.26)
	torso_mesh.mesh = box_torso
	torso_mesh.material_override = mat_tunic
	torso_node.add_child(torso_mesh)

	# Belt
	var belt_mesh := MeshInstance3D.new()
	var box_belt := BoxMesh.new()
	box_belt.size = Vector3(0.46, 0.08, 0.28)
	belt_mesh.mesh = box_belt
	belt_mesh.position = Vector3(0, -0.22, 0)
	belt_mesh.material_override = mat_belt
	torso_node.add_child(belt_mesh)

	# Carried Wooden Log (held horizontally in front of torso with both arms wrapped around it)
	carried_log_node = Node3D.new()
	carried_log_node.name = "CarriedLog"
	carried_log_node.position = Vector3(0, -0.04, -0.32)
	carried_log_node.visible = false
	torso_node.add_child(carried_log_node)

	var log_mesh := MeshInstance3D.new()
	var cyl_log := CylinderMesh.new()
	cyl_log.top_radius = 0.13
	cyl_log.bottom_radius = 0.13
	cyl_log.height = 1.45
	cyl_log.radial_segments = 12
	log_mesh.mesh = cyl_log
	log_mesh.rotation_degrees = Vector3(0, 0, 90)
	log_mesh.material_override = mat_wood
	carried_log_node.add_child(log_mesh)

	# End grain circles
	var mat_endgrain := StandardMaterial3D.new()
	mat_endgrain.albedo_color = Color(0.70, 0.55, 0.35)
	mat_endgrain.roughness = 0.9

	for end_sign in [-1.0, 1.0]:
		var end_cap := MeshInstance3D.new()
		var cap_cyl := CylinderMesh.new()
		cap_cyl.top_radius = 0.125
		cap_cyl.bottom_radius = 0.125
		cap_cyl.height = 0.02
		end_cap.mesh = cap_cyl
		end_cap.material_override = mat_endgrain
		end_cap.rotation_degrees = Vector3(0, 0, 90)
		end_cap.position = Vector3(end_sign * 0.725, 0, 0)
		carried_log_node.add_child(end_cap)

	# 2. Head (attached to torso or separate)
	head_node = Node3D.new()
	head_node.name = "HeadNode"
	head_node.position = Vector3(0, 1.52, 0)
	add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var box_head := BoxMesh.new()
	box_head.size = Vector3(0.28, 0.30, 0.28)
	head_mesh.mesh = box_head
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Face indicator / Brow (Forward direction is -Z)
	var face_mesh := MeshInstance3D.new()
	var box_face := BoxMesh.new()
	box_face.size = Vector3(0.22, 0.07, 0.05)
	face_mesh.mesh = box_face
	face_mesh.position = Vector3(0, 0.03, -0.145)
	face_mesh.material_override = mat_belt
	head_node.add_child(face_mesh)

	# Medieval cowl / Hood top
	var hood_mesh := MeshInstance3D.new()
	var box_hood := BoxMesh.new()
	box_hood.size = Vector3(0.31, 0.08, 0.31)
	hood_mesh.mesh = box_hood
	hood_mesh.position = Vector3(0, 0.16, 0)
	hood_mesh.material_override = mat_tunic
	head_node.add_child(hood_mesh)

	# 3. Left Arm (Shoulder pivot at -0.28, 1.25, 0)
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArm"
	left_arm_pivot.position = Vector3(-0.28, 1.25, 0)
	add_child(left_arm_pivot)

	var l_arm_mesh := MeshInstance3D.new()
	var box_arm := BoxMesh.new()
	box_arm.size = Vector3(0.12, 0.42, 0.12)
	l_arm_mesh.mesh = box_arm
	l_arm_mesh.position = Vector3(0, -0.21, 0)
	l_arm_mesh.material_override = mat_tunic
	left_arm_pivot.add_child(l_arm_mesh)

	var l_hand_mesh := MeshInstance3D.new()
	var box_hand := BoxMesh.new()
	box_hand.size = Vector3(0.11, 0.11, 0.11)
	l_hand_mesh.mesh = box_hand
	l_hand_mesh.position = Vector3(0, -0.45, 0)
	l_hand_mesh.material_override = mat_skin
	left_arm_pivot.add_child(l_hand_mesh)

	# Torch in Left Hand
	torch_mesh = Node3D.new()
	torch_mesh.name = "HandTorch"
	torch_mesh.position = Vector3(0, -0.45, -0.1)
	torch_mesh.visible = false
	left_arm_pivot.add_child(torch_mesh)

	var torch_stick := MeshInstance3D.new()
	var cyl_torch := CylinderMesh.new()
	cyl_torch.top_radius = 0.04
	cyl_torch.bottom_radius = 0.03
	cyl_torch.height = 0.55
	torch_stick.mesh = cyl_torch
	torch_stick.position = Vector3(0, 0.15, 0)
	torch_stick.material_override = mat_wood
	torch_mesh.add_child(torch_stick)

	var torch_flame := MeshInstance3D.new()
	var sph_flame := SphereMesh.new()
	sph_flame.radius = 0.09
	sph_flame.height = 0.18
	torch_flame.mesh = sph_flame
	torch_flame.position = Vector3(0, 0.42, 0)
	var mat_flame := StandardMaterial3D.new()
	mat_flame.albedo_color = Color(1.0, 0.55, 0.15)
	mat_flame.emission_enabled = true
	mat_flame.emission = Color(1.0, 0.6, 0.1)
	mat_flame.emission_energy_multiplier = 3.0
	torch_flame.material_override = mat_flame
	torch_mesh.add_child(torch_flame)

	# 4. Right Arm (Shoulder pivot at 0.28, 1.25, 0)
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArm"
	right_arm_pivot.position = Vector3(0.28, 1.25, 0)
	add_child(right_arm_pivot)

	var r_arm_mesh := MeshInstance3D.new()
	r_arm_mesh.mesh = box_arm
	r_arm_mesh.position = Vector3(0, -0.21, 0)
	r_arm_mesh.material_override = mat_tunic
	right_arm_pivot.add_child(r_arm_mesh)

	var r_hand_mesh := MeshInstance3D.new()
	r_hand_mesh.mesh = box_hand
	r_hand_mesh.position = Vector3(0, -0.45, 0)
	r_hand_mesh.material_override = mat_skin
	right_arm_pivot.add_child(r_hand_mesh)

	# Woodcutter's Axe in Right Hand
	axe_mesh = Node3D.new()
	axe_mesh.name = "HandAxe"
	axe_mesh.position = Vector3(0, -0.45, -0.05)
	axe_mesh.rotation_degrees = Vector3(20, 0, 0)
	right_arm_pivot.add_child(axe_mesh)

	var axe_handle := MeshInstance3D.new()
	var cyl_handle := CylinderMesh.new()
	cyl_handle.top_radius = 0.025
	cyl_handle.bottom_radius = 0.025
	cyl_handle.height = 0.65
	axe_handle.mesh = cyl_handle
	axe_handle.position = Vector3(0, 0.12, 0)
	axe_handle.material_override = mat_wood
	axe_mesh.add_child(axe_handle)

	var axe_head := MeshInstance3D.new()
	var box_blade := BoxMesh.new()
	box_blade.size = Vector3(0.04, 0.16, 0.22)
	axe_head.mesh = box_blade
	axe_head.position = Vector3(0, 0.38, -0.08)
	axe_head.material_override = mat_iron
	axe_mesh.add_child(axe_head)

	# 5. Left Leg (Hip pivot at -0.13, 0.72, 0)
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLeg"
	left_leg_pivot.position = Vector3(-0.13, 0.72, 0)
	add_child(left_leg_pivot)

	var l_leg_mesh := MeshInstance3D.new()
	var box_leg := BoxMesh.new()
	box_leg.size = Vector3(0.15, 0.52, 0.15)
	l_leg_mesh.mesh = box_leg
	l_leg_mesh.position = Vector3(0, -0.26, 0)
	l_leg_mesh.material_override = mat_tunic
	left_leg_pivot.add_child(l_leg_mesh)

	var l_boot_mesh := MeshInstance3D.new()
	var box_boot := BoxMesh.new()
	box_boot.size = Vector3(0.16, 0.14, 0.24)
	l_boot_mesh.mesh = box_boot
	l_boot_mesh.position = Vector3(0, -0.58, -0.04)
	l_boot_mesh.material_override = mat_boot
	left_leg_pivot.add_child(l_boot_mesh)

	# 6. Right Leg (Hip pivot at 0.13, 0.72, 0)
	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLeg"
	right_leg_pivot.position = Vector3(0.13, 0.72, 0)
	add_child(right_leg_pivot)

	var r_leg_mesh := MeshInstance3D.new()
	r_leg_mesh.mesh = box_leg
	r_leg_mesh.position = Vector3(0, -0.26, 0)
	r_leg_mesh.material_override = mat_tunic
	right_leg_pivot.add_child(r_leg_mesh)

	var r_boot_mesh := MeshInstance3D.new()
	r_boot_mesh.mesh = box_boot
	r_boot_mesh.position = Vector3(0, -0.58, -0.04)
	r_boot_mesh.material_override = mat_boot
	right_leg_pivot.add_child(r_boot_mesh)

## Updates procedural animation every physics frame
func update_animation(delta: float, horizontal_velocity: Vector3, is_grounded: bool, holding_torch: bool) -> void:
	has_torch = holding_torch

	if carried_log_node:
		carried_log_node.visible = is_carrying_log

	if axe_mesh:
		axe_mesh.visible = not is_carrying_log

	if torch_mesh:
		torch_mesh.visible = holding_torch and not is_carrying_log

	var horiz_speed := horizontal_velocity.length()

	# Handle chop/attack swing timer
	if is_chopping and not is_carrying_log:
		chop_timer += delta * 6.0
		if chop_timer >= PI:
			is_chopping = false
			chop_timer = 0.0
	else:
		is_chopping = false
		chop_timer = 0.0

	if is_grounded and horiz_speed > 0.15:
		# Walking / Sprinting stride cycle
		var anim_rate := clampf(horiz_speed * 1.8, 4.0, 14.0)
		walk_cycle += delta * anim_rate

		var leg_swing := sin(walk_cycle) * 0.65
		var arm_swing := sin(walk_cycle) * 0.55

		left_leg_pivot.rotation.x = leg_swing
		right_leg_pivot.rotation.x = -leg_swing

		if is_carrying_log:
			# Both arms wrapped horizontally around the wooden log
			var carry_bob := sin(walk_cycle * 2.0) * deg_to_rad(3.0)
			left_arm_pivot.rotation.x = deg_to_rad(-62) + carry_bob
			left_arm_pivot.rotation.y = deg_to_rad(28)
			left_arm_pivot.rotation.z = deg_to_rad(22)

			right_arm_pivot.rotation.x = deg_to_rad(-62) + carry_bob
			right_arm_pivot.rotation.y = deg_to_rad(-28)
			right_arm_pivot.rotation.z = deg_to_rad(-22)
		else:
			left_arm_pivot.rotation.y = 0.0
			right_arm_pivot.rotation.y = 0.0
			right_arm_pivot.rotation.z = 0.0

			# Right arm swings opposite to right leg unless chopping
			if not is_chopping:
				right_arm_pivot.rotation.x = -arm_swing
			else:
				right_arm_pivot.rotation.x = -deg_to_rad(65) + sin(chop_timer) * deg_to_rad(95)

			# Left arm swings unless holding torch
			if holding_torch:
				left_arm_pivot.rotation.x = deg_to_rad(-60)
				left_arm_pivot.rotation.z = deg_to_rad(15)
			else:
				left_arm_pivot.rotation.x = arm_swing
				left_arm_pivot.rotation.z = 0.0

		# Torso subtle vertical bob
		torso_node.position.y = 1.05 + absf(sin(walk_cycle * 2.0)) * 0.035
		head_node.position.y = 1.52 + absf(sin(walk_cycle * 2.0)) * 0.025
	elif not is_grounded:
		# Airborne / jumping pose
		walk_cycle = 0.0
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, deg_to_rad(25), delta * 8.0)
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, deg_to_rad(-15), delta * 8.0)

		if is_carrying_log:
			left_arm_pivot.rotation.x = deg_to_rad(-62)
			left_arm_pivot.rotation.y = deg_to_rad(28)
			left_arm_pivot.rotation.z = deg_to_rad(22)

			right_arm_pivot.rotation.x = deg_to_rad(-62)
			right_arm_pivot.rotation.y = deg_to_rad(-28)
			right_arm_pivot.rotation.z = deg_to_rad(-22)
		else:
			left_arm_pivot.rotation.y = 0.0
			right_arm_pivot.rotation.y = 0.0
			right_arm_pivot.rotation.z = 0.0

			if not is_chopping:
				right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, deg_to_rad(-40), delta * 8.0)
			if holding_torch:
				left_arm_pivot.rotation.x = deg_to_rad(-60)
				left_arm_pivot.rotation.z = deg_to_rad(15)
			else:
				left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, deg_to_rad(-40), delta * 8.0)

		torso_node.position.y = lerpf(torso_node.position.y, 1.05, delta * 8.0)
		head_node.position.y = lerpf(head_node.position.y, 1.52, delta * 8.0)
	else:
		# Idle pose: smooth return to neutral with subtle breathing
		walk_cycle = 0.0
		var time := Time.get_ticks_msec() * 0.002
		var breath := sin(time) * 0.012

		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, 0.0, delta * 8.0)
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, 0.0, delta * 8.0)

		if is_carrying_log:
			left_arm_pivot.rotation.x = deg_to_rad(-62) + breath * 1.5
			left_arm_pivot.rotation.y = deg_to_rad(28)
			left_arm_pivot.rotation.z = deg_to_rad(22)

			right_arm_pivot.rotation.x = deg_to_rad(-62) + breath * 1.5
			right_arm_pivot.rotation.y = deg_to_rad(-28)
			right_arm_pivot.rotation.z = deg_to_rad(-22)
		else:
			left_arm_pivot.rotation.y = lerpf(left_arm_pivot.rotation.y, 0.0, delta * 8.0)
			right_arm_pivot.rotation.y = lerpf(right_arm_pivot.rotation.y, 0.0, delta * 8.0)

			if not is_chopping:
				right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, deg_to_rad(10) + breath * 2.0, delta * 6.0)
				right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, 0.0, delta * 8.0)
			else:
				right_arm_pivot.rotation.x = -deg_to_rad(65) + sin(chop_timer) * deg_to_rad(95)

			if holding_torch:
				left_arm_pivot.rotation.x = deg_to_rad(-60)
				left_arm_pivot.rotation.z = deg_to_rad(15)
			else:
				left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, deg_to_rad(10) - breath * 2.0, delta * 6.0)
				left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, 0.0, delta * 8.0)

		torso_node.position.y = 1.05 + breath
		head_node.position.y = 1.52 + breath * 0.7

## Sets whether the settler is carrying a physical log in arms
func set_carrying_log(carrying: bool) -> void:
	is_carrying_log = carrying
	if carried_log_node:
		carried_log_node.visible = carrying
	if axe_mesh:
		axe_mesh.visible = not carrying
	if torch_mesh and has_torch:
		torch_mesh.visible = not carrying

## Triggers an axe chopping animation
func trigger_chop() -> void:
	if not is_carrying_log:
		is_chopping = true
		chop_timer = 0.0
