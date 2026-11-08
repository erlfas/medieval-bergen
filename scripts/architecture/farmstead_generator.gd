class_name FarmsteadGenerator
extends Node

## Procedural Piece-by-Piece Medieval Bergen Valley Farmstead Generator (Klyngetun Gård)
## Places authentic 1360 Norwegian farmsteads on flat valley plains with per-structure ground clamping:
## - Lafteverk Årestue Farmhouse (8-course notched logs, 3 shuttered windows, hinged open door, rafters, sod roof & hearth)
## - Grindverk Livestock Barn / Fjøs (post-and-beam stave frame, board-and-batten planks, barn doors, vent windows & sod roof)
## - Elevated Timber Stabbur (carved pillars, rodent stone caps, 6-course notched logs, framed door, rafters & sod roof)
## - Terrain-Conforming Split-Rail Wooden Fences (Skigard enclosing the flat valley farmyard)
## - Tilled Crop Patches (cabbage, barley, turnips), Stone Freshwater Well, Chopping Block & Bloomery Furnace

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

## Helper to snap any farmstead sub-structure to the exact terrain elevation at its local offset
static func _place_on_valley_plain(origin: Vector3, local_xz: Vector2, terrain_generator: BergenTerrainGenerator) -> Vector3:
	var wy := origin.y
	if terrain_generator != null:
		wy = terrain_generator.sample_height(origin.x + local_xz.x, origin.z + local_xz.y)
	return Vector3(local_xz.x, wy - origin.y, local_xz.y)

## Assembles a complete valley farmstead cluster (Klyngetun) at specified plain location
static func create_farmstead(farm_id: int, origin: Vector3, farm_name: String, terrain_generator: BergenTerrainGenerator) -> Node3D:
	var farm_root := Node3D.new()
	farm_root.name = "Farmstead_%d_%s" % [farm_id, farm_name.replace(" ", "_")]
	farm_root.position = origin
	farm_root.add_to_group("farmstead")

	var mat_wood := BuildingAssembler.get_shared_material("wood_spruce")
	var mat_wood_dark := BuildingAssembler.get_shared_material("wood_dark")
	var mat_stone := BuildingAssembler.get_shared_material("stone_foundation")
	var mat_sod := BuildingAssembler.get_shared_material("sod_roof")
	var mat_soil := BuildingAssembler.get_shared_material("soil_humus")

	# -------------------------------------------------------------------------
	# 1. Main Timber Farmhouse (Piece-Built Blender Laftehytte Årestue with Windows, Shutters & Hearth)
	# -------------------------------------------------------------------------
	var farmhouse_pos := _place_on_valley_plain(origin, Vector2(-3.5, -6.5), terrain_generator)
	var fw := 5.2 + float(farm_id % 3) * 0.3
	var fd := 5.8 + float((farm_id + 1) % 3) * 0.3
	var farm_spec := {
		"name": "TimberFarmhouse_Arestue_%d" % farm_id,
		"back_window": true,
		"left_window": true,
		"right_window": (farm_id % 2 == 1),
		"dual_benches": true,
	}
	var farmhouse := BuildingAssembler.assemble_log_cabin(fw, fd, farm_spec)
	farmhouse.name = "TimberFarmhouse_Arestue"
	farmhouse.position = farmhouse_pos
	farm_root.add_child(farmhouse)

	# -------------------------------------------------------------------------
	# 2. Grindverk Livestock Barn (Piece-Built Fjøs & Løe)
	# -------------------------------------------------------------------------
	var barn_pos := _place_on_valley_plain(origin, Vector2(-10.5, 2.5), terrain_generator)
	var barn := BuildingAssembler.assemble_grindverk_barn(5.6, 9.0)
	barn.name = "GrindverkBarn_Fjos"
	barn.position = barn_pos
	barn.rotation.y = deg_to_rad(90.0) # Door faces inward toward the central farmyard tun
	farm_root.add_child(barn)

	# -------------------------------------------------------------------------
	# 3. Elevated Piece-Built Timber Stabbur (Storehouse on Stilts using Blender Laftehytte modules)
	# -------------------------------------------------------------------------
	var stabbur_pos := _place_on_valley_plain(origin, Vector2(8.8, -5.0), terrain_generator)
	var stabbur := _assemble_stabbur(4.0, 4.5, mat_wood, mat_wood_dark, mat_stone, mat_sod)
	stabbur.name = "TimberStorehouse_Stabbur"
	stabbur.position = stabbur_pos
	stabbur.add_to_group("shelter")
	stabbur.add_to_group("laftehytte")
	farm_root.add_child(stabbur)

	# -------------------------------------------------------------------------
	# 4. Stone Freshwater Well
	# -------------------------------------------------------------------------
	var well_pos := _place_on_valley_plain(origin, Vector2(2.2, 1.5), terrain_generator)
	var well := _assemble_stone_well(mat_stone, mat_wood_dark)
	well.name = "StoneWell"
	well.position = well_pos
	farm_root.add_child(well)

	# -------------------------------------------------------------------------
	# 5. Wood Chopping Block & Firewood Stacks
	# -------------------------------------------------------------------------
	var wood_pos := _place_on_valley_plain(origin, Vector2(3.5, -5.5), terrain_generator)
	var wood_area := _assemble_chopping_area(mat_wood, mat_wood_dark, mat_stone)
	wood_area.name = "WoodChoppingArea"
	wood_area.position = wood_pos
	farm_root.add_child(wood_area)

	# -------------------------------------------------------------------------
	# 6. Tilled Crop Patches (Cabbage, Barley, Turnips)
	# -------------------------------------------------------------------------
	var crops_pos := _place_on_valley_plain(origin, Vector2(-4.5, 9.2), terrain_generator)
	var crop_patch := _assemble_crop_patch(7.0, 5.0, mat_soil, mat_wood_dark)
	crop_patch.name = "CropPatches"
	crop_patch.position = crops_pos
	farm_root.add_child(crop_patch)

	# -------------------------------------------------------------------------
	# 7. Hay Storage & Livestock Feeder Rack
	# -------------------------------------------------------------------------
	var hay_pos := _place_on_valley_plain(origin, Vector2(8.5, 6.8), terrain_generator)
	var hay_area := _assemble_hay_rack(mat_wood_dark)
	hay_area.name = "HayStorageRack"
	hay_area.position = hay_pos
	hay_area.add_to_group("shelter")
	farm_root.add_child(hay_area)

	# -------------------------------------------------------------------------
	# 8. Traditional Bloomery Furnace & Smithing Anvil (Blæsterovn)
	# -------------------------------------------------------------------------
	if farm_id <= 2:
		var furnace_pos := _place_on_valley_plain(origin, Vector2(9.2, 0.8), terrain_generator)
		var furnace := BloomeryFurnaceInteractable.new()
		furnace.name = "BloomeryFurnace_%d" % farm_id
		furnace.position = furnace_pos
		farm_root.add_child(furnace)

	# -------------------------------------------------------------------------
	# 9. Terrain-Conforming Split-Rail Wooden Fences (Skigard Enclosure)
	#    Batched into 1 StaticBody3D and 1 compound MeshInstance3D per farmstead
	# -------------------------------------------------------------------------
	var fence_body := StaticBody3D.new()
	fence_body.name = "SplitRailFences"
	farm_root.add_child(fence_body)

	var nw := _place_on_valley_plain(origin, Vector2(-15.5, -13.0), terrain_generator)
	var ne := _place_on_valley_plain(origin, Vector2(14.5, -13.0), terrain_generator)
	var se := _place_on_valley_plain(origin, Vector2(14.5, 14.5), terrain_generator)
	var sw := _place_on_valley_plain(origin, Vector2(-15.5, 14.5), terrain_generator)
	var gate_r := _place_on_valley_plain(origin, Vector2(2.8, 14.5), terrain_generator)
	var gate_l := _place_on_valley_plain(origin, Vector2(-2.8, 14.5), terrain_generator)

	var fence_streams: Dictionary = {}
	var st_fence := BuildingAssembler._get_stream(fence_streams, "wood_dark")
	_append_fence_segment(fence_body, st_fence, nw, ne)
	_append_fence_segment(fence_body, st_fence, ne, se)
	_append_fence_segment(fence_body, st_fence, se, gate_r)
	_append_fence_segment(fence_body, st_fence, gate_l, sw)
	_append_fence_segment(fence_body, st_fence, sw, nw)
	fence_body.add_child(BuildingAssembler._commit_piece_streams(fence_streams, "FenceCompoundMesh"))

	return farm_root

## Piece-by-Piece Traditional Norwegian Stabbur (Elevated Lafteverk Storehouse on Carved Stilts)
static func _assemble_stabbur(w: float, d: float, _mat_wood: Material, _mat_wood_dark: Material, _mat_stone: Material, _mat_sod: Material) -> StaticBody3D:
	var stabbur := StaticBody3D.new()
	stabbur.add_to_group("building")

	var streams: Dictionary = {}
	var st_dark := BuildingAssembler._get_stream(streams, "wood_dark")
	var st_stone := BuildingAssembler._get_stream(streams, "stone_foundation")
	var st_wood := BuildingAssembler._get_stream(streams, "wood_spruce")

	var stilt_h: float = 0.92
	var wall_h: float = 1.98
	var gable_h: float = 1.18
	var half_w: float = w * 0.5
	var half_d: float = d * 0.5
	var base_y: float = stilt_h + 0.24

	# 1. 4 Carved Wooden Pillars (Stabbestolper) + Blender Stone Footing Piers + Rodent-Guard Caps (Stabbesteiner)
	var pillar_coords := [
		Vector3(-half_w + 0.32, 0, -half_d + 0.32),
		Vector3(half_w - 0.32, 0, -half_d + 0.32),
		Vector3(-half_w + 0.32, 0, half_d - 0.32),
		Vector3(half_w - 0.32, 0, half_d - 0.32)
	]
	for pos in pillar_coords:
		if not BuildingAssembler._append_blender_module(streams, "foundation_pier", BuildingAssembler._make_module_transform(pos, 0.0, Vector3(0.88, 0.65, 0.88))):
			BuildingAssembler._append_box_piece(st_stone, Vector3(0.56, 0.36, 0.56), pos + Vector3(0, -0.12, 0))
		BuildingAssembler._append_cyl_piece(st_dark, 0.16, 0.23, stilt_h, pos + Vector3(0, stilt_h * 0.5, 0))
		BuildingAssembler._append_cyl_piece(st_stone, 0.35, 0.25, 0.14, pos + Vector3(0, stilt_h + 0.07, 0))

	# 2. Heavy Cross-Sill Beams & Blender Planked Storehouse Deck
	BuildingAssembler._append_box_piece(st_dark, Vector3(w + 0.26, 0.18, 0.24), Vector3(0, stilt_h + 0.16, -half_d + 0.32))
	BuildingAssembler._append_box_piece(st_dark, Vector3(w + 0.26, 0.18, 0.24), Vector3(0, stilt_h + 0.16, half_d - 0.32))
	if not BuildingAssembler._append_blender_module(streams, "floor_plank_bay", BuildingAssembler._make_module_transform(Vector3(0, base_y - 0.08, 0), 0.0, Vector3((w + 0.2) / 4.0, 1.0, (d + 0.2) / 4.0))):
		BuildingAssembler._append_box_piece(st_wood, Vector3(w + 0.16, 0.12, d + 0.24), Vector3(0, base_y - 0.04, 0))

	# 3. Elevated Notched Lafteverk Log Walls & Portal Door (from Blender .glb modules)
	if not BuildingAssembler._append_laftehytte_wall_modules(streams, w, d, base_y, wall_h, false, false, false):
		var door_ap := [{"x": 0.0, "y_min": 0.0, "y_max": 1.56, "w": 0.94}]
		BuildingAssembler._append_lafteverk_wall_courses(streams, Vector3(0, base_y, -half_d), w, wall_h, 0.0, 6, 0.28, 0.26, door_ap)
		BuildingAssembler._append_door_piece(streams, Vector3(0, base_y, -half_d), 0.0, 0.94, 1.56, 0.28, false)
		BuildingAssembler._append_lafteverk_wall_courses(streams, Vector3(0, base_y, half_d), w, wall_h, PI, 6, 0.28, 0.26, [])
		BuildingAssembler._append_lafteverk_wall_courses(streams, Vector3(-half_w, base_y, 0), d, wall_h, deg_to_rad(-90.0), 6, 0.28, 0.26, [])
		BuildingAssembler._append_lafteverk_wall_courses(streams, Vector3(half_w, base_y, 0), d, wall_h, deg_to_rad(90.0), 6, 0.28, 0.26, [])

	# 4. Walkable Timber Steps (Trapp) with Stringers & Treads
	var step_count := 4
	for s in range(step_count):
		var sy: float = (float(s) + 0.5) * (stilt_h / float(step_count))
		var sz: float = -half_d - 0.28 - float(step_count - 1 - s) * 0.32
		BuildingAssembler._append_box_piece(st_dark, Vector3(1.12, 0.14, 0.34), Vector3(0, sy, sz))

	# 5. Gables, Exposed Rafters, Bargeboards, Birch Bark & Sod Turf Roof (from Blender .glb modules)
	if not BuildingAssembler._append_laftehytte_roof_modules(streams, w, d, base_y + wall_h, gable_h, false):
		for gz in [-half_d, half_d]:
			var g_steps := 4
			for g in range(g_steps):
				var frac := (float(g) + 0.5) / float(g_steps)
				var cw := (w + 0.40) * (1.0 - frac * 0.86)
				var gy := base_y + wall_h + (float(g) + 0.5) * (gable_h / float(g_steps))
				BuildingAssembler._append_box_piece(st_wood, Vector3(cw, (gable_h / float(g_steps)) * 0.92, 0.28), Vector3(0, gy, gz))
		BuildingAssembler._append_roof_assembly(streams, w, d, base_y + wall_h, gable_h, "sod_roof", true, false, false)

	stabbur.add_child(BuildingAssembler._commit_piece_streams(streams, "StabburPieceAssemblyMesh"))

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(w + 0.4, wall_h + stilt_h + 1.2, d + 0.4)
	col.shape = box_col
	col.position = Vector3(0, (wall_h + stilt_h) * 0.5 + 0.4, 0)
	stabbur.add_child(col)

	return stabbur

## Stone Well with Timber Gantry, Rope, and Wooden Bucket (Freshwater source)
static func _assemble_stone_well(_mat_stone: Material, _mat_wood: Material) -> StaticBody3D:
	var well := FarmWellInteractable.new()
	well.add_to_group("stone_well")
	well.add_to_group("freshwater")

	var streams: Dictionary = {}
	var st_stone := BuildingAssembler._get_stream(streams, "stone_foundation")
	var st_wood := BuildingAssembler._get_stream(streams, "wood_dark")
	var st_water := BuildingAssembler._get_stream(streams, "well_water")

	BuildingAssembler._append_cyl_piece(st_stone, 1.0, 1.08, 1.15, Vector3(0, 0.28, 0), Vector3.ZERO, 12)
	BuildingAssembler._append_cyl_piece(st_water, 0.72, 0.72, 0.05, Vector3(0, 0.35, 0), Vector3.ZERO, 8)

	for sign_x in [-1.0, 1.0]:
		BuildingAssembler._append_box_piece(st_wood, Vector3(0.14, 2.0, 0.14), Vector3(sign_x * 0.88, 1.25, 0))
	BuildingAssembler._append_box_piece(st_wood, Vector3(2.0, 0.14, 0.14), Vector3(0, 2.2, 0))

	for sign_z in [-1.0, 1.0]:
		BuildingAssembler._append_box_piece(st_wood, Vector3(2.1, 0.08, 0.85), Vector3(0, 2.45, sign_z * 0.35), Vector3(sign_z * deg_to_rad(30.0), 0, 0))

	BuildingAssembler._append_cyl_piece(st_wood, 0.18, 0.14, 0.32, Vector3(0.18, 0.95, 0.1))

	well.add_child(BuildingAssembler._commit_piece_streams(streams, "WellCompoundMesh"))

	var col := CollisionShape3D.new()
	var cyl_col := CylinderShape3D.new()
	cyl_col.radius = 1.15
	cyl_col.height = 2.4
	col.shape = cyl_col
	col.position.y = 1.2
	well.add_child(col)

	return well

## Crop Patches with Rows of Cabbage, Barley, and Turnips (Single multi-surface MeshInstance3D)
static func _assemble_crop_patch(w: float, d: float, _mat_soil: Material, _mat_wood: Material) -> StaticBody3D:
	var patch := FarmCropInteractable.new()
	patch.add_to_group("crop_patch")

	var streams: Dictionary = {}
	var st_soil := BuildingAssembler._get_stream(streams, "soil_humus")
	var st_wood := BuildingAssembler._get_stream(streams, "wood_dark")
	var st_cab := BuildingAssembler._get_stream(streams, "crop_cabbage")
	var st_barley := BuildingAssembler._get_stream(streams, "crop_barley")
	var st_turnip := BuildingAssembler._get_stream(streams, "crop_turnip")

	BuildingAssembler._append_box_piece(st_soil, Vector3(w, 0.32, d), Vector3.ZERO)

	for sign_z in [-1.0, 1.0]:
		BuildingAssembler._append_box_piece(st_wood, Vector3(w + 0.2, 0.24, 0.15), Vector3(0, 0.06, sign_z * (d * 0.5 + 0.07)))
	for sign_x in [-1.0, 1.0]:
		BuildingAssembler._append_box_piece(st_wood, Vector3(0.15, 0.24, d), Vector3(sign_x * (w * 0.5 + 0.07), 0.06, 0))

	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.35
	sph.radial_segments = 8
	sph.rings = 4
	for cx in range(-1, 2):
		st_cab.append_from(sph, 0, Transform3D(Basis(), Vector3(cx * 1.6, 0.25, -1.4)))

	for bx in range(-2, 3):
		var rot_b := Vector3(0, 0, deg_to_rad(sin(bx * 1.5) * 8.0))
		BuildingAssembler._append_cyl_piece(st_barley, 0.05, 0.04, 0.75, Vector3(bx * 1.1, 0.45, 0.0), rot_b)

	for tx in range(-1, 2):
		BuildingAssembler._append_box_piece(st_turnip, Vector3(0.28, 0.35, 0.28), Vector3(tx * 1.5, 0.24, 1.4))

	patch.add_child(BuildingAssembler._commit_piece_streams(streams, "CropPatchCompoundMesh"))

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(w + 0.3, 0.16, d + 0.3)
	col.shape = box_col
	col.position.y = 0.08
	patch.add_child(col)

	return patch

## Chopping Block, Wedge Axe, and Firewood Stacks (Single multi-surface MeshInstance3D)
static func _assemble_chopping_area(_mat_wood: Material, _mat_wood_dark: Material, _mat_stone: Material) -> Node3D:
	var area := StaticBody3D.new()

	var streams: Dictionary = {}
	var st_dark := BuildingAssembler._get_stream(streams, "wood_dark")
	var st_stone := BuildingAssembler._get_stream(streams, "stone_foundation")
	var st_wood := BuildingAssembler._get_stream(streams, "wood_spruce")

	BuildingAssembler._append_cyl_piece(st_dark, 0.35, 0.42, 0.75, Vector3(0, 0.375, 0))
	BuildingAssembler._append_box_piece(st_stone, Vector3(0.04, 0.15, 0.18), Vector3(0, 0.82, 0), Vector3(deg_to_rad(15.0), 0, 0))
	BuildingAssembler._append_box_piece(st_dark, Vector3(0.6, 0.45, 0.85), Vector3(1.2, 0.22, -0.2))

	for log_i in range(3):
		BuildingAssembler._append_cyl_piece(st_wood, 0.08, 0.08, 0.8, Vector3(1.2, 0.5, -0.45 + log_i * 0.25), Vector3(0, 0, deg_to_rad(90.0)))

	area.add_child(BuildingAssembler._commit_piece_streams(streams, "ChoppingAreaCompoundMesh"))

	var col := CollisionShape3D.new()
	var cyl_col := CylinderShape3D.new()
	cyl_col.radius = 0.45
	cyl_col.height = 0.8
	col.shape = cyl_col
	col.position.y = 0.4
	area.add_child(col)

	return area

## Hay Storage & Animal Feeder Rack (Single multi-surface MeshInstance3D)
static func _assemble_hay_rack(_mat_wood: Material) -> Node3D:
	var rack := Node3D.new()

	var streams: Dictionary = {}
	var st_wood := BuildingAssembler._get_stream(streams, "wood_dark")
	var st_hay := BuildingAssembler._get_stream(streams, "hay_straw")

	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			BuildingAssembler._append_box_piece(st_wood, Vector3(0.12, 1.4, 0.12), Vector3(sign_x * 0.85, 0.7, sign_z * 0.5))

	for sign_z in [-1.0, 1.0]:
		BuildingAssembler._append_box_piece(st_wood, Vector3(1.8, 0.08, 0.08), Vector3(0, 1.1, sign_z * 0.5))

	BuildingAssembler._append_box_piece(st_hay, Vector3(1.6, 0.85, 0.9), Vector3(0, 0.45, 0))

	rack.add_child(BuildingAssembler._commit_piece_streams(streams, "HayRackCompoundMesh"))
	return rack

## Appends a split-rail fence segment into the farmstead's unified fence SurfaceTool stream and StaticBody3D
static func _append_fence_segment(fence_body: StaticBody3D, st: SurfaceTool, from_pos: Vector3, to_pos: Vector3) -> void:
	var span_vec := to_pos - from_pos
	var horiz_vec := Vector3(span_vec.x, 0.0, span_vec.z)
	var total_len := horiz_vec.length()
	if total_len < 0.2:
		return
	var dir := horiz_vec.normalized()
	var dy := to_pos.y - from_pos.y
	var mid_pos := (from_pos + to_pos) * 0.5
	var yaw := atan2(-dir.x, -dir.z)
	var seg_xform := Transform3D(Basis(Vector3.UP, yaw), mid_pos)

	for frac in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		var pz: float = frac * total_len
		var py: float = -frac * dy + 0.58
		var world_post_pos := seg_xform * Vector3(0, py, pz)
		BuildingAssembler._append_box_piece(st, Vector3(0.13, 1.45, 0.13), world_post_pos, Vector3(0, yaw, 0))

	var pitch_x := atan2(dy, total_len)
	for r in [0.42, 0.92]:
		var world_rail_pos := seg_xform * Vector3(0, r, 0)
		BuildingAssembler._append_box_piece(st, Vector3(0.08, 0.08, total_len + 0.1), world_rail_pos, Vector3(pitch_x, yaw, 0))

	var col := CollisionShape3D.new()
	var box_c := BoxShape3D.new()
	box_c.size = Vector3(0.3, 1.2, total_len)
	col.shape = box_c
	col.transform = seg_xform * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))
	fence_body.add_child(col)
