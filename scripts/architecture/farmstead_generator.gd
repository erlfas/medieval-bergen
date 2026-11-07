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
	# 7. Traditional Bloomery Furnace & Smithing Anvil (Blæsterovn)
	# -------------------------------------------------------------------------
	if farm_id == 0 or farm_id == 1:
		var furnace := BloomeryFurnaceInteractable.new()
		furnace.name = "BloomeryFurnace_%d" % farm_id
		furnace.position = Vector3(-6.5, 0.0, -6.5)
		farm_root.add_child(furnace)

	# -------------------------------------------------------------------------
	# 8. Split-Rail Wooden Fences (Pasture & Yard Enclosure)
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

	# Compound stilts mesh
	var st_stilts := SurfaceTool.new()
	st_stilts.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_stilts.set_material(mat_wood_dark)
	var cyl_post := CylinderMesh.new()
	cyl_post.top_radius = 0.16
	cyl_post.bottom_radius = 0.22
	cyl_post.height = stilt_h
	for pos in pillar_coords:
		st_stilts.append_from(cyl_post, 0, Transform3D(Basis(), pos + Vector3(0, stilt_h * 0.5, 0)))
	st_stilts.generate_tangents()
	var stilts_mi := MeshInstance3D.new()
	stilts_mi.name = "StiltsCompoundMesh"
	stilts_mi.mesh = st_stilts.commit()
	stabbur.add_child(stilts_mi)

	# Compound rodent collar stones mesh
	var st_caps := SurfaceTool.new()
	st_caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_caps.set_material(mat_stone)
	var cyl_cap := CylinderMesh.new()
	cyl_cap.top_radius = 0.34
	cyl_cap.bottom_radius = 0.24
	cyl_cap.height = 0.14
	for pos in pillar_coords:
		st_caps.append_from(cyl_cap, 0, Transform3D(Basis(), pos + Vector3(0, stilt_h + 0.07, 0)))
	st_caps.generate_tangents()
	var caps_mi := MeshInstance3D.new()
	caps_mi.name = "CapsCompoundMesh"
	caps_mi.mesh = st_caps.commit()
	stabbur.add_child(caps_mi)

	# 2. Heavy Timber Sills & Floor Platform
	var floor_m := MeshInstance3D.new()
	var box_floor := BoxMesh.new()
	box_floor.size = Vector3(w + 0.2, 0.22, d + 0.2)
	floor_m.mesh = box_floor
	floor_m.position = Vector3(0, stilt_h + 0.18, 0)
	floor_m.material_override = mat_wood_dark
	stabbur.add_child(floor_m)

	# 3. Lafteverk Walls (Stacked horizontal timber logs - compound mesh)
	var log_count: int = 2
	var log_h: float = wall_h / float(log_count)
	var base_y: float = stilt_h + 0.29

	var st_walls := SurfaceTool.new()
	st_walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_walls.set_material(mat_wood)

	var log_box_z := BoxMesh.new()
	log_box_z.size = Vector3(w + 0.5, log_h * 0.94, 0.3)
	for i in range(log_count):
		var y_pos: float = base_y + (i + 0.5) * log_h
		st_walls.append_from(log_box_z, 0, Transform3D(Basis(), Vector3(0, y_pos, half_d)))
		st_walls.append_from(log_box_z, 0, Transform3D(Basis(), Vector3(0, y_pos, -half_d)))

	var log_box_x := BoxMesh.new()
	log_box_x.size = Vector3(0.3, log_h * 0.94, d + 0.5)
	for sign_x in [-1.0, 1.0]:
		for i in range(log_count):
			var y_pos: float = base_y + (i + 0.5) * log_h
			st_walls.append_from(log_box_x, 0, Transform3D(Basis(), Vector3(sign_x * half_w, y_pos, 0)))

	st_walls.generate_tangents()
	var walls_mi := MeshInstance3D.new()
	walls_mi.name = "StabburWallsCompoundMesh"
	walls_mi.mesh = st_walls.commit()
	stabbur.add_child(walls_mi)

	# 4. Access Wooden Steps (Trapp) & Doorway
	var st_door_steps := SurfaceTool.new()
	st_door_steps.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_door_steps.set_material(mat_wood_dark)

	var box_door := BoxMesh.new()
	box_door.size = Vector3(0.95, 1.6, 0.08)
	st_door_steps.append_from(box_door, 0, Transform3D(Basis(), Vector3(0, base_y + 0.85, -half_d - 0.16)))

	var step_count := 3
	var box_step := BoxMesh.new()
	box_step.size = Vector3(1.1, 0.22, 0.38)
	for s in range(step_count):
		var sy: float = (s + 0.5) * (stilt_h / float(step_count))
		var sz: float = -half_d - 0.3 - (step_count - 1 - s) * 0.35
		st_door_steps.append_from(box_step, 0, Transform3D(Basis(), Vector3(0, sy, sz)))

	st_door_steps.generate_tangents()
	var door_steps_mi := MeshInstance3D.new()
	door_steps_mi.name = "DoorStepsCompoundMesh"
	door_steps_mi.mesh = st_door_steps.commit()
	stabbur.add_child(door_steps_mi)

	# 5. Sod Roof (Torvtak - compound slopes)
	var roof_thick: float = 0.24
	var roof_len: float = d + 0.8
	var roof_slope_len: float = sqrt(pow(half_w + 0.4, 2.0) + pow(ridge_h - wall_h, 2.0))
	var pitch_rad: float = atan2(ridge_h - wall_h, half_w)

	var st_roof := SurfaceTool.new()
	st_roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_roof.set_material(mat_sod)
	var r_box := BoxMesh.new()
	r_box.size = Vector3(roof_slope_len, roof_thick, roof_len)
	for sign_x in [-1.0, 1.0]:
		var rot_basis := Basis(Vector3.FORWARD, sign_x * pitch_rad)
		var xform := Transform3D(rot_basis, Vector3(sign_x * (half_w * 0.5 + 0.08), base_y + wall_h + 0.55, 0))
		st_roof.append_from(r_box, 0, xform)

	st_roof.generate_tangents()
	var roof_mi := MeshInstance3D.new()
	roof_mi.name = "StabburRoofCompoundMesh"
	roof_mi.mesh = st_roof.commit()
	stabbur.add_child(roof_mi)

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

	# 2. Compound Timber Gantry (Posts, Beam, Roof, Bucket)
	var st_gantry := SurfaceTool.new()
	st_gantry.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_gantry.set_material(mat_wood)

	var box_post := BoxMesh.new()
	box_post.size = Vector3(0.14, 2.0, 0.14)
	for sign_x in [-1.0, 1.0]:
		st_gantry.append_from(box_post, 0, Transform3D(Basis(), Vector3(sign_x * 0.88, 1.25, 0)))

	var box_beam := BoxMesh.new()
	box_beam.size = Vector3(2.0, 0.14, 0.14)
	st_gantry.append_from(box_beam, 0, Transform3D(Basis(), Vector3(0, 2.2, 0)))

	var box_r := BoxMesh.new()
	box_r.size = Vector3(2.1, 0.08, 0.85)
	for sign_z in [-1.0, 1.0]:
		var basis_r := Basis(Vector3.RIGHT, sign_z * deg_to_rad(30.0))
		st_gantry.append_from(box_r, 0, Transform3D(basis_r, Vector3(0, 2.45, sign_z * 0.35)))

	var cyl_b := CylinderMesh.new()
	cyl_b.top_radius = 0.18
	cyl_b.bottom_radius = 0.14
	cyl_b.height = 0.32
	st_gantry.append_from(cyl_b, 0, Transform3D(Basis(), Vector3(0.18, 0.95, 0.1)))

	st_gantry.generate_tangents()
	var gantry_mi := MeshInstance3D.new()
	gantry_mi.name = "WellGantryCompoundMesh"
	gantry_mi.mesh = st_gantry.commit()
	well.add_child(gantry_mi)

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

	# Timber Bed Borders (compound mesh)
	var st_borders := SurfaceTool.new()
	st_borders.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_borders.set_material(mat_wood)

	var box_bz := BoxMesh.new()
	box_bz.size = Vector3(w + 0.2, 0.18, 0.15)
	for sign_z in [-1.0, 1.0]:
		st_borders.append_from(box_bz, 0, Transform3D(Basis(), Vector3(0, 0.09, sign_z * (d * 0.5 + 0.07))))

	var box_bx := BoxMesh.new()
	box_bx.size = Vector3(0.15, 0.18, d)
	for sign_x in [-1.0, 1.0]:
		st_borders.append_from(box_bx, 0, Transform3D(Basis(), Vector3(sign_x * (w * 0.5 + 0.07), 0.09, 0)))

	st_borders.generate_tangents()
	var borders_mi := MeshInstance3D.new()
	borders_mi.name = "CropBordersCompoundMesh"
	borders_mi.mesh = st_borders.commit()
	patch.add_child(borders_mi)

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

	# Row 1: Cabbages (compound mesh)
	var st_cab := SurfaceTool.new()
	st_cab.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_cab.set_material(mat_cabbage)
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.35
	for cx in range(-1, 2):
		st_cab.append_from(sph, 0, Transform3D(Basis(), Vector3(cx * 1.6, 0.25, -1.4)))
	st_cab.generate_tangents()
	var cab_mi := MeshInstance3D.new()
	cab_mi.name = "CabbageCompoundMesh"
	cab_mi.mesh = st_cab.commit()
	patch.add_child(cab_mi)

	# Row 2: Barley (compound mesh)
	var st_barley := SurfaceTool.new()
	st_barley.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_barley.set_material(mat_barley)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.04
	cyl.height = 0.75
	for bx in range(-2, 3):
		var rot_b := Basis(Vector3.FORWARD, deg_to_rad(sin(bx * 1.5) * 8.0))
		st_barley.append_from(cyl, 0, Transform3D(rot_b, Vector3(bx * 1.1, 0.45, 0.0)))
	st_barley.generate_tangents()
	var barley_mi := MeshInstance3D.new()
	barley_mi.name = "BarleyCompoundMesh"
	barley_mi.mesh = st_barley.commit()
	patch.add_child(barley_mi)

	# Row 3: Turnips (compound mesh)
	var st_turnip := SurfaceTool.new()
	st_turnip.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_turnip.set_material(mat_turnip)
	var box_t := BoxMesh.new()
	box_t.size = Vector3(0.28, 0.35, 0.28)
	for tx in range(-1, 2):
		st_turnip.append_from(box_t, 0, Transform3D(Basis(), Vector3(tx * 1.5, 0.24, 1.4)))
	st_turnip.generate_tangents()
	var turnip_mi := MeshInstance3D.new()
	turnip_mi.name = "TurnipCompoundMesh"
	turnip_mi.mesh = st_turnip.commit()
	patch.add_child(turnip_mi)

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

	# Stacked Cords of Firewood (compound 2-surface mesh)
	var arr_wood := ArrayMesh.new()
	var st_wood := SurfaceTool.new()

	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_wood.set_material(mat_wood_dark)
	var stack_box := BoxMesh.new()
	stack_box.size = Vector3(0.6, 0.45, 0.85)
	st_wood.append_from(stack_box, 0, Transform3D(Basis(), Vector3(1.2, 0.22, -0.2)))
	st_wood.generate_tangents()
	st_wood.commit(arr_wood)

	st_wood.clear()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_wood.set_material(mat_wood)
	var cyl_l := CylinderMesh.new()
	cyl_l.top_radius = 0.08
	cyl_l.bottom_radius = 0.08
	cyl_l.height = 0.8
	var rot_log := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	for log_i in range(3):
		st_wood.append_from(cyl_l, 0, Transform3D(rot_log, Vector3(1.2, 0.5, -0.45 + log_i * 0.25)))
	st_wood.generate_tangents()
	st_wood.commit(arr_wood)

	var stack_mi := MeshInstance3D.new()
	stack_mi.name = "FirewoodStackCompoundMesh"
	stack_mi.mesh = arr_wood
	area.add_child(stack_mi)

	return area

## Hay Storage & Animal Feeder Rack
static func _assemble_hay_rack(mat_wood: Material) -> Node3D:
	var rack := Node3D.new()

	# Compound Timber Frame (4 Corner Posts + Horizontal Rails)
	var st_rack := SurfaceTool.new()
	st_rack.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_rack.set_material(mat_wood)

	var box_p := BoxMesh.new()
	box_p.size = Vector3(0.12, 1.4, 0.12)
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			st_rack.append_from(box_p, 0, Transform3D(Basis(), Vector3(sign_x * 0.85, 0.7, sign_z * 0.5)))

	var box_r := BoxMesh.new()
	box_r.size = Vector3(1.8, 0.08, 0.08)
	for sign_z in [-1.0, 1.0]:
		st_rack.append_from(box_r, 0, Transform3D(Basis(), Vector3(0, 1.1, sign_z * 0.5)))

	st_rack.generate_tangents()
	var rack_mi := MeshInstance3D.new()
	rack_mi.name = "HayRackCompoundMesh"
	rack_mi.mesh = st_rack.commit()
	rack.add_child(rack_mi)

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

	# Compound mesh for 3 posts and 2 split rails in a single MeshInstance3D
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_wood)

	var box_p := BoxMesh.new()
	box_p.size = Vector3(0.12, 1.3, 0.12)
	for pz in [-total_len * 0.5, 0.0, total_len * 0.5]:
		st.append_from(box_p, 0, Transform3D(Basis(), Vector3(0, 0.65, pz)))

	var box_r := BoxMesh.new()
	box_r.size = Vector3(0.08, 0.08, total_len)
	for r in [0.45, 0.95]:
		st.append_from(box_r, 0, Transform3D(Basis(), Vector3(0, r, 0)))

	st.generate_tangents()
	var fence_mi := MeshInstance3D.new()
	fence_mi.name = "FenceCompoundMesh"
	fence_mi.mesh = st.commit()
	fence_seg.add_child(fence_mi)

	# Solid physics collision
	var col := CollisionShape3D.new()
	var box_c := BoxShape3D.new()
	box_c.size = Vector3(0.3, 1.2, total_len)
	col.shape = box_c
	col.position.y = 0.6
	fence_seg.add_child(col)

	parent.add_child(fence_seg)
