class_name BoxManModel
extends Node3D

## Simple procedural gray box man model for the Bergen 1360 settler:
## - Torso with medieval wool tunic & belt
## - Detailed 3D Leather Backpack on back (rucksack, shoulder straps, brass buckles, rolled travel blanket)
## - Head with brow / visor indicating facing direction
## - Left & Right arms with hands holding equipped medieval survival tools:
##     [1] Woodcutter's Axe
##     [2] Water Bottle / Drinking Horn
##     [3] Hunting Knife
##     [4] Hunting Recurve Bow & Arrow
##     [5] Pine-tar Torch
## - Left & Right legs with boots
## - Procedural limb swing animations for walking, sprinting, jumping, idle breathing,
##   axe chopping, agile knife slashing, drinking from horn, and bow aiming & arrow draw.

enum EquippedItem {
	NONE = 0,
	AXE = 1,
	WATER_BOTTLE = 2,
	KNIFE = 3,
	BOW = 4,
	TORCH = 5,
	FISHING_LINE = 6
}

@export var tunic_color: Color = Color(0.46, 0.48, 0.52) # Slate grey wool
@export var skin_color: Color = Color(0.68, 0.68, 0.70)  # Light stone grey
@export var belt_color: Color = Color(0.24, 0.22, 0.20)  # Dark leather
@export var boot_color: Color = Color(0.28, 0.28, 0.30)  # Charcoal leather boots
@export var axe_wood_color: Color = Color(0.42, 0.28, 0.16)
@export var iron_color: Color = Color(0.65, 0.68, 0.72)
@export var leather_color: Color = Color(0.38, 0.24, 0.14) # Warm tanned rucksack leather
@export var brass_color: Color = Color(0.86, 0.72, 0.26)   # Brass buckles
@export var blanket_color: Color = Color(0.32, 0.40, 0.34) # Pine green woven wool bedroll

# Node references for animation
var torso_node: Node3D
var head_node: Node3D
var left_arm_pivot: Node3D
var right_arm_pivot: Node3D
var left_leg_pivot: Node3D
var right_leg_pivot: Node3D

# Item Meshes
var backpack_node: Node3D
var torch_mesh: Node3D
var axe_mesh: Node3D
var knife_mesh: Node3D
var water_bottle_mesh: Node3D
var bow_mesh: Node3D
var arrow_hand_mesh: Node3D
var carried_log_node: Node3D
var fishing_spool_mesh: Node3D

# State
var walk_cycle: float = 0.0
var chop_timer: float = 0.0
var is_chopping: bool = false
var knife_timer: float = 0.0
var is_knife_slashing: bool = false
var drink_timer: float = 0.0
var is_drinking: bool = false
var is_aiming_bow: bool = false
var bow_draw_progress: float = 0.0
var has_torch: bool = false
var is_carrying_log: bool = false
var equipped_item: int = EquippedItem.AXE

# Swimming & Mountain Climbing Animation States (Tasks 2 & 7)
var is_swimming: bool = false
var is_climbing: bool = false
var is_on_rope: bool = false
var swim_cycle: float = 0.0
var flutter_cycle: float = 0.0
var tread_cycle: float = 0.0
var climb_cycle: float = 0.0
var rope_cycle: float = 0.0

# Stage 2 Procedural Locomotion, Weight & Landing Squash Variables
var _last_global_y_rot: float = 0.0
var _prev_is_grounded: bool = true
var _prev_vert_vel: float = 0.0
var landing_compression: float = 0.0

func _ready() -> void:
	_build_box_man()

func _build_box_man() -> void:
	if torso_node != null:
		return

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
	mat_iron.metallic = 0.85
	mat_iron.roughness = 0.35

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = axe_wood_color
	mat_wood.roughness = 0.8

	var mat_leather := StandardMaterial3D.new()
	mat_leather.albedo_color = leather_color
	mat_leather.roughness = 0.72

	var mat_dark_leather := StandardMaterial3D.new()
	mat_dark_leather.albedo_color = Color(0.20, 0.13, 0.08)
	mat_dark_leather.roughness = 0.75

	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = brass_color
	mat_brass.metallic = 0.92
	mat_brass.roughness = 0.25

	var mat_blanket := StandardMaterial3D.new()
	mat_blanket.albedo_color = blanket_color
	mat_blanket.roughness = 0.95

	var mat_horn := StandardMaterial3D.new()
	mat_horn.albedo_color = Color(0.72, 0.65, 0.52)
	mat_horn.roughness = 0.45

	# =========================================================================
	# 1. Torso
	# =========================================================================
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

	# Belt around waist
	var belt_mesh := MeshInstance3D.new()
	var box_belt := BoxMesh.new()
	box_belt.size = Vector3(0.46, 0.08, 0.28)
	belt_mesh.mesh = box_belt
	belt_mesh.position = Vector3(0, -0.22, 0)
	belt_mesh.material_override = mat_belt
	torso_node.add_child(belt_mesh)

	# =========================================================================
	# 3D BACKPACK (Attached to Torso back at +Z)
	# =========================================================================
	_build_backpack(mat_leather, mat_dark_leather, mat_brass, mat_blanket, mat_horn, mat_wood, mat_iron)

	# Carried Wooden Log (held horizontally in front of torso)
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

	# =========================================================================
	# 2. Head
	# =========================================================================
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

	# Face indicator / Brow (Forward is -Z)
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

	# =========================================================================
	# 3. Left Arm (Shoulder pivot at -0.28, 1.25, 0)
	# =========================================================================
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

	# Pine-tar Torch in Left Hand (Slot 5)
	_build_torch(mat_wood)

	# Hunting Recurve Bow in Left Hand (Slot 4)
	_build_bow(mat_wood, mat_dark_leather)

	# =========================================================================
	# 4. Right Arm (Shoulder pivot at 0.28, 1.25, 0)
	# =========================================================================
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

	# Woodcutter's Axe in Right Hand (Slot 1)
	_build_axe(mat_wood, mat_iron)

	# Water Bottle / Drinking Horn in Right Hand (Slot 2)
	_build_water_bottle(mat_horn, mat_dark_leather, mat_brass)

	# Hunting Knife in Right Hand (Slot 3)
	_build_knife(mat_wood, mat_brass, mat_iron)

	# Arrow in Right Hand (held ready when Bow Slot 4 is active)
	_build_held_arrow(mat_wood, mat_iron)

	# Handline & Cod Jig Spool in Right Hand (Slot 6)
	_build_fishing_spool(mat_wood, mat_iron, mat_dark_leather)

	# =========================================================================
	# 5. Left Leg (Hip pivot at -0.13, 0.72, 0)
	# =========================================================================
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

	# =========================================================================
	# 6. Right Leg (Hip pivot at 0.13, 0.72, 0)
	# =========================================================================
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

	# Initialize item visibilities
	set_equipped_item(equipped_item)

## Builds 3D Leather Backpack with shoulder straps, brass buckles, and rolled travel blanket
func _build_backpack(mat_leather: Material, mat_dark_leather: Material, mat_brass: Material, mat_blanket: Material, mat_horn: Material, mat_wood: Material, mat_iron: Material) -> void:
	backpack_node = Node3D.new()
	backpack_node.name = "Backpack"
	torso_node.add_child(backpack_node)

	# 1. Main Rucksack Bag (attached to back of torso at +Z)
	var bag_main := MeshInstance3D.new()
	var box_bag := BoxMesh.new()
	box_bag.size = Vector3(0.36, 0.42, 0.22)
	bag_main.mesh = box_bag
	bag_main.position = Vector3(0.0, 0.02, 0.24)
	bag_main.name = "BagMain"
	bag_main.material_override = mat_leather
	backpack_node.add_child(bag_main)

	# Rucksack top flap
	var bag_flap := MeshInstance3D.new()
	bag_flap.name = "BagFlap"
	var box_flap := BoxMesh.new()
	box_flap.size = Vector3(0.37, 0.16, 0.24)
	bag_flap.mesh = box_flap
	bag_flap.position = Vector3(0.0, 0.16, 0.25)
	bag_flap.material_override = mat_dark_leather
	backpack_node.add_child(bag_flap)

	# Front external pouch
	var bag_pouch := MeshInstance3D.new()
	bag_pouch.name = "BagPouch"
	var box_pouch := BoxMesh.new()
	box_pouch.size = Vector3(0.28, 0.18, 0.08)
	bag_pouch.mesh = box_pouch
	bag_pouch.position = Vector3(0.0, -0.07, 0.36)
	bag_pouch.material_override = mat_leather
	backpack_node.add_child(bag_pouch)

	# 2. Side Pouches:
	# Left side pouch (Water horn reservoir holster)
	var left_pouch := MeshInstance3D.new()
	left_pouch.name = "LeftPouch"
	var box_lp := BoxMesh.new()
	box_lp.size = Vector3(0.09, 0.24, 0.14)
	left_pouch.mesh = box_lp
	left_pouch.position = Vector3(-0.21, -0.02, 0.23)
	left_pouch.material_override = mat_dark_leather
	backpack_node.add_child(left_pouch)

	# Stowed drinking horn in side pouch
	var stowed_horn := MeshInstance3D.new()
	stowed_horn.name = "StowedHorn"
	var cyl_horn := CylinderMesh.new()
	cyl_horn.top_radius = 0.038
	cyl_horn.bottom_radius = 0.016
	cyl_horn.height = 0.26
	cyl_horn.radial_segments = 8
	stowed_horn.mesh = cyl_horn
	stowed_horn.position = Vector3(-0.21, 0.09, 0.23)
	stowed_horn.rotation_degrees = Vector3(15, 0, -12)
	stowed_horn.material_override = mat_horn
	backpack_node.add_child(stowed_horn)

	# Right side pouch (Tool & Arrow Quiver pocket)
	var right_pouch := MeshInstance3D.new()
	right_pouch.name = "RightPouch"
	var box_rp := BoxMesh.new()
	box_rp.size = Vector3(0.09, 0.26, 0.14)
	right_pouch.mesh = box_rp
	right_pouch.position = Vector3(0.21, 0.0, 0.23)
	right_pouch.material_override = mat_dark_leather
	backpack_node.add_child(right_pouch)

	# Stowed arrows peeking out of quiver pouch
	for i in range(3):
		var arrow_quiv := MeshInstance3D.new()
		arrow_quiv.name = "QuiverArrow_%d" % i
		var cyl_arr := CylinderMesh.new()
		cyl_arr.top_radius = 0.008
		cyl_arr.bottom_radius = 0.008
		cyl_arr.height = 0.38
		arrow_quiv.mesh = cyl_arr
		arrow_quiv.position = Vector3(0.20 + (i - 1) * 0.025, 0.18, 0.23 + (i - 1) * 0.02)
		arrow_quiv.rotation_degrees = Vector3(randf_range(-6, 6), 0, randf_range(6, 16))
		arrow_quiv.material_override = mat_wood
		backpack_node.add_child(arrow_quiv)

	# 3. Shoulder Straps (wrapping over shoulders to chest)
	for sign_x in [-1.0, 1.0]:
		# Shoulder curve over top
		var strap_top := MeshInstance3D.new()
		strap_top.name = "StrapTop_%d" % int(sign_x)
		var box_st := BoxMesh.new()
		box_st.size = Vector3(0.065, 0.04, 0.32)
		strap_top.mesh = box_st
		strap_top.position = Vector3(sign_x * 0.15, 0.29, 0.02)
		strap_top.material_override = mat_dark_leather
		backpack_node.add_child(strap_top)

		# Front chest strap
		var strap_front := MeshInstance3D.new()
		strap_front.name = "StrapFront_%d" % int(sign_x)
		var box_sf := BoxMesh.new()
		box_sf.size = Vector3(0.06, 0.36, 0.035)
		strap_front.mesh = box_sf
		strap_front.position = Vector3(sign_x * 0.15, 0.08, -0.138)
		strap_front.material_override = mat_dark_leather
		backpack_node.add_child(strap_front)

	# Chest cross-strap connecting shoulder straps across sternum
	var chest_strap := MeshInstance3D.new()
	chest_strap.name = "ChestStrap"
	var box_cs := BoxMesh.new()
	box_cs.size = Vector3(0.24, 0.038, 0.025)
	chest_strap.mesh = box_cs
	chest_strap.position = Vector3(0.0, 0.12, -0.14)
	chest_strap.material_override = mat_dark_leather
	backpack_node.add_child(chest_strap)

	# 4. Brass Buckles
	# Main flap brass buckle
	var buckle_main := MeshInstance3D.new()
	buckle_main.name = "BuckleMain"
	var box_bm := BoxMesh.new()
	box_bm.size = Vector3(0.08, 0.07, 0.03)
	buckle_main.mesh = box_bm
	buckle_main.position = Vector3(0.0, 0.08, 0.365)
	buckle_main.material_override = mat_brass
	backpack_node.add_child(buckle_main)

	# Chest sternum brass buckle
	var buckle_chest := MeshInstance3D.new()
	buckle_chest.name = "BuckleChest"
	var box_bc := BoxMesh.new()
	box_bc.size = Vector3(0.05, 0.05, 0.02)
	buckle_chest.mesh = box_bc
	buckle_chest.position = Vector3(0.0, 0.12, -0.155)
	buckle_chest.material_override = mat_brass
	backpack_node.add_child(buckle_chest)

	# Lower pocket brass buckle
	var buckle_pouch := MeshInstance3D.new()
	buckle_pouch.name = "BucklePouch"
	var box_bp := BoxMesh.new()
	box_bp.size = Vector3(0.05, 0.05, 0.02)
	buckle_pouch.mesh = box_bp
	buckle_pouch.position = Vector3(0.0, -0.01, 0.405)
	buckle_pouch.material_override = mat_brass
	backpack_node.add_child(buckle_pouch)

	# 5. Rolled Travel Blanket on top of rucksack
	var blanket_roll := MeshInstance3D.new()
	blanket_roll.name = "BlanketRoll"
	var cyl_blanket := CylinderMesh.new()
	cyl_blanket.top_radius = 0.075
	cyl_blanket.bottom_radius = 0.075
	cyl_blanket.height = 0.44
	cyl_blanket.radial_segments = 14
	blanket_roll.mesh = cyl_blanket
	blanket_roll.rotation_degrees = Vector3(0, 0, 90)
	blanket_roll.position = Vector3(0.0, 0.28, 0.23)
	blanket_roll.material_override = mat_blanket
	backpack_node.add_child(blanket_roll)

	# Two dark leather bedroll binding straps holding the blanket roll down
	for sign_x in [-1.0, 1.0]:
		var strap_blanket := MeshInstance3D.new()
		strap_blanket.name = "BlanketStrap_%d" % int(sign_x)
		var cyl_bs := CylinderMesh.new()
		cyl_bs.top_radius = 0.082
		cyl_bs.bottom_radius = 0.082
		cyl_bs.height = 0.035
		cyl_bs.radial_segments = 12
		strap_blanket.mesh = cyl_bs
		strap_blanket.rotation_degrees = Vector3(0, 0, 90)
		strap_blanket.position = Vector3(sign_x * 0.13, 0.28, 0.23)
		strap_blanket.material_override = mat_dark_leather
		backpack_node.add_child(strap_blanket)

		# Mini brass buckle on each blanket strap
		var buckle_bs := MeshInstance3D.new()
		buckle_bs.name = "BlanketBuckle_%d" % int(sign_x)
		var box_bbs := BoxMesh.new()
		box_bbs.size = Vector3(0.035, 0.035, 0.02)
		buckle_bs.mesh = box_bbs
		buckle_bs.position = Vector3(sign_x * 0.13, 0.355, 0.23)
		buckle_bs.material_override = mat_brass
		backpack_node.add_child(buckle_bs)

func _build_axe(mat_wood: Material, mat_iron: Material) -> void:
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

func _build_water_bottle(mat_horn: Material, mat_strap: Material, mat_brass: Material) -> void:
	water_bottle_mesh = Node3D.new()
	water_bottle_mesh.name = "WaterBottle"
	water_bottle_mesh.position = Vector3(0, -0.48, -0.06)
	water_bottle_mesh.rotation_degrees = Vector3(-10, 0, 20)
	water_bottle_mesh.visible = false
	right_arm_pivot.add_child(water_bottle_mesh)

	# Drinking Horn / Flask body
	var horn_body := MeshInstance3D.new()
	var cyl_h := CylinderMesh.new()
	cyl_h.top_radius = 0.048
	cyl_h.bottom_radius = 0.018
	cyl_h.height = 0.28
	cyl_h.radial_segments = 10
	horn_body.mesh = cyl_h
	horn_body.material_override = mat_horn
	water_bottle_mesh.add_child(horn_body)

	# Brass collar ring around rim
	var rim_brass := MeshInstance3D.new()
	var cyl_rim := CylinderMesh.new()
	cyl_rim.top_radius = 0.052
	cyl_rim.bottom_radius = 0.052
	cyl_rim.height = 0.03
	rim_brass.mesh = cyl_rim
	rim_brass.position = Vector3(0, 0.13, 0)
	rim_brass.material_override = mat_brass
	water_bottle_mesh.add_child(rim_brass)

	# Wooden stopper plug
	var stopper := MeshInstance3D.new()
	var cyl_stop := CylinderMesh.new()
	cyl_stop.top_radius = 0.03
	cyl_stop.bottom_radius = 0.03
	cyl_stop.height = 0.04
	stopper.mesh = cyl_stop
	stopper.position = Vector3(0, 0.16, 0)
	var mat_plug := StandardMaterial3D.new()
	mat_plug.albedo_color = Color(0.48, 0.32, 0.18)
	stopper.material_override = mat_plug
	water_bottle_mesh.add_child(stopper)

	# Leather carry strap band
	var strap_band := MeshInstance3D.new()
	var cyl_sb := CylinderMesh.new()
	cyl_sb.top_radius = 0.045
	cyl_sb.bottom_radius = 0.045
	cyl_sb.height = 0.04
	strap_band.mesh = cyl_sb
	strap_band.position = Vector3(0, -0.02, 0)
	strap_band.material_override = mat_strap
	water_bottle_mesh.add_child(strap_band)

func _build_knife(mat_wood: Material, mat_brass: Material, mat_iron: Material) -> void:
	knife_mesh = Node3D.new()
	knife_mesh.name = "HuntingKnife"
	knife_mesh.position = Vector3(0, -0.46, -0.04)
	knife_mesh.rotation_degrees = Vector3(15, 0, 0)
	knife_mesh.visible = false
	right_arm_pivot.add_child(knife_mesh)

	# Birch wooden hilt / grip
	var hilt := MeshInstance3D.new()
	var cyl_hilt := CylinderMesh.new()
	cyl_hilt.top_radius = 0.022
	cyl_hilt.bottom_radius = 0.02
	cyl_hilt.height = 0.15
	cyl_hilt.radial_segments = 8
	hilt.mesh = cyl_hilt
	hilt.material_override = mat_wood
	knife_mesh.add_child(hilt)

	# Brass bolster / guard
	var guard := MeshInstance3D.new()
	var box_g := BoxMesh.new()
	box_g.size = Vector3(0.03, 0.02, 0.055)
	guard.mesh = box_g
	guard.position = Vector3(0, 0.08, 0)
	guard.material_override = mat_brass
	knife_mesh.add_child(guard)

	# Sharp iron blade (single-edge seax style)
	var blade := MeshInstance3D.new()
	var box_b := BoxMesh.new()
	box_b.size = Vector3(0.016, 0.24, 0.042)
	blade.mesh = box_b
	blade.position = Vector3(0, 0.20, -0.008)
	blade.material_override = mat_iron
	knife_mesh.add_child(blade)

func _build_bow(mat_wood: Material, mat_grip: Material) -> void:
	bow_mesh = Node3D.new()
	bow_mesh.name = "HuntingBow"
	bow_mesh.position = Vector3(0, -0.45, -0.08)
	bow_mesh.rotation_degrees = Vector3(0, 90, 0)
	bow_mesh.visible = false
	left_arm_pivot.add_child(bow_mesh)

	# Central handle grip
	var grip := MeshInstance3D.new()
	var cyl_g := CylinderMesh.new()
	cyl_g.top_radius = 0.025
	cyl_g.bottom_radius = 0.025
	cyl_g.height = 0.16
	grip.mesh = cyl_g
	grip.material_override = mat_grip
	bow_mesh.add_child(grip)

	# Upper limb (curved forward recurve)
	var upper_limb := MeshInstance3D.new()
	var cyl_ul := CylinderMesh.new()
	cyl_ul.top_radius = 0.016
	cyl_ul.bottom_radius = 0.024
	cyl_ul.height = 0.44
	upper_limb.mesh = cyl_ul
	upper_limb.position = Vector3(0.06, 0.28, 0)
	upper_limb.rotation_degrees = Vector3(0, 0, -18)
	upper_limb.material_override = mat_wood
	bow_mesh.add_child(upper_limb)

	# Lower limb (curved forward recurve)
	var lower_limb := MeshInstance3D.new()
	var cyl_ll := CylinderMesh.new()
	cyl_ll.top_radius = 0.024
	cyl_ll.bottom_radius = 0.016
	cyl_ll.height = 0.44
	lower_limb.mesh = cyl_ll
	lower_limb.position = Vector3(0.06, -0.28, 0)
	lower_limb.rotation_degrees = Vector3(0, 0, 18)
	lower_limb.material_override = mat_wood
	bow_mesh.add_child(lower_limb)

	# Bowstring (taut cord between upper and lower nocks)
	var string_mesh := MeshInstance3D.new()
	var cyl_s := CylinderMesh.new()
	cyl_s.top_radius = 0.003
	cyl_s.bottom_radius = 0.003
	cyl_s.height = 0.94
	string_mesh.mesh = cyl_s
	string_mesh.position = Vector3(0.12, 0, 0)
	var mat_string := StandardMaterial3D.new()
	mat_string.albedo_color = Color(0.92, 0.92, 0.88)
	string_mesh.material_override = mat_string
	bow_mesh.add_child(string_mesh)

func _build_held_arrow(mat_wood: Material, mat_iron: Material) -> void:
	arrow_hand_mesh = Node3D.new()
	arrow_hand_mesh.name = "HeldArrow"
	arrow_hand_mesh.position = Vector3(0, -0.45, 0)
	arrow_hand_mesh.visible = false
	right_arm_pivot.add_child(arrow_hand_mesh)

	var shaft := MeshInstance3D.new()
	var cyl_as := CylinderMesh.new()
	cyl_as.top_radius = 0.01
	cyl_as.bottom_radius = 0.01
	cyl_as.height = 0.68
	shaft.mesh = cyl_as
	shaft.position = Vector3(0, 0.22, 0)
	shaft.material_override = mat_wood
	arrow_hand_mesh.add_child(shaft)

	var head := MeshInstance3D.new()
	var box_h := BoxMesh.new()
	box_h.size = Vector3(0.02, 0.06, 0.035)
	head.mesh = box_h
	head.position = Vector3(0, 0.58, 0)
	head.material_override = mat_iron
	arrow_hand_mesh.add_child(head)

func _build_torch(mat_wood: Material) -> void:
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

func _build_fishing_spool(mat_wood: Material, mat_iron: Material, mat_line: Material) -> void:
	fishing_spool_mesh = Node3D.new()
	fishing_spool_mesh.name = "FishingSpool"
	fishing_spool_mesh.position = Vector3(0, -0.46, -0.06)
	fishing_spool_mesh.rotation_degrees = Vector3(15, 0, 10)
	fishing_spool_mesh.visible = false
	right_arm_pivot.add_child(fishing_spool_mesh)

	# 1. Wooden handline winder frame (H-shaped juksehjul)
	var spool_frame := MeshInstance3D.new()
	var box_frame := BoxMesh.new()
	box_frame.size = Vector3(0.04, 0.22, 0.12)
	spool_frame.mesh = box_frame
	spool_frame.material_override = mat_wood
	fishing_spool_mesh.add_child(spool_frame)

	# 2. Wound hemp / linen fishing line coil
	var line_coil := MeshInstance3D.new()
	var box_line := BoxMesh.new()
	box_line.size = Vector3(0.045, 0.14, 0.09)
	line_coil.mesh = box_line
	line_coil.material_override = mat_line
	fishing_spool_mesh.add_child(line_coil)

	# 3. Trailing line cord with small iron jig sinker (dreg / juksa)
	var trailing_line := MeshInstance3D.new()
	var cyl_tl := CylinderMesh.new()
	cyl_tl.top_radius = 0.003
	cyl_tl.bottom_radius = 0.003
	cyl_tl.height = 0.35
	trailing_line.mesh = cyl_tl
	trailing_line.position = Vector3(0, -0.22, 0)
	trailing_line.material_override = mat_line
	fishing_spool_mesh.add_child(trailing_line)

	var jig_sinker := MeshInstance3D.new()
	var cyl_jig := CylinderMesh.new()
	cyl_jig.top_radius = 0.012
	cyl_jig.bottom_radius = 0.004
	cyl_jig.height = 0.08
	jig_sinker.mesh = cyl_jig
	jig_sinker.position = Vector3(0, -0.40, 0)
	jig_sinker.material_override = mat_iron
	fishing_spool_mesh.add_child(jig_sinker)

## Changes active equipped item and updates 3D mesh visibility
func set_equipped_item(item_slot: int) -> void:
	equipped_item = item_slot
	_update_hand_item_visibility()

func _update_hand_item_visibility() -> void:
	if is_carrying_log:
		if axe_mesh: axe_mesh.visible = false
		if water_bottle_mesh: water_bottle_mesh.visible = false
		if knife_mesh: knife_mesh.visible = false
		if bow_mesh: bow_mesh.visible = false
		if arrow_hand_mesh: arrow_hand_mesh.visible = false
		if torch_mesh: torch_mesh.visible = false
		if fishing_spool_mesh: fishing_spool_mesh.visible = false
		return

	if axe_mesh:
		axe_mesh.visible = (equipped_item == EquippedItem.AXE)
	if water_bottle_mesh:
		water_bottle_mesh.visible = (equipped_item == EquippedItem.WATER_BOTTLE)
	if knife_mesh:
		knife_mesh.visible = (equipped_item == EquippedItem.KNIFE)
	if bow_mesh:
		bow_mesh.visible = (equipped_item == EquippedItem.BOW)
	if arrow_hand_mesh:
		arrow_hand_mesh.visible = (equipped_item == EquippedItem.BOW and is_aiming_bow)
	if torch_mesh:
		torch_mesh.visible = (equipped_item == EquippedItem.TORCH or has_torch)
	if fishing_spool_mesh:
		fishing_spool_mesh.visible = (equipped_item == EquippedItem.FISHING_LINE)

## Updates procedural animation every physics frame
func update_animation(delta: float, horizontal_velocity: Vector3, is_grounded: bool, holding_torch: bool, is_swimming: bool = false, is_climbing: bool = false, is_on_rope: bool = false, vertical_velocity: float = 0.0) -> void:
	has_torch = holding_torch
	self.is_swimming = is_swimming
	self.is_climbing = is_climbing
	self.is_on_rope = is_on_rope

	if carried_log_node:
		carried_log_node.visible = is_carrying_log

	_update_hand_item_visibility()

	# Stage 2: Landing impact detection and spring recovery
	if not _prev_is_grounded and is_grounded and _prev_vert_vel < -1.8:
		landing_compression = clampf(absf(_prev_vert_vel) * 0.018, 0.035, 0.12)
	_prev_is_grounded = is_grounded
	_prev_vert_vel = vertical_velocity
	landing_compression = lerpf(landing_compression, 0.0, delta * 11.0)

	var horiz_speed := horizontal_velocity.length()

	# 1. Update Action Timers
	if is_chopping and not is_carrying_log:
		chop_timer += delta * 6.5
		if chop_timer >= PI:
			is_chopping = false
			chop_timer = 0.0
	else:
		is_chopping = false
		chop_timer = 0.0

	if is_knife_slashing and not is_carrying_log:
		knife_timer += delta * 12.0
		if knife_timer >= PI:
			is_knife_slashing = false
			knife_timer = 0.0
	else:
		is_knife_slashing = false
		knife_timer = 0.0

	if is_drinking and not is_carrying_log:
		drink_timer += delta * 3.5
		if drink_timer >= PI:
			is_drinking = false
			drink_timer = 0.0
	else:
		is_drinking = false
		drink_timer = 0.0

	# 2. Movement / Swimming / Climbing / Idle Animation
	if is_swimming:
		if horiz_speed > 0.15:
			# Forward swimming stroke: prone torso, head up, crawl paddle, flutter kicks
			torso_node.rotation.x = lerp_angle(torso_node.rotation.x, deg_to_rad(65.0), delta * 7.0)
			torso_node.rotation.y = lerpf(torso_node.rotation.y, 0.0, delta * 7.0)
			torso_node.rotation.z = lerpf(torso_node.rotation.z, 0.0, delta * 7.0)
			head_node.rotation.x = lerp_angle(head_node.rotation.x, deg_to_rad(-42.0), delta * 7.0)

			var stroke_rate := clampf(horiz_speed * 2.4, 5.0, 9.5)
			swim_cycle += delta * stroke_rate
			flutter_cycle += delta * stroke_rate * 2.0

			# Arms paddling (alternating crawl stroke)
			left_arm_pivot.rotation.x = -deg_to_rad(70.0) + sin(swim_cycle) * deg_to_rad(55.0)
			left_arm_pivot.rotation.y = cos(swim_cycle) * deg_to_rad(28.0)
			left_arm_pivot.rotation.z = deg_to_rad(24.0) + sin(swim_cycle) * deg_to_rad(18.0)

			right_arm_pivot.rotation.x = -deg_to_rad(70.0) + sin(swim_cycle + PI) * deg_to_rad(55.0)
			right_arm_pivot.rotation.y = -cos(swim_cycle + PI) * deg_to_rad(28.0)
			right_arm_pivot.rotation.z = -deg_to_rad(24.0) - sin(swim_cycle + PI) * deg_to_rad(18.0)

			# Legs fluttering
			left_leg_pivot.rotation.x = deg_to_rad(14.0) + sin(flutter_cycle) * deg_to_rad(24.0)
			left_leg_pivot.rotation.y = 0.0
			left_leg_pivot.rotation.z = deg_to_rad(4.0)

			right_leg_pivot.rotation.x = deg_to_rad(14.0) - sin(flutter_cycle) * deg_to_rad(24.0)
			right_leg_pivot.rotation.y = 0.0
			right_leg_pivot.rotation.z = -deg_to_rad(4.0)

			torso_node.position.y = 1.05 + sin(swim_cycle * 2.0) * 0.04
			head_node.position.y = 1.52 + sin(swim_cycle * 2.0) * 0.03
		else:
			# Idle in water: treading water upright
			torso_node.rotation.x = lerp_angle(torso_node.rotation.x, deg_to_rad(22.0), delta * 5.0)
			torso_node.rotation.y = lerpf(torso_node.rotation.y, 0.0, delta * 5.0)
			torso_node.rotation.z = lerpf(torso_node.rotation.z, 0.0, delta * 5.0)
			head_node.rotation.x = lerp_angle(head_node.rotation.x, deg_to_rad(-18.0), delta * 5.0)

			tread_cycle += delta * 3.4
			left_arm_pivot.rotation.x = deg_to_rad(-24.0) + sin(tread_cycle) * deg_to_rad(16.0)
			left_arm_pivot.rotation.y = deg_to_rad(12.0)
			left_arm_pivot.rotation.z = deg_to_rad(36.0) + cos(tread_cycle) * deg_to_rad(15.0)

			right_arm_pivot.rotation.x = deg_to_rad(-24.0) + sin(tread_cycle) * deg_to_rad(16.0)
			right_arm_pivot.rotation.y = -deg_to_rad(12.0)
			right_arm_pivot.rotation.z = -deg_to_rad(36.0) - cos(tread_cycle) * deg_to_rad(15.0)

			left_leg_pivot.rotation.x = sin(tread_cycle) * deg_to_rad(18.0)
			left_leg_pivot.rotation.y = 0.0
			left_leg_pivot.rotation.z = deg_to_rad(6.0)

			right_leg_pivot.rotation.x = -sin(tread_cycle) * deg_to_rad(18.0)
			right_leg_pivot.rotation.y = 0.0
			right_leg_pivot.rotation.z = -deg_to_rad(6.0)

			torso_node.position.y = 1.05 + sin(tread_cycle) * 0.03
			head_node.position.y = 1.52 + sin(tread_cycle) * 0.02
	elif is_on_rope:
		# Rope climbing & rappelling
		torso_node.rotation.x = lerp_angle(torso_node.rotation.x, -deg_to_rad(14.0), delta * 8.0)
		torso_node.rotation.y = lerpf(torso_node.rotation.y, 0.0, delta * 8.0)
		torso_node.rotation.z = lerpf(torso_node.rotation.z, 0.0, delta * 8.0)
		head_node.rotation.x = lerp_angle(head_node.rotation.x, deg_to_rad(-22.0), delta * 8.0)

		var vert_speed := horizontal_velocity.length()
		rope_cycle += delta * (6.5 if vert_speed > 0.1 else 0.0)
		var hand_shift := sin(rope_cycle) * deg_to_rad(18.0)

		left_arm_pivot.rotation.x = -deg_to_rad(105.0) + hand_shift
		left_arm_pivot.rotation.y = deg_to_rad(16.0)
		left_arm_pivot.rotation.z = deg_to_rad(22.0)

		right_arm_pivot.rotation.x = -deg_to_rad(85.0) - hand_shift
		right_arm_pivot.rotation.y = -deg_to_rad(16.0)
		right_arm_pivot.rotation.z = -deg_to_rad(22.0)

		left_leg_pivot.rotation.x = deg_to_rad(28.0) - sin(rope_cycle) * deg_to_rad(10.0)
		left_leg_pivot.rotation.y = 0.0
		left_leg_pivot.rotation.z = deg_to_rad(10.0)

		right_leg_pivot.rotation.x = deg_to_rad(28.0) + sin(rope_cycle) * deg_to_rad(10.0)
		right_leg_pivot.rotation.y = 0.0
		right_leg_pivot.rotation.z = -deg_to_rad(10.0)

		torso_node.position.y = 1.05
		head_node.position.y = 1.52
	elif is_climbing:
		# Freeform rock climbing
		torso_node.rotation.x = lerp_angle(torso_node.rotation.x, 0.0, delta * 8.0)
		torso_node.rotation.y = lerpf(torso_node.rotation.y, 0.0, delta * 8.0)
		torso_node.rotation.z = lerpf(torso_node.rotation.z, 0.0, delta * 8.0)
		head_node.rotation.x = lerp_angle(head_node.rotation.x, deg_to_rad(-24.0), delta * 8.0)

		var climb_spd := horizontal_velocity.length()
		climb_cycle += delta * (6.8 if climb_spd > 0.1 else 0.0)
		var reach := sin(climb_cycle) * deg_to_rad(26.0)

		left_arm_pivot.rotation.x = -deg_to_rad(125.0) + reach
		left_arm_pivot.rotation.y = deg_to_rad(18.0)
		left_arm_pivot.rotation.z = deg_to_rad(18.0)

		right_arm_pivot.rotation.x = -deg_to_rad(125.0) - reach
		right_arm_pivot.rotation.y = -deg_to_rad(18.0)
		right_arm_pivot.rotation.z = -deg_to_rad(18.0)

		left_leg_pivot.rotation.x = deg_to_rad(24.0) - reach * 0.65
		left_leg_pivot.rotation.y = 0.0
		left_leg_pivot.rotation.z = deg_to_rad(12.0)

		right_leg_pivot.rotation.x = deg_to_rad(24.0) + reach * 0.65
		right_leg_pivot.rotation.y = 0.0
		right_leg_pivot.rotation.z = -deg_to_rad(12.0)

		torso_node.position.y = 1.05
		head_node.position.y = 1.52
	else:
		# Stage 2 Procedural Torso Banking & Acceleration Lean
		var target_roll: float = 0.0
		var target_pitch: float = 0.0

		if is_grounded and horiz_speed > 0.2:
			var current_y_rot := global_rotation.y
			var turn_rate := (current_y_rot - _last_global_y_rot) / maxf(delta, 0.001)
			_last_global_y_rot = current_y_rot
			turn_rate = wrapf(turn_rate, -PI, PI)

			# Roll into turn (lean into curve)
			target_roll = clampf(-turn_rate * 0.22, -deg_to_rad(8.0), deg_to_rad(8.0))

			# Pitch lean forward during sprint and brisk walking
			var sprint_ratio := clampf((horiz_speed - 3.5) / 3.5, 0.0, 1.0)
			target_pitch = deg_to_rad(2.0 + 6.0 * sprint_ratio)
		else:
			_last_global_y_rot = global_rotation.y

		torso_node.rotation.x = lerp_angle(torso_node.rotation.x, target_pitch, delta * 8.0)
		torso_node.rotation.y = lerp_angle(torso_node.rotation.y, 0.0, delta * 8.0)
		torso_node.rotation.z = lerp_angle(torso_node.rotation.z, target_roll, delta * 8.0)
		head_node.rotation.x = lerp_angle(head_node.rotation.x, -target_pitch * 0.35, delta * 8.0)
		head_node.rotation.y = lerp_angle(head_node.rotation.y, 0.0, delta * 8.0)
		head_node.rotation.z = lerp_angle(head_node.rotation.z, -target_roll * 0.45, delta * 8.0)

		# Leg flare on landing impact squash
		left_leg_pivot.rotation.z = landing_compression * 0.35
		right_leg_pivot.rotation.z = -landing_compression * 0.35

		var base_torso_y := 1.05 - landing_compression
		var base_head_y := 1.52 - landing_compression * 0.75

		if is_grounded and horiz_speed > 0.15:
			# Walking / Sprinting stride cycle synced to ground velocity
			var anim_rate := clampf(horiz_speed * 2.2, 4.0, 15.0)
			walk_cycle += delta * anim_rate

			var leg_swing := sin(walk_cycle) * 0.65
			var arm_swing := sin(walk_cycle) * 0.55

			left_leg_pivot.rotation.x = leg_swing
			right_leg_pivot.rotation.x = -leg_swing

			if is_carrying_log:
				_apply_log_carry_pose(walk_cycle)
			else:
				_apply_item_poses(arm_swing, delta, false)

			# Torso subtle vertical bobbing
			torso_node.position.y = base_torso_y + absf(sin(walk_cycle * 2.0)) * 0.035
			head_node.position.y = base_head_y + absf(sin(walk_cycle * 2.0)) * 0.025
		elif not is_grounded:
			# Airborne / jumping pose
			walk_cycle = 0.0
			left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, deg_to_rad(25), delta * 8.0)
			right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, deg_to_rad(-15), delta * 8.0)

			if is_carrying_log:
				_apply_log_carry_pose(0.0)
			else:
				_apply_item_poses(0.0, delta, true)

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
				_apply_log_carry_pose(0.0, breath)
			else:
				_apply_item_poses(0.0, delta, false, breath)

			torso_node.position.y = base_torso_y + breath
			head_node.position.y = base_head_y + breath * 0.7

func _apply_log_carry_pose(cycle: float, breath: float = 0.0) -> void:
	var bob := sin(cycle * 2.0) * deg_to_rad(3.0) + breath * 1.5
	left_arm_pivot.rotation.x = deg_to_rad(-62) + bob
	left_arm_pivot.rotation.y = deg_to_rad(28)
	left_arm_pivot.rotation.z = deg_to_rad(22)

	right_arm_pivot.rotation.x = deg_to_rad(-62) + bob
	right_arm_pivot.rotation.y = deg_to_rad(-28)
	right_arm_pivot.rotation.z = deg_to_rad(-22)

func _apply_item_poses(arm_swing: float, delta: float, is_airborne: bool, breath: float = 0.0) -> void:
	# =======================
	# Left Arm Handling
	# =======================
	if is_aiming_bow and equipped_item == EquippedItem.BOW:
		# Bow Aim Pose: Left arm extended forward pointing bow
		left_arm_pivot.rotation.x = lerp_angle(left_arm_pivot.rotation.x, deg_to_rad(-82), delta * 14.0)
		left_arm_pivot.rotation.y = lerp_angle(left_arm_pivot.rotation.y, deg_to_rad(18), delta * 14.0)
		left_arm_pivot.rotation.z = lerp_angle(left_arm_pivot.rotation.z, deg_to_rad(-12), delta * 14.0)
	elif equipped_item == EquippedItem.TORCH or has_torch:
		# Torch held high
		left_arm_pivot.rotation.x = lerp_angle(left_arm_pivot.rotation.x, deg_to_rad(-60), delta * 10.0)
		left_arm_pivot.rotation.y = lerp_angle(left_arm_pivot.rotation.y, 0.0, delta * 8.0)
		left_arm_pivot.rotation.z = lerp_angle(left_arm_pivot.rotation.z, deg_to_rad(15), delta * 8.0)
	else:
		left_arm_pivot.rotation.y = lerp_angle(left_arm_pivot.rotation.y, 0.0, delta * 8.0)
		left_arm_pivot.rotation.z = lerp_angle(left_arm_pivot.rotation.z, 0.0, delta * 8.0)
		if is_airborne:
			left_arm_pivot.rotation.x = lerp_angle(left_arm_pivot.rotation.x, deg_to_rad(-35), delta * 8.0)
		elif arm_swing != 0.0:
			left_arm_pivot.rotation.x = arm_swing
		else:
			left_arm_pivot.rotation.x = lerp_angle(left_arm_pivot.rotation.x, deg_to_rad(8) - breath * 2.0, delta * 6.0)

	# =======================
	# Right Arm Handling
	# =======================
	if is_aiming_bow and equipped_item == EquippedItem.BOW:
		# Bow Arrow Draw Pose: Right arm pulls arrow back towards chin / cheek
		var draw_pull := bow_draw_progress * deg_to_rad(28)
		right_arm_pivot.rotation.x = lerp_angle(right_arm_pivot.rotation.x, deg_to_rad(-72) - draw_pull, delta * 14.0)
		right_arm_pivot.rotation.y = lerp_angle(right_arm_pivot.rotation.y, deg_to_rad(-32), delta * 14.0)
		right_arm_pivot.rotation.z = lerp_angle(right_arm_pivot.rotation.z, deg_to_rad(45), delta * 14.0)
	elif is_drinking:
		# Drinking motion: bring bottle to mouth
		var sip_curve := sin(drink_timer)
		right_arm_pivot.rotation.x = lerp_angle(right_arm_pivot.rotation.x, deg_to_rad(-110) * sip_curve, delta * 12.0)
		right_arm_pivot.rotation.y = lerp_angle(right_arm_pivot.rotation.y, deg_to_rad(-24) * sip_curve, delta * 12.0)
		right_arm_pivot.rotation.z = lerp_angle(right_arm_pivot.rotation.z, deg_to_rad(30) * sip_curve, delta * 12.0)
		head_node.rotation.x = lerp_angle(head_node.rotation.x, deg_to_rad(-16) * sip_curve, delta * 10.0)
	elif is_knife_slashing:
		# Fast agile knife slash
		var slash := sin(knife_timer)
		right_arm_pivot.rotation.x = -deg_to_rad(55) + slash * deg_to_rad(85)
		right_arm_pivot.rotation.y = -slash * deg_to_rad(40)
		right_arm_pivot.rotation.z = slash * deg_to_rad(35)
	elif is_chopping:
		# Heavy axe chop
		var chop := sin(chop_timer)
		right_arm_pivot.rotation.x = -deg_to_rad(65) + chop * deg_to_rad(95)
		right_arm_pivot.rotation.y = 0.0
		right_arm_pivot.rotation.z = 0.0
	elif equipped_item == EquippedItem.FISHING_LINE:
		# Handline jigging posture: hold arm forward with rhythmic gentle bobbing
		var jig_bob := sin(Time.get_ticks_msec() * 0.005) * deg_to_rad(6.0)
		right_arm_pivot.rotation.x = lerp_angle(right_arm_pivot.rotation.x, deg_to_rad(-45) + jig_bob, delta * 8.0)
		right_arm_pivot.rotation.y = lerp_angle(right_arm_pivot.rotation.y, deg_to_rad(-12), delta * 8.0)
		right_arm_pivot.rotation.z = lerp_angle(right_arm_pivot.rotation.z, deg_to_rad(10), delta * 8.0)
	else:
		right_arm_pivot.rotation.y = lerp_angle(right_arm_pivot.rotation.y, 0.0, delta * 8.0)
		right_arm_pivot.rotation.z = lerp_angle(right_arm_pivot.rotation.z, 0.0, delta * 8.0)
		if is_airborne:
			right_arm_pivot.rotation.x = lerp_angle(right_arm_pivot.rotation.x, deg_to_rad(-35), delta * 8.0)
		elif arm_swing != 0.0:
			right_arm_pivot.rotation.x = -arm_swing
		else:
			right_arm_pivot.rotation.x = lerp_angle(right_arm_pivot.rotation.x, deg_to_rad(10) + breath * 2.0, delta * 6.0)

## Sets whether the settler is carrying a physical log in arms
func set_carrying_log(carrying: bool) -> void:
	is_carrying_log = carrying
	if carried_log_node:
		carried_log_node.visible = carrying
	_update_hand_item_visibility()

## Triggers an axe chopping animation (Slot 1)
func trigger_chop() -> void:
	if not is_carrying_log:
		is_chopping = true
		chop_timer = 0.0

## Triggers an agile knife slash animation (Slot 3)
func trigger_knife_slash() -> void:
	if not is_carrying_log:
		is_knife_slashing = true
		knife_timer = 0.0

## Triggers drinking animation (Slot 2)
func trigger_drink() -> void:
	if not is_carrying_log:
		is_drinking = true
		drink_timer = 0.0

## Triggers fish catch reel-in animation (Slot 6)
func trigger_fish_catch() -> void:
	if not is_carrying_log:
		is_knife_slashing = true
		knife_timer = 0.0

## Updates bow aiming and draw strength (Slot 4)
func set_bow_aim(aiming: bool, draw_progress: float = 0.0) -> void:
	is_aiming_bow = aiming
	bow_draw_progress = clampf(draw_progress, 0.0, 1.0)
	if arrow_hand_mesh:
		arrow_hand_mesh.visible = (equipped_item == EquippedItem.BOW and aiming)
