class_name FarmsteadGenerator
extends Node

## Procedural Medieval Bergen Farmstead Generator (Gård / Årestue cluster)
## Creates authentic 1360 Norwegian farmsteads on fertile lower shelves:
## - Lafteverk Årestue Farmhouse with central glowing stone hearth (firelight scares wolves)
## - Elevated Timber Stabbur (storehouse on carved pillars with rodent collars & stairs)
## - Split-rail Wooden Fences (traditional Skigard enclosing farmyard & pastures)
## - Crop Patches (tilled dark soil with rows of cabbage, barley, and turnips)
## - Stone Well (freshwater drinking source with wooden gantry, rope, and bucket)
## - Wood Chopping Block & Firewood Stacks
## - Hardworking Medieval Farmers (FarmerAI) performing daily chore routines

const FARMER_NAMES: Array[String] = [
	"Bonde Torstein", "Bonde Astrid", "Bonde Halvard", "Bonde Sigrid",
	"Bonde Einar", "Bonde Ragnhild", "Bonde Olav", "Bonde Ingrid"
]

const TUNIC_COLORS: Array[Color] = [
	Color(0.46, 0.33, 0.22), # Russet brown wool
	Color(0.32, 0.42, 0.28), # Moss green wool
	Color(0.72, 0.68, 0.62), # Oatmeal natural wool
	Color(0.28, 0.28, 0.32), # Peat charcoal wool
	Color(0.55, 0.26, 0.22)  # Madder red wool
]

## Assembles a complete farmstead cluster at specified location
static func create_farmstead(farm_id: int, origin: Vector3, farm_name: String, terrain_generator: BergenTerrainGenerator) -> Node3D:
	var farm_root := Node3D.new()
	farm_root.name = "Farmstead_%d_%s" % [farm_id, farm_name.replace(" ", "_")]
	farm_root.position = origin
	farm_root.add_to_group("farmstead")

	# Shared Materials
	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.42, 0.28, 0.16) # Weathered pine/spruce log
	mat_wood.roughness = 0.88

	var mat_wood_dark := StandardMaterial3D.new()
	mat_wood_dark.albedo_color = Color(0.30, 0.20, 0.12) # Tarred timber
	mat_wood_dark.roughness = 0.9

	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.46, 0.44, 0.42) # Slate & granite
	mat_stone.roughness = 0.92

	var mat_sod := StandardMaterial3D.new()
	mat_sod.albedo_color = Color(0.25, 0.40, 0.18) # Green turf/sod
	mat_sod.roughness = 0.95

	var mat_soil := StandardMaterial3D.new()
	mat_soil.albedo_color = Color(0.22, 0.17, 0.12) # Rich tilled garden humus
	mat_soil.roughness = 0.98

	# -------------------------------------------------------------------------
	# 1. Main Timber Farmhouse (Årestue)
	# -------------------------------------------------------------------------
	# Farmhouse placed slightly north of origin
	var farmhouse_offset := Vector3(-2.0, 0.0, -6.0)
	var farmhouse := BuildingAssembler.assemble_log_cabin(5.4, 6.0)
	farmhouse.name = "TimberFarmhouse_Arestue"
	farmhouse.position = farmhouse_offset
	farm_root.add_child(farmhouse)

	var hearth_world_pos := origin + farmhouse_offset + Vector3(0, 0.2, 0.2)

	# -------------------------------------------------------------------------
	# 2. Elevated Timber Stabbur (Storehouse on Stilts)
	# -------------------------------------------------------------------------
	var stabbur_offset := Vector3(9.5, 0.0, -4.5)
	var stabbur := _assemble_stabbur(4.0, 4.5, mat_wood, mat_wood_dark, mat_stone, mat_sod)
	stabbur.name = "TimberStorehouse_Stabbur"
	stabbur.position = stabbur_offset
	farm_root.add_child(stabbur)

	var stabbur_world_pos := origin + stabbur_offset

	# -------------------------------------------------------------------------
	# 3. Stone Freshwater Well
	# -------------------------------------------------------------------------
	var well_offset := Vector3(2.5, 0.0, 2.0)
	var well := _assemble_stone_well(mat_stone, mat_wood_dark)
	well.name = "StoneWell"
	well.position = well_offset
	farm_root.add_child(well)

	# -------------------------------------------------------------------------
	# 4. Wood Chopping Block & Firewood Stacks
	# -------------------------------------------------------------------------
	var wood_offset := Vector3(-7.5, 0.0, -1.0)
	var wood_area := _assemble_chopping_area(mat_wood, mat_wood_dark, mat_stone)
	wood_area.name = "WoodChoppingArea"
	wood_area.position = wood_offset
	farm_root.add_child(wood_area)

	var wood_world_pos := origin + wood_offset

	# -------------------------------------------------------------------------
	# 5. Crop Patches (Cabbage, Barley, Turnips)
	# -------------------------------------------------------------------------
	var crops_offset := Vector3(-8.0, 0.0, 8.0)
	var crop_patch := _assemble_crop_patch(7.0, 5.0, mat_soil, mat_wood_dark)
	crop_patch.name = "CropPatches"
	crop_patch.position = crops_offset
	farm_root.add_child(crop_patch)

	var crops_world_pos := origin + crops_offset

	# -------------------------------------------------------------------------
	# 6. Hay Storage & Feeder Rack
	# -------------------------------------------------------------------------
	var hay_offset := Vector3(8.0, 0.0, 7.0)
	var hay_area := _assemble_hay_rack(mat_wood_dark)
	hay_area.name = "HayStorageRack"
	hay_area.position = hay_offset
	farm_root.add_child(hay_area)

	var hay_world_pos := origin + hay_offset

	# -------------------------------------------------------------------------
	# 7. Split-Rail Wooden Fences (Pasture & Yard Enclosure)
	# -------------------------------------------------------------------------
	var fence_root := Node3D.new()
	fence_root.name = "SplitRailFences"
	farm_root.add_child(fence_root)

	# Enclose the pasture / farmyard with rustic post-and-rail wooden fences
	# North fence line
	_create_fence_line(fence_root, Vector3(-14.0, 0, -12.0), Vector3(14.0, 0, -12.0), mat_wood_dark)
	# East fence line
	_create_fence_line(fence_root, Vector3(14.0, 0, -12.0), Vector3(14.0, 0, 14.0), mat_wood_dark)
	# South fence line with 3m entrance gate opening
	_create_fence_line(fence_root, Vector3(14.0, 0, 14.0), Vector3(2.5, 0, 14.0), mat_wood_dark)
	_create_fence_line(fence_root, Vector3(-2.5, 0, 14.0), Vector3(-14.0, 0, 14.0), mat_wood_dark)
	# West fence line
	_create_fence_line(fence_root, Vector3(-14.0, 0, 14.0), Vector3(-14.0, 0, -12.0), mat_wood_dark)

	# -------------------------------------------------------------------------
	# 8. Farmers (2-4 Farmers per farmstead with authentic chores)
	# -------------------------------------------------------------------------
	# var farmer_count := 3
	# for f in range(farmer_count):
	# 	var farmer := FarmerAI.new()
	# 	farmer.name = "Farmer_%d_%d" % [farm_id, f]
	# 	var name_idx := (farm_id * 3 + f) % FARMER_NAMES.size()
	# 	farmer.set("farmer_name", FARMER_NAMES[name_idx])
	# 	farmer.set("tunic_color", TUNIC_COLORS[(farm_id * 2 + f) % TUNIC_COLORS.size()])
	# 	farmer.set("crop_pos", crops_world_pos)
	# 	farmer.set("wood_pos", wood_world_pos)
	# 	farmer.set("hay_pos", hay_world_pos)
	# 	farmer.set("hearth_pos", hearth_world_pos)
	# 	farmer.set("stabbur_pos", stabbur_world_pos)
	# 	farm_root.add_child(farmer)
	# 	var start_spots := [
	# 		crops_world_pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)),
	# 		wood_world_pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)),
	# 		hearth_world_pos + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
	# 	]
	# 	farmer.position = start_spots[f % start_spots.size()] - origin

	return farm_root

## Traditional Norwegian Stabbur (Elevated Storehouse on Stilts)
static func _assemble_stabbur(w: float, d: float, mat_wood: Material, mat_wood_dark: Material, mat_stone: Material, mat_sod: Material) -> StaticBody3D:
	var stabbur := StaticBody3D.new()
	stabbur.add_to_group("building")

	var stilt_h: float = 0.95
	var wall_h: float = 2.0
	var ridge_h: float = 3.3
	var half_w: float = w * 0.5
	var half_d: float = d * 0.5

	# 1. 4 Carved Wooden Pillars (Stabbestolper) with Rodent-Guard Caps (Stabbesteiner)
	var pillar_coords := [
		Vector3(-half_w + 0.3, 0, -half_d + 0.3),
		Vector3(half_w - 0.3, 0, -half_d + 0.3),
		Vector3(-half_w + 0.3, 0, half_d - 0.3),
		Vector3(half_w - 0.3, 0, half_d - 0.3)
	]

	for pos in pillar_coords:
		# Sturdy pillar post
		var post := MeshInstance3D.new()
		var cyl_post := CylinderMesh.new()
		cyl_post.top_radius = 0.16
		cyl_post.bottom_radius = 0.22
		cyl_post.height = stilt_h
		post.mesh = cyl_post
		post.position = pos + Vector3(0, stilt_h * 0.5, 0)
		post.material_override = mat_wood_dark
		stabbur.add_child(post)

		# Flared mushroom rodent-guard cap (stabbestein)
		var cap := MeshInstance3D.new()
		var cyl_cap := CylinderMesh.new()
		cyl_cap.top_radius = 0.34
		cyl_cap.bottom_radius = 0.24
		cyl_cap.height = 0.14
		cap.mesh = cyl_cap
		cap.position = pos + Vector3(0, stilt_h + 0.07, 0)
		cap.material_override = mat_stone
		stabbur.add_child(cap)

	# 2. Heavy Timber Sills & Floor Platform
	var floor_m := MeshInstance3D.new()
	var box_floor := BoxMesh.new()
	box_floor.size = Vector3(w + 0.2, 0.22, d + 0.2)
	floor_m.mesh = box_floor
	floor_m.position = Vector3(0, stilt_h + 0.18, 0)
	floor_m.material_override = mat_wood_dark
	stabbur.add_child(floor_m)

	# 3. Lafteverk Walls (Stacked horizontal timber logs)
	var log_count: int = 2
	var log_h: float = wall_h / float(log_count)
	var base_y: float = stilt_h + 0.29

	# Back wall (+Z)
	for i in range(log_count):
		var y_pos: float = base_y + (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(w + 0.5, log_h * 0.94, 0.3)
		log_m.mesh = log_box
		log_m.position = Vector3(0, y_pos, half_d)
		log_m.material_override = mat_wood
		stabbur.add_child(log_m)

	# Left & Right walls (-X and +X)
	for sign_x in [-1.0, 1.0]:
		for i in range(log_count):
			var y_pos: float = base_y + (i + 0.5) * log_h
			var log_m := MeshInstance3D.new()
			var log_box := BoxMesh.new()
			log_box.size = Vector3(0.3, log_h * 0.94, d + 0.5)
			log_m.mesh = log_box
			log_m.position = Vector3(sign_x * half_w, y_pos, 0)
			log_m.material_override = mat_wood
			stabbur.add_child(log_m)

	# Front wall (-Z) with heavy storehouse door
	for i in range(log_count):
		var y_pos: float = base_y + (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(w + 0.5, log_h * 0.94, 0.3)
		log_m.mesh = log_box
		log_m.position = Vector3(0, y_pos, -half_d)
		log_m.material_override = mat_wood
		stabbur.add_child(log_m)

	# Door slab on front
	var door_m := MeshInstance3D.new()
	var box_door := BoxMesh.new()
	box_door.size = Vector3(0.95, 1.6, 0.08)
	door_m.mesh = box_door
	door_m.position = Vector3(0, base_y + 0.85, -half_d - 0.16)
	door_m.material_override = mat_wood_dark
	stabbur.add_child(door_m)

	# 4. Access Wooden Steps (Trapp) up to the elevated doorway
	var step_count := 3
	for s in range(step_count):
		var step_m := MeshInstance3D.new()
		var box_step := BoxMesh.new()
		box_step.size = Vector3(1.1, 0.22, 0.38)
		step_m.mesh = box_step
		var sy: float = (s + 0.5) * (stilt_h / float(step_count))
		var sz: float = -half_d - 0.3 - (step_count - 1 - s) * 0.35
		step_m.position = Vector3(0, sy, sz)
		step_m.material_override = mat_wood_dark
		stabbur.add_child(step_m)

	# 5. Sod Roof (Torvtak)
	var roof_thick: float = 0.24
	var roof_len: float = d + 0.8
	var roof_slope_len: float = sqrt(pow(half_w + 0.4, 2.0) + pow(ridge_h - wall_h, 2.0))
	var pitch_rad: float = atan2(ridge_h - wall_h, half_w)

	for sign_x in [-1.0, 1.0]:
		var r_slope := MeshInstance3D.new()
		var r_box := BoxMesh.new()
		r_box.size = Vector3(roof_slope_len, roof_thick, roof_len)
		r_slope.mesh = r_box
		r_slope.material_override = mat_sod
		r_slope.position = Vector3(sign_x * (half_w * 0.5 + 0.08), base_y + wall_h + 0.55, 0)
		r_slope.rotation.z = sign_x * pitch_rad
		stabbur.add_child(r_slope)

	# 6. Solid Physics Collision Shape
	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(w + 0.4, wall_h + stilt_h + 1.2, d + 0.4)
	col.shape = box_col
	col.position = Vector3(0, (wall_h + stilt_h) * 0.5 + 0.4, 0)
	stabbur.add_child(col)

	return stabbur

## Stone Well with Timber Gantry, Rope, and Wooden Bucket (Freshwater source)
static func _assemble_stone_well(mat_stone: Material, mat_wood: Material) -> StaticBody3D:
	var well := FarmWellInteractable.new()
	well.add_to_group("stone_well")
	well.add_to_group("freshwater")

	# 1. Circular Stone Well Curb
	var curb := MeshInstance3D.new()
	var cyl_curb := CylinderMesh.new()
	cyl_curb.top_radius = 1.0
	cyl_curb.bottom_radius = 1.05
	cyl_curb.height = 0.85
	curb.mesh = cyl_curb
	curb.position.y = 0.42
	curb.material_override = mat_stone
	well.add_child(curb)

	# Well Water Surface inside
	var water_surf := MeshInstance3D.new()
	var cyl_water := CylinderMesh.new()
	cyl_water.top_radius = 0.72
	cyl_water.bottom_radius = 0.72
	cyl_water.height = 0.05
	water_surf.mesh = cyl_water
	water_surf.position.y = 0.35
	var mat_w := StandardMaterial3D.new()
	mat_w.albedo_color = Color(0.12, 0.28, 0.36, 0.9)
	mat_w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_w.roughness = 0.1
	water_surf.material_override = mat_w
	well.add_child(water_surf)

	# 2. Wooden Upright Posts & Crossbeam
	for sign_x in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box_post := BoxMesh.new()
		box_post.size = Vector3(0.14, 2.0, 0.14)
		post.mesh = box_post
		post.position = Vector3(sign_x * 0.88, 1.25, 0)
		post.material_override = mat_wood
		well.add_child(post)

	# Crossbeam
	var beam := MeshInstance3D.new()
	var box_beam := BoxMesh.new()
	box_beam.size = Vector3(2.0, 0.14, 0.14)
	beam.mesh = box_beam
	beam.position = Vector3(0, 2.2, 0)
	beam.material_override = mat_wood
	well.add_child(beam)

	# Pitched Shingle Rain Roof
	for sign_z in [-1.0, 1.0]:
		var roof := MeshInstance3D.new()
		var box_r := BoxMesh.new()
		box_r.size = Vector3(2.1, 0.08, 0.85)
		roof.mesh = box_r
		roof.position = Vector3(0, 2.45, sign_z * 0.35)
		roof.rotation.x = sign_z * deg_to_rad(30.0)
		roof.material_override = mat_wood
		well.add_child(roof)

	# Rope & Wooden Water Bucket
	var bucket := MeshInstance3D.new()
	var cyl_b := CylinderMesh.new()
	cyl_b.top_radius = 0.18
	cyl_b.bottom_radius = 0.14
	cyl_b.height = 0.32
	bucket.mesh = cyl_b
	bucket.position = Vector3(0.18, 0.95, 0.1)
	bucket.material_override = mat_wood
	well.add_child(bucket)

	# Collision
	var col := CollisionShape3D.new()
	var cyl_col := CylinderShape3D.new()
	cyl_col.radius = 1.15
	cyl_col.height = 2.4
	col.shape = cyl_col
	col.position.y = 1.2
	well.add_child(col)

	return well

## Crop Patches with Rows of Cabbage, Barley, and Turnips
static func _assemble_crop_patch(w: float, d: float, mat_soil: Material, mat_wood: Material) -> StaticBody3D:
	var patch := FarmCropInteractable.new()
	patch.add_to_group("crop_patch")

	# Tilled Soil Bed (raised fertile earth mound)
	var bed := MeshInstance3D.new()
	var box_bed := BoxMesh.new()
	box_bed.size = Vector3(w, 0.15, d)
	bed.mesh = box_bed
	bed.position.y = 0.075
	bed.material_override = mat_soil
	patch.add_child(bed)

	# Timber Bed Borders
	for sign_z in [-1.0, 1.0]:
		var border := MeshInstance3D.new()
		var box_b := BoxMesh.new()
		box_b.size = Vector3(w + 0.2, 0.18, 0.15)
		border.mesh = box_b
		border.position = Vector3(0, 0.09, sign_z * (d * 0.5 + 0.07))
		border.material_override = mat_wood
		patch.add_child(border)

	for sign_x in [-1.0, 1.0]:
		var border := MeshInstance3D.new()
		var box_b := BoxMesh.new()
		box_b.size = Vector3(0.15, 0.18, d)
		border.mesh = box_b
		border.position = Vector3(sign_x * (w * 0.5 + 0.07), 0.09, 0)
		border.material_override = mat_wood
		patch.add_child(border)

	# Materials for crops
	var mat_cabbage := StandardMaterial3D.new()
	mat_cabbage.albedo_color = Color(0.35, 0.58, 0.24) # Fresh cabbage green
	mat_cabbage.roughness = 0.7

	var mat_barley := StandardMaterial3D.new()
	mat_barley.albedo_color = Color(0.82, 0.72, 0.38) # Golden ripe barley
	mat_barley.roughness = 0.9

	var mat_turnip := StandardMaterial3D.new()
	mat_turnip.albedo_color = Color(0.24, 0.46, 0.20) # Dark turnip top green
	mat_turnip.roughness = 0.8

	# Row 1: Cabbages (Z = -1.5)
	for cx in range(-1, 2):
		var cab := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.22
		sph.height = 0.35
		cab.mesh = sph
		cab.position = Vector3(cx * 1.6, 0.25, -1.4)
		cab.material_override = mat_cabbage
		patch.add_child(cab)

	# Row 2: Barley (Z = 0.0)
	for bx in range(-2, 3):
		var stalk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.04
		cyl.height = 0.75
		stalk.mesh = cyl
		stalk.position = Vector3(bx * 1.1, 0.45, 0.0)
		stalk.rotation.z = deg_to_rad(sin(bx * 1.5) * 8.0)
		stalk.material_override = mat_barley
		patch.add_child(stalk)

	# Row 3: Turnips (Z = +1.4)
	for tx in range(-1, 2):
		var turnip := MeshInstance3D.new()
		var box_t := BoxMesh.new()
		box_t.size = Vector3(0.28, 0.35, 0.28)
		turnip.mesh = box_t
		turnip.position = Vector3(tx * 1.5, 0.24, 1.4)
		turnip.material_override = mat_turnip
		patch.add_child(turnip)

	# Low Collision Shape
	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(w + 0.3, 0.3, d + 0.3)
	col.shape = box_col
	col.position.y = 0.15
	patch.add_child(col)

	return patch

## Chopping Block, Wedge Axe, and Firewood Stacks
static func _assemble_chopping_area(mat_wood: Material, mat_wood_dark: Material, mat_stone: Material) -> Node3D:
	var area := Node3D.new()

	# Large Oak/Spruce Chopping Stump (Hoggestabbe)
	var stump_body := StaticBody3D.new()
	var stump := MeshInstance3D.new()
	var cyl_stump := CylinderMesh.new()
	cyl_stump.top_radius = 0.35
	cyl_stump.bottom_radius = 0.42
	cyl_stump.height = 0.75
	stump.mesh = cyl_stump
	stump.position.y = 0.375
	stump.material_override = mat_wood_dark
	stump_body.add_child(stump)

	# Small iron axe in stump
	var axe_head := MeshInstance3D.new()
	var box_axe := BoxMesh.new()
	box_axe.size = Vector3(0.04, 0.15, 0.18)
	axe_head.mesh = box_axe
	axe_head.position = Vector3(0, 0.82, 0)
	axe_head.rotation.x = deg_to_rad(15.0)
	axe_head.material_override = mat_stone
	stump_body.add_child(axe_head)

	var col := CollisionShape3D.new()
	var cyl_col := CylinderShape3D.new()
	cyl_col.radius = 0.45
	cyl_col.height = 0.8
	col.shape = cyl_col
	col.position.y = 0.4
	stump_body.add_child(col)
	area.add_child(stump_body)

	# Stacked Cords of Firewood
	var stack_m := MeshInstance3D.new()
	var stack_box := BoxMesh.new()
	stack_box.size = Vector3(0.6, 0.45, 0.85)
	stack_m.mesh = stack_box
	stack_m.position = Vector3(1.2, 0.22, -0.2)
	stack_m.material_override = mat_wood_dark
	area.add_child(stack_m)

	for log_i in range(3):
		var f_log := MeshInstance3D.new()
		var cyl_l := CylinderMesh.new()
		cyl_l.top_radius = 0.08
		cyl_l.bottom_radius = 0.08
		cyl_l.height = 0.8
		f_log.mesh = cyl_l
		f_log.rotation.z = deg_to_rad(90.0)
		f_log.position = Vector3(1.2, 0.5, -0.45 + log_i * 0.25)
		f_log.material_override = mat_wood
		area.add_child(f_log)

	return area

## Hay Storage & Animal Feeder Rack
static func _assemble_hay_rack(mat_wood: Material) -> Node3D:
	var rack := Node3D.new()

	# 4 Corner Posts
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var box_p := BoxMesh.new()
			box_p.size = Vector3(0.12, 1.4, 0.12)
			post.mesh = box_p
			post.position = Vector3(sign_x * 0.85, 0.7, sign_z * 0.5)
			post.material_override = mat_wood
			rack.add_child(post)

	# Horizontal Rails
	for sign_z in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var box_r := BoxMesh.new()
		box_r.size = Vector3(1.8, 0.08, 0.08)
		rail.mesh = box_r
		rail.position = Vector3(0, 1.1, sign_z * 0.5)
		rail.material_override = mat_wood
		rack.add_child(rail)

	# Hay Mound
	var hay_m := MeshInstance3D.new()
	var box_h := BoxMesh.new()
	box_h.size = Vector3(1.6, 0.85, 0.9)
	hay_m.mesh = box_h
	hay_m.position = Vector3(0, 0.45, 0)
	var mat_hay := StandardMaterial3D.new()
	mat_hay.albedo_color = Color(0.78, 0.68, 0.35)
	mat_hay.roughness = 0.95
	hay_m.material_override = mat_hay
	rack.add_child(hay_m)

	return rack

## Creates a split-rail fence line between two points
static func _create_fence_line(parent: Node3D, from_pos: Vector3, to_pos: Vector3, mat_wood: Material) -> void:
	var span_vec := to_pos - from_pos
	var total_len := span_vec.length()
	var dir := span_vec.normalized()

	var fence_seg := StaticBody3D.new()
	fence_seg.position = (from_pos + to_pos) * 0.5
	fence_seg.rotation.y = atan2(-dir.x, -dir.z)

	# Posts: start, mid, end
	var post_offsets := [-total_len * 0.5, 0.0, total_len * 0.5]
	for pz in post_offsets:
		var post := MeshInstance3D.new()
		var box_p := BoxMesh.new()
		box_p.size = Vector3(0.12, 1.3, 0.12)
		post.mesh = box_p
		post.position = Vector3(0, 0.65, pz)
		post.material_override = mat_wood
		fence_seg.add_child(post)

	# 2 Horizontal / Diagonal Split Rails spanning the length
	for r in [0.45, 0.95]:
		var rail := MeshInstance3D.new()
		var box_r := BoxMesh.new()
		box_r.size = Vector3(0.08, 0.08, total_len)
		rail.mesh = box_r
		rail.position = Vector3(0, r, 0)
		rail.material_override = mat_wood
		fence_seg.add_child(rail)

	# Solid physics collision
	var col := CollisionShape3D.new()
	var box_c := BoxShape3D.new()
	box_c.size = Vector3(0.3, 1.2, total_len)
	col.shape = box_c
	col.position.y = 0.6
	fence_seg.add_child(col)

	parent.add_child(fence_seg)
