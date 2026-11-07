class_name BuildingAssembler
extends Node3D

## Deterministic procedural assembler for medieval Bergen buildings.
## Assembles buildings piece-by-piece from modular 3D components following
## historical Norwegian vernacular timber framing (lafteverk & grindverk).

@export var lot_seed: int = 1360
@export var lot_width_meters: float = 8.0   ## Typical narrow Bergen tenement width
@export var lot_depth_meters: float = 24.0  ## Deep tenement strip stretching back from quay
@export var stories: int = 3
@export var has_waterfront_crane: bool = true
@export var has_rear_stone_cellar: bool = true

var _rng: RandomNumberGenerator

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = lot_seed

## Generates a complete Norwegian medieval log cabin (Laftehytte / Årestue)
## - Lafteverk interlocking spruce timber walls with notched corner overhangs
## - Navigable open doorway for player to enter and walk inside
## - Central stone hearth (Åre) with firelight (group "hearth")
## - Traditional Norwegian sod roof (Torvtak) with birch bark waterproofing and smoke hole (ljore)
## - Complete solid physics collisions on walls, floor, and roof
static func assemble_log_cabin(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var cabin := StaticBody3D.new()
	cabin.name = "Laftehytte_Cabin_%d" % (randi() % 9999)
	cabin.add_to_group("building")
	cabin.add_to_group("shelter")

	# Shared materials
	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.42, 0.28, 0.16) # Weathered spruce / pine log
	mat_wood.roughness = 0.85

	var mat_wood_dark := StandardMaterial3D.new()
	mat_wood_dark.albedo_color = Color(0.32, 0.20, 0.11) # Tarred frame beams
	mat_wood_dark.roughness = 0.9

	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.48, 0.46, 0.44) # Slate & granite
	mat_stone.roughness = 0.92

	var mat_sod := StandardMaterial3D.new()
	mat_sod.albedo_color = Color(0.24, 0.42, 0.18) # Green sod / moss turf
	mat_sod.roughness = 0.95

	var mat_birch := StandardMaterial3D.new()
	mat_birch.albedo_color = Color(0.85, 0.82, 0.74) # White birch bark edge
	mat_birch.roughness = 0.8

	var wall_h: float = 2.2
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var wall_thick: float = 0.35
	var door_w: float = 1.1
	var door_h: float = 1.95

	# -------------------------------------------------------------
	# 1. Foundation Stones (Grunnmur - Deep Footings anchored into terrain)
	# -------------------------------------------------------------
	var foundation_coords := [
		Vector3(-half_w, -0.15, -half_d),
		Vector3(half_w, -0.15, -half_d),
		Vector3(-half_w, -0.15, half_d),
		Vector3(half_w, -0.15, half_d)
	]
	for pos in foundation_coords:
		var stone_mesh := MeshInstance3D.new()
		var stone_box := BoxMesh.new()
		stone_box.size = Vector3(0.72, 0.7, 0.72)
		stone_mesh.mesh = stone_box
		stone_mesh.material_override = mat_stone
		stone_mesh.position = pos
		cabin.add_child(stone_mesh)

	# -------------------------------------------------------------
	# 2. Wooden Floor & Floor Collision
	# -------------------------------------------------------------
	var floor_mesh := MeshInstance3D.new()
	var box_floor := BoxMesh.new()
	box_floor.size = Vector3(width - 0.2, 0.12, depth - 0.2)
	floor_mesh.mesh = box_floor
	floor_mesh.material_override = mat_wood_dark
	floor_mesh.position = Vector3(0, 0.06, 0)
	cabin.add_child(floor_mesh)

	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(width, 0.2, depth)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, 0.0, 0)
	cabin.add_child(floor_col)

	# Doorway Threshold (Terskel)
	var threshold := MeshInstance3D.new()
	var th_box := BoxMesh.new()
	th_box.size = Vector3(door_w + 0.1, 0.1, 0.35)
	threshold.mesh = th_box
	threshold.material_override = mat_wood_dark
	threshold.position = Vector3(0, 0.05, -half_d)
	cabin.add_child(threshold)

	# -------------------------------------------------------------
	# 3. Lafteverk Walls (Stacked horizontal timber logs)
	# -------------------------------------------------------------
	var log_count: int = 3
	var log_h: float = wall_h / float(log_count)
	var nov_extension: float = 0.30 # Overhang past corner joints

	# Back Wall (Z = +half_d)
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(width + nov_extension * 2.0, log_h * 0.94, wall_thick)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(0, y_pos, half_d)
		cabin.add_child(log_m)

	var back_col := CollisionShape3D.new()
	var back_shape := BoxShape3D.new()
	back_shape.size = Vector3(width, wall_h, wall_thick)
	back_col.shape = back_shape
	back_col.position = Vector3(0, wall_h * 0.5, half_d)
	cabin.add_child(back_col)

	# Left Wall (X = -half_w)
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(wall_thick, log_h * 0.94, depth + nov_extension * 2.0)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(-half_w, y_pos, 0)
		cabin.add_child(log_m)

	var left_col := CollisionShape3D.new()
	var left_shape := BoxShape3D.new()
	left_shape.size = Vector3(wall_thick, wall_h, depth)
	left_col.shape = left_shape
	left_col.position = Vector3(-half_w, wall_h * 0.5, 0)
	cabin.add_child(left_col)

	# Right Wall (X = +half_w)
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(wall_thick, log_h * 0.94, depth + nov_extension * 2.0)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(half_w, y_pos, 0)
		cabin.add_child(log_m)

	var right_col := CollisionShape3D.new()
	var right_shape := BoxShape3D.new()
	right_shape.size = Vector3(wall_thick, wall_h, depth)
	right_col.shape = right_shape
	right_col.position = Vector3(half_w, wall_h * 0.5, 0)
	cabin.add_child(right_col)

	# Front Wall (Z = -half_d) with OPEN DOORWAY in center
	var front_side_w: float = (width - door_w) * 0.5
	var left_front_center_x: float = -half_w + front_side_w * 0.5
	var right_front_center_x: float = half_w - front_side_w * 0.5

	# Front Left logs
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(front_side_w + nov_extension, log_h * 0.94, wall_thick)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(left_front_center_x - nov_extension * 0.5, y_pos, -half_d)
		cabin.add_child(log_m)

	var front_left_col := CollisionShape3D.new()
	var front_l_shape := BoxShape3D.new()
	front_l_shape.size = Vector3(front_side_w, wall_h, wall_thick)
	front_left_col.shape = front_l_shape
	front_left_col.position = Vector3(left_front_center_x, wall_h * 0.5, -half_d)
	cabin.add_child(front_left_col)

	# Front Right logs
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(front_side_w + nov_extension, log_h * 0.94, wall_thick)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(right_front_center_x + nov_extension * 0.5, y_pos, -half_d)
		cabin.add_child(log_m)

	var front_right_col := CollisionShape3D.new()
	var front_r_shape := BoxShape3D.new()
	front_r_shape.size = Vector3(front_side_w, wall_h, wall_thick)
	front_right_col.shape = front_r_shape
	front_right_col.position = Vector3(right_front_center_x, wall_h * 0.5, -half_d)
	cabin.add_child(front_right_col)

	# Door Lintel (Overstokk above doorway)
	var lintel_h: float = wall_h - door_h
	var lintel_m := MeshInstance3D.new()
	var lintel_box := BoxMesh.new()
	lintel_box.size = Vector3(door_w + 0.3, lintel_h, wall_thick * 1.05)
	lintel_m.mesh = lintel_box
	lintel_m.material_override = mat_wood_dark
	lintel_m.position = Vector3(0, door_h + lintel_h * 0.5, -half_d)
	cabin.add_child(lintel_m)

	var lintel_col := CollisionShape3D.new()
	var lintel_shape := BoxShape3D.new()
	lintel_shape.size = Vector3(door_w, lintel_h, wall_thick)
	lintel_col.shape = lintel_shape
	lintel_col.position = Vector3(0, door_h + lintel_h * 0.5, -half_d)
	cabin.add_child(lintel_col)

	# Door Jamb Posts (Heavy vertical timber frames flanking the door)
	for jamb_sign in [-1.0, 1.0]:
		var jamb := MeshInstance3D.new()
		var jamb_box := BoxMesh.new()
		jamb_box.size = Vector3(0.14, door_h, wall_thick * 1.1)
		jamb.mesh = jamb_box
		jamb.material_override = mat_wood_dark
		jamb.position = Vector3(jamb_sign * (door_w * 0.5 + 0.05), door_h * 0.5, -half_d)
		cabin.add_child(jamb)

	# Interior Sleeping Bench (Langbenk / Bris) along right wall
	var bench := MeshInstance3D.new()
	var bench_box := BoxMesh.new()
	bench_box.size = Vector3(0.75, 0.4, depth * 0.6)
	bench.mesh = bench_box
	bench.material_override = mat_wood
	bench.position = Vector3(half_w - 0.55, 0.26, 0.2)
	cabin.add_child(bench)

	# -------------------------------------------------------------
	# 4. Gable Ends (Front & Back Triangular Log Gables)
	# -------------------------------------------------------------
	var ridge_h: float = 3.6
	var gable_h: float = ridge_h - wall_h

	for gable_z in [-half_d, half_d]:
		var gable_steps: int = 2
		for g in range(gable_steps):
			var frac: float = float(g + 0.5) / float(gable_steps)
			var cur_w: float = (width + nov_extension * 2.0) * (1.0 - frac * 0.88)
			var gy: float = wall_h + (g + 0.5) * (gable_h / float(gable_steps))
			var gm := MeshInstance3D.new()
			var gbox := BoxMesh.new()
			gbox.size = Vector3(cur_w, (gable_h / float(gable_steps)) * 0.95, wall_thick)
			gm.mesh = gbox
			gm.material_override = mat_wood
			gm.position = Vector3(0, gy, gable_z)
			cabin.add_child(gm)

		var g_col := CollisionShape3D.new()
		var g_shape := BoxShape3D.new()
		g_shape.size = Vector3(width * 0.65, gable_h, wall_thick)
		g_col.shape = g_shape
		g_col.position = Vector3(0, wall_h + gable_h * 0.5, gable_z)
		cabin.add_child(g_col)

	# -------------------------------------------------------------
	# 5. Heavy Ridge Beam (Mønsås) & Ceiling Collision
	# -------------------------------------------------------------
	var ridge_beam := MeshInstance3D.new()
	var ridge_box := BoxMesh.new()
	ridge_box.size = Vector3(0.35, 0.35, depth + 1.0)
	ridge_beam.mesh = ridge_box
	ridge_beam.material_override = mat_wood_dark
	ridge_beam.position = Vector3(0, ridge_h + 0.05, 0)
	cabin.add_child(ridge_beam)

	var ridge_col := CollisionShape3D.new()
	var rcol_shape := BoxShape3D.new()
	rcol_shape.size = Vector3(ridge_box.size.x, ridge_box.size.y, ridge_box.size.z)
	ridge_col.shape = rcol_shape
	ridge_col.position = ridge_beam.position
	cabin.add_child(ridge_col)

	# -------------------------------------------------------------
	# 6. Traditional Norwegian Sod Roof (Torvtak)
	# -------------------------------------------------------------
	var roof_pitch_rad: float = atan2(gable_h, half_w)
	var roof_slope_len: float = sqrt(pow(half_w + 0.45, 2.0) + pow(gable_h + 0.15, 2.0))
	var roof_thick: float = 0.28
	var roof_length: float = depth + 0.8

	# Left Roof Slope (-X)
	var roof_left := MeshInstance3D.new()
	var r_box_l := BoxMesh.new()
	r_box_l.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_left.mesh = r_box_l
	roof_left.material_override = mat_sod
	roof_left.position = Vector3(-half_w * 0.5 - 0.1, wall_h + gable_h * 0.5 + 0.12, 0)
	roof_left.rotation.z = -roof_pitch_rad
	cabin.add_child(roof_left)

	var roof_l_col := CollisionShape3D.new()
	var roof_l_shape := BoxShape3D.new()
	roof_l_shape.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_l_col.shape = roof_l_shape
	roof_l_col.position = roof_left.position
	roof_l_col.rotation.z = -roof_pitch_rad
	cabin.add_child(roof_l_col)

	# Right Roof Slope (+X)
	var roof_right := MeshInstance3D.new()
	var r_box_r := BoxMesh.new()
	r_box_r.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_right.mesh = r_box_r
	roof_right.material_override = mat_sod
	roof_right.position = Vector3(half_w * 0.5 + 0.1, wall_h + gable_h * 0.5 + 0.12, 0)
	roof_right.rotation.z = roof_pitch_rad
	cabin.add_child(roof_right)

	var roof_r_col := CollisionShape3D.new()
	var roof_r_shape := BoxShape3D.new()
	roof_r_shape.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_r_col.shape = roof_r_shape
	roof_r_col.position = roof_right.position
	roof_r_col.rotation.z = roof_pitch_rad
	cabin.add_child(roof_r_col)

	# Birch bark strip under turf edge (Never under torv)
	for side_sign in [-1.0, 1.0]:
		var bark_strip := MeshInstance3D.new()
		var bark_box := BoxMesh.new()
		bark_box.size = Vector3(0.06, 0.08, roof_length)
		bark_strip.mesh = bark_box
		bark_strip.material_override = mat_birch
		bark_strip.position = Vector3(side_sign * (half_w + 0.35), wall_h - 0.04, 0)
		cabin.add_child(bark_strip)

		# Turf-retaining log along eaves (Torvvol)
		var torvvol := MeshInstance3D.new()
		var torv_box := BoxMesh.new()
		torv_box.size = Vector3(0.18, 0.18, roof_length)
		torvvol.mesh = torv_box
		torvvol.material_override = mat_wood_dark
		torvvol.position = Vector3(side_sign * (half_w + 0.38), wall_h + 0.08, 0)
		cabin.add_child(torvvol)

	# -------------------------------------------------------------
	# 7. Smoke Hole / Skylight (Ljore) in Roof
	# -------------------------------------------------------------
	var ljore_frame := MeshInstance3D.new()
	var ljore_box := BoxMesh.new()
	ljore_box.size = Vector3(0.85, 0.3, 0.85)
	ljore_frame.mesh = ljore_box
	ljore_frame.material_override = mat_wood_dark
	ljore_frame.position = Vector3(0, ridge_h + 0.22, 0.1)
	cabin.add_child(ljore_frame)

	# -------------------------------------------------------------
	# 8. Central Stone Hearth (Åre) Fireplace with Rising Smoke
	# -------------------------------------------------------------
	var hearth := Node3D.new()
	hearth.name = "CentralHearth"
	hearth.add_to_group("hearth")
	hearth.position = Vector3(0, 0.14, 0.2)
	cabin.add_child(hearth)

	# Hearth stone border
	var hearth_base := MeshInstance3D.new()
	var h_box := BoxMesh.new()
	h_box.size = Vector3(1.3, 0.22, 1.3)
	hearth_base.mesh = h_box
	hearth_base.material_override = mat_stone
	hearth.add_child(hearth_base)

	# Glowing Embers & Burning Firewood
	var embers := MeshInstance3D.new()
	var emb_box := BoxMesh.new()
	emb_box.size = Vector3(0.8, 0.14, 0.8)
	embers.mesh = emb_box
	var mat_fire := StandardMaterial3D.new()
	mat_fire.albedo_color = Color(1.0, 0.45, 0.12)
	mat_fire.emission_enabled = true
	mat_fire.emission = Color(1.0, 0.55, 0.15)
	mat_fire.emission_energy_multiplier = 2.8
	embers.material_override = mat_fire
	embers.position = Vector3(0, 0.14, 0)
	hearth.add_child(embers)

	# Hearth Light (Warm firelight for cozy interior warmth)
	var fire_light := OmniLight3D.new()
	fire_light.name = "HearthFireLight"
	fire_light.light_color = Color(1.0, 0.65, 0.25)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 9.0
	fire_light.shadow_enabled = false
	fire_light.position = Vector3(0, 0.65, 0)
	hearth.add_child(fire_light)

	return cabin

## Assembles Cabin Stage 1: Stone Footings & Heavy Timber Floor
static func assemble_cabin_stage_foundation(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Foundation_%d" % (randi() % 9999)
	stage.add_to_group("building")

	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.48, 0.46, 0.44)
	mat_stone.roughness = 0.92

	var mat_wood_dark := StandardMaterial3D.new()
	mat_wood_dark.albedo_color = Color(0.32, 0.20, 0.11)

	var half_w := width * 0.5
	var half_d := depth * 0.5

	var foundation_coords := [
		Vector3(-half_w, -0.15, -half_d),
		Vector3(half_w, -0.15, -half_d),
		Vector3(-half_w, -0.15, half_d),
		Vector3(half_w, -0.15, half_d),
		Vector3(0, -0.15, -half_d),
		Vector3(0, -0.15, half_d),
		Vector3(-half_w, -0.15, 0),
		Vector3(half_w, -0.15, 0)
	]
	for pos in foundation_coords:
		var stone_mesh := MeshInstance3D.new()
		var stone_box := BoxMesh.new()
		stone_box.size = Vector3(0.72, 0.7, 0.72)
		stone_mesh.mesh = stone_box
		stone_mesh.material_override = mat_stone
		stone_mesh.position = pos
		stage.add_child(stone_mesh)

	var floor_mesh := MeshInstance3D.new()
	var box_floor := BoxMesh.new()
	box_floor.size = Vector3(width - 0.2, 0.12, depth - 0.2)
	floor_mesh.mesh = box_floor
	floor_mesh.material_override = mat_wood_dark
	floor_mesh.position = Vector3(0, 0.06, 0)
	stage.add_child(floor_mesh)

	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(width, 0.2, depth)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, 0.0, 0)
	stage.add_child(floor_col)

	return stage

## Assembles Cabin Stage 2: Lafteverk Timber Walls & Open Doorway
static func assemble_cabin_stage_walls(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Walls_%d" % (randi() % 9999)
	stage.add_to_group("building")

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.42, 0.28, 0.16)
	mat_wood.roughness = 0.85

	var mat_wood_dark := StandardMaterial3D.new()
	mat_wood_dark.albedo_color = Color(0.32, 0.20, 0.11)

	var wall_h: float = 2.2
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var wall_thick: float = 0.35
	var door_w: float = 1.1
	var door_h: float = 1.95
	var log_count: int = 7
	var log_h: float = wall_h / float(log_count)
	var nov_extension: float = 0.30

	# Back wall
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(width + nov_extension * 2.0, log_h * 0.94, wall_thick)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(0, y_pos, half_d)
		stage.add_child(log_m)

	var back_col := CollisionShape3D.new()
	var back_shape := BoxShape3D.new()
	back_shape.size = Vector3(width, wall_h, wall_thick)
	back_col.shape = back_shape
	back_col.position = Vector3(0, wall_h * 0.5, half_d)
	stage.add_child(back_col)

	# Left wall
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(wall_thick, log_h * 0.94, depth + nov_extension * 2.0)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(-half_w, y_pos, 0)
		stage.add_child(log_m)

	var left_col := CollisionShape3D.new()
	var left_shape := BoxShape3D.new()
	left_shape.size = Vector3(wall_thick, wall_h, depth)
	left_col.shape = left_shape
	left_col.position = Vector3(-half_w, wall_h * 0.5, 0)
	stage.add_child(left_col)

	# Right wall
	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_m := MeshInstance3D.new()
		var log_box := BoxMesh.new()
		log_box.size = Vector3(wall_thick, log_h * 0.94, depth + nov_extension * 2.0)
		log_m.mesh = log_box
		log_m.material_override = mat_wood
		log_m.position = Vector3(half_w, y_pos, 0)
		stage.add_child(log_m)

	var right_col := CollisionShape3D.new()
	var right_shape := BoxShape3D.new()
	right_shape.size = Vector3(wall_thick, wall_h, depth)
	right_col.shape = right_shape
	right_col.position = Vector3(half_w, wall_h * 0.5, 0)
	stage.add_child(right_col)

	# Front wall with door
	var front_side_w: float = (width - door_w) * 0.5
	var left_front_center_x: float = -half_w + front_side_w * 0.5
	var right_front_center_x: float = half_w - front_side_w * 0.5

	for i in range(log_count):
		var y_pos: float = (i + 0.5) * log_h
		var log_l := MeshInstance3D.new()
		var box_l := BoxMesh.new()
		box_l.size = Vector3(front_side_w + nov_extension, log_h * 0.94, wall_thick)
		log_l.mesh = box_l
		log_l.material_override = mat_wood
		log_l.position = Vector3(left_front_center_x - nov_extension * 0.5, y_pos, -half_d)
		stage.add_child(log_l)

		var log_r := MeshInstance3D.new()
		var box_r := BoxMesh.new()
		box_r.size = Vector3(front_side_w + nov_extension, log_h * 0.94, wall_thick)
		log_r.mesh = box_r
		log_r.material_override = mat_wood
		log_r.position = Vector3(right_front_center_x + nov_extension * 0.5, y_pos, -half_d)
		stage.add_child(log_r)

	var fl_col := CollisionShape3D.new()
	var fl_shape := BoxShape3D.new()
	fl_shape.size = Vector3(front_side_w, wall_h, wall_thick)
	fl_col.shape = fl_shape
	fl_col.position = Vector3(left_front_center_x, wall_h * 0.5, -half_d)
	stage.add_child(fl_col)

	var fr_col := CollisionShape3D.new()
	var fr_shape := BoxShape3D.new()
	fr_shape.size = Vector3(front_side_w, wall_h, wall_thick)
	fr_col.shape = fr_shape
	fr_col.position = Vector3(right_front_center_x, wall_h * 0.5, -half_d)
	stage.add_child(fr_col)

	var lintel_h: float = wall_h - door_h
	var lintel_m := MeshInstance3D.new()
	var lintel_box := BoxMesh.new()
	lintel_box.size = Vector3(door_w + 0.3, lintel_h, wall_thick * 1.05)
	lintel_m.mesh = lintel_box
	lintel_m.material_override = mat_wood_dark
	lintel_m.position = Vector3(0, door_h + lintel_h * 0.5, -half_d)
	stage.add_child(lintel_m)

	for jamb_sign in [-1.0, 1.0]:
		var jamb := MeshInstance3D.new()
		var jamb_box := BoxMesh.new()
		jamb_box.size = Vector3(0.14, door_h, wall_thick * 1.1)
		jamb.mesh = jamb_box
		jamb.material_override = mat_wood_dark
		jamb.position = Vector3(jamb_sign * (door_w * 0.5 + 0.05), door_h * 0.5, -half_d)
		stage.add_child(jamb)

	return stage

## Assembles Cabin Stage 3: Gables, Ridge Beam & Sod Turf Roof
static func assemble_cabin_stage_roof(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Roof_%d" % (randi() % 9999)
	stage.add_to_group("building")
	stage.add_to_group("shelter")

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.42, 0.28, 0.16)

	var mat_wood_dark := StandardMaterial3D.new()
	mat_wood_dark.albedo_color = Color(0.32, 0.20, 0.11)

	var mat_sod := StandardMaterial3D.new()
	mat_sod.albedo_color = Color(0.24, 0.42, 0.18)

	var mat_birch := StandardMaterial3D.new()
	mat_birch.albedo_color = Color(0.85, 0.82, 0.74)

	var wall_h: float = 2.2
	var ridge_h: float = 3.6
	var gable_h: float = ridge_h - wall_h
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thick: float = 0.35
	var nov_extension: float = 0.30

	for gable_z in [-half_d, half_d]:
		var gable_steps: int = 4
		for g in range(gable_steps):
			var frac: float = float(g + 0.5) / float(gable_steps)
			var cur_w: float = (width + nov_extension * 2.0) * (1.0 - frac * 0.88)
			var gy: float = wall_h + (g + 0.5) * (gable_h / float(gable_steps))
			var gm := MeshInstance3D.new()
			var gbox := BoxMesh.new()
			gbox.size = Vector3(cur_w, (gable_h / float(gable_steps)) * 0.95, wall_thick)
			gm.mesh = gbox
			gm.material_override = mat_wood
			gm.position = Vector3(0, gy, gable_z)
			stage.add_child(gm)

		var g_col := CollisionShape3D.new()
		var g_shape := BoxShape3D.new()
		g_shape.size = Vector3(width * 0.65, gable_h, wall_thick)
		g_col.shape = g_shape
		g_col.position = Vector3(0, wall_h + gable_h * 0.5, gable_z)
		stage.add_child(g_col)

	var ridge_beam := MeshInstance3D.new()
	var ridge_box := BoxMesh.new()
	ridge_box.size = Vector3(0.35, 0.35, depth + 1.0)
	ridge_beam.mesh = ridge_box
	ridge_beam.material_override = mat_wood_dark
	ridge_beam.position = Vector3(0, ridge_h + 0.05, 0)
	stage.add_child(ridge_beam)

	var ridge_col := CollisionShape3D.new()
	var rcol_shape := BoxShape3D.new()
	rcol_shape.size = ridge_box.size
	ridge_col.shape = rcol_shape
	ridge_col.position = ridge_beam.position
	stage.add_child(ridge_col)

	var roof_pitch_rad: float = atan2(gable_h, half_w)
	var roof_slope_len: float = sqrt(pow(half_w + 0.45, 2.0) + pow(gable_h + 0.15, 2.0))
	var roof_thick: float = 0.28
	var roof_length: float = depth + 0.8

	var roof_left := MeshInstance3D.new()
	var r_box_l := BoxMesh.new()
	r_box_l.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_left.mesh = r_box_l
	roof_left.material_override = mat_sod
	roof_left.position = Vector3(-half_w * 0.5 - 0.1, wall_h + gable_h * 0.5 + 0.12, 0)
	roof_left.rotation.z = -roof_pitch_rad
	stage.add_child(roof_left)

	var roof_l_col := CollisionShape3D.new()
	var roof_l_shape := BoxShape3D.new()
	roof_l_shape.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_l_col.shape = roof_l_shape
	roof_l_col.position = roof_left.position
	roof_l_col.rotation.z = -roof_pitch_rad
	stage.add_child(roof_l_col)

	var roof_right := MeshInstance3D.new()
	var r_box_r := BoxMesh.new()
	r_box_r.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_right.mesh = r_box_r
	roof_right.material_override = mat_sod
	roof_right.position = Vector3(half_w * 0.5 + 0.1, wall_h + gable_h * 0.5 + 0.12, 0)
	roof_right.rotation.z = roof_pitch_rad
	stage.add_child(roof_right)

	var roof_r_col := CollisionShape3D.new()
	var roof_r_shape := BoxShape3D.new()
	roof_r_shape.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_r_col.shape = roof_r_shape
	roof_r_col.position = roof_right.position
	roof_r_col.rotation.z = roof_pitch_rad
	stage.add_child(roof_r_col)

	for side_sign in [-1.0, 1.0]:
		var bark_strip := MeshInstance3D.new()
		var bark_box := BoxMesh.new()
		bark_box.size = Vector3(0.06, 0.08, roof_length)
		bark_strip.mesh = bark_box
		bark_strip.material_override = mat_birch
		bark_strip.position = Vector3(side_sign * (half_w + 0.35), wall_h - 0.04, 0)
		stage.add_child(bark_strip)

		var torvvol := MeshInstance3D.new()
		var torv_box := BoxMesh.new()
		torv_box.size = Vector3(0.18, 0.18, roof_length)
		torvvol.mesh = torv_box
		torvvol.material_override = mat_wood_dark
		torvvol.position = Vector3(side_sign * (half_w + 0.38), wall_h + 0.08, 0)
		stage.add_child(torvvol)

	var ljore_frame := MeshInstance3D.new()
	var ljore_box := BoxMesh.new()
	ljore_box.size = Vector3(0.85, 0.3, 0.85)
	ljore_frame.mesh = ljore_box
	ljore_frame.material_override = mat_wood_dark
	ljore_frame.position = Vector3(0, ridge_h + 0.22, 0.1)
	stage.add_child(ljore_frame)

	return stage

## Assembles Cabin Stage 4: Central Hearth (Åre) & Sleeping Bench
static func assemble_cabin_stage_hearth(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Hearth_%d" % (randi() % 9999)
	stage.add_to_group("hearth")

	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.48, 0.46, 0.44)

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.42, 0.28, 0.16)

	var half_w := width * 0.5

	# Central hearth
	var hearth := Node3D.new()
	hearth.name = "CentralHearth"
	hearth.add_to_group("hearth")
	hearth.position = Vector3(0, 0.14, 0.2)
	stage.add_child(hearth)

	var hearth_base := MeshInstance3D.new()
	var h_box := BoxMesh.new()
	h_box.size = Vector3(1.3, 0.22, 1.3)
	hearth_base.mesh = h_box
	hearth_base.material_override = mat_stone
	hearth.add_child(hearth_base)

	var embers := MeshInstance3D.new()
	var emb_box := BoxMesh.new()
	emb_box.size = Vector3(0.8, 0.14, 0.8)
	embers.mesh = emb_box
	var mat_fire := StandardMaterial3D.new()
	mat_fire.albedo_color = Color(1.0, 0.45, 0.12)
	mat_fire.emission_enabled = true
	mat_fire.emission = Color(1.0, 0.55, 0.15)
	mat_fire.emission_energy_multiplier = 2.8
	embers.material_override = mat_fire
	embers.position = Vector3(0, 0.14, 0)
	hearth.add_child(embers)

	var fire_light := OmniLight3D.new()
	fire_light.name = "HearthFireLight"
	fire_light.light_color = Color(1.0, 0.65, 0.25)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 9.0
	fire_light.shadow_enabled = false
	fire_light.position = Vector3(0, 0.65, 0)
	hearth.add_child(fire_light)

	# Sleeping bench along right wall
	var bench := MeshInstance3D.new()
	var bench_box := BoxMesh.new()
	bench_box.size = Vector3(0.75, 0.4, depth * 0.6)
	bench.mesh = bench_box
	bench.material_override = mat_wood
	bench.position = Vector3(half_w - 0.55, 0.26, 0.2)
	stage.add_child(bench)

	return stage

## Creates a detailed transparent 3D architectural ghost preview of the complete cabin
## Shows walls, the open doorway cutout, roof slopes, and an entrance compass marker!
static func create_cabin_ghost_preview(width: float = 5.0, depth: float = 5.0, ghost_mat: Material = null) -> Node3D:
	var preview := Node3D.new()
	preview.name = "CabinGhostPreview"

	var wall_h: float = 2.2
	var ridge_h: float = 3.6
	var gable_h: float = ridge_h - wall_h
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var wall_thick: float = 0.35
	var door_w: float = 1.1
	var door_h: float = 1.95

	# 1. Floor slab
	var floor_m := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(width, 0.1, depth)
	floor_m.mesh = fbox
	floor_m.position = Vector3(0, 0.05, 0)
	preview.add_child(floor_m)

	# 2. Back Wall
	var back_m := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(width, wall_h, wall_thick)
	back_m.mesh = bbox
	back_m.position = Vector3(0, wall_h * 0.5, half_d)
	preview.add_child(back_m)

	# 3. Left Wall
	var left_m := MeshInstance3D.new()
	var lbox := BoxMesh.new()
	lbox.size = Vector3(wall_thick, wall_h, depth)
	left_m.mesh = lbox
	left_m.position = Vector3(-half_w, wall_h * 0.5, 0)
	preview.add_child(left_m)

	# 4. Right Wall
	var right_m := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(wall_thick, wall_h, depth)
	right_m.mesh = rbox
	right_m.position = Vector3(half_w, wall_h * 0.5, 0)
	preview.add_child(right_m)

	# 5. Front Wall with OPEN DOORWAY
	var front_side_w: float = (width - door_w) * 0.5
	var left_front_center_x: float = -half_w + front_side_w * 0.5
	var right_front_center_x: float = half_w - front_side_w * 0.5

	var fl_m := MeshInstance3D.new()
	var fl_box := BoxMesh.new()
	fl_box.size = Vector3(front_side_w, wall_h, wall_thick)
	fl_m.mesh = fl_box
	fl_m.position = Vector3(left_front_center_x, wall_h * 0.5, -half_d)
	preview.add_child(fl_m)

	var fr_m := MeshInstance3D.new()
	var fr_box := BoxMesh.new()
	fr_box.size = Vector3(front_side_w, wall_h, wall_thick)
	fr_m.mesh = fr_box
	fr_m.position = Vector3(right_front_center_x, wall_h * 0.5, -half_d)
	preview.add_child(fr_m)

	# Lintel above door
	var lintel_h: float = wall_h - door_h
	var lintel_m := MeshInstance3D.new()
	var lint_box := BoxMesh.new()
	lint_box.size = Vector3(door_w, lintel_h, wall_thick)
	lintel_m.mesh = lint_box
	lintel_m.position = Vector3(0, door_h + lintel_h * 0.5, -half_d)
	preview.add_child(lintel_m)

	# 6. Roof Slopes
	var roof_pitch_rad: float = atan2(gable_h, half_w)
	var roof_slope_len: float = sqrt(pow(half_w + 0.45, 2.0) + pow(gable_h + 0.15, 2.0))
	var roof_thick: float = 0.18
	var roof_length: float = depth + 0.8

	var roof_l := MeshInstance3D.new()
	var r_box_l := BoxMesh.new()
	r_box_l.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_l.mesh = r_box_l
	roof_l.position = Vector3(-half_w * 0.5 - 0.1, wall_h + gable_h * 0.5 + 0.12, 0)
	roof_l.rotation.z = -roof_pitch_rad
	preview.add_child(roof_l)

	var roof_r := MeshInstance3D.new()
	var r_box_r := BoxMesh.new()
	r_box_r.size = Vector3(roof_slope_len, roof_thick, roof_length)
	roof_r.mesh = r_box_r
	roof_r.position = Vector3(half_w * 0.5 + 0.1, wall_h + gable_h * 0.5 + 0.12, 0)
	roof_r.rotation.z = roof_pitch_rad
	preview.add_child(roof_r)

	# 7. Ridge Beam
	var ridge := MeshInstance3D.new()
	var ridge_box := BoxMesh.new()
	ridge_box.size = Vector3(0.3, 0.3, depth + 1.0)
	ridge.mesh = ridge_box
	ridge.position = Vector3(0, ridge_h + 0.05, 0)
	preview.add_child(ridge)

	# 8. Central Hearth Marker
	var hearth_m := MeshInstance3D.new()
	var h_box := BoxMesh.new()
	h_box.size = Vector3(1.2, 0.2, 1.2)
	hearth_m.mesh = h_box
	hearth_m.position = Vector3(0, 0.1, 0.2)
	preview.add_child(hearth_m)

	# 9. Entrance Threshold & Facing Arrow (So player clearly sees door direction!)
	var door_step := MeshInstance3D.new()
	var step_box := BoxMesh.new()
	step_box.size = Vector3(door_w * 0.9, 0.08, 0.7)
	door_step.mesh = step_box
	door_step.position = Vector3(0, 0.04, -half_d - 0.35)
	preview.add_child(door_step)

	if ghost_mat != null:
		apply_ghost_material_recursive(preview, ghost_mat)

	return preview

## Applies a ghost material recursively to all MeshInstance3Ds in a node tree
static func apply_ghost_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		apply_ghost_material_recursive(child, mat)


## Generates a building hierarchy given a parcel location and orientation
func assemble_tenement(lot_transform: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Tenement_%d" % lot_seed
	root.transform = lot_transform

	# 1. Foundation pass (piles over water/mud, stone sill on land)
	_assemble_foundations(root)

	# 2. Structural framing pass (post-and-beam grindverk bays)
	_assemble_framing(root)

	# 3. Wall infill & openings (timber walls, doors to alleys, shuttered openings)
	_assemble_walls(root)

	# 4. Svalgang / Exterior galleries (hallmarks of Bryggen architecture)
	_assemble_galleries(root)

	# 5. Roof assembly & cargo hoist gables
	_assemble_roofs(root)

	return root

func _assemble_foundations(parent: Node3D) -> void:
	pass

func _assemble_framing(parent: Node3D) -> void:
	pass

func _assemble_walls(parent: Node3D) -> void:
	pass

func _assemble_galleries(parent: Node3D) -> void:
	pass

func _assemble_roofs(parent: Node3D) -> void:
	pass
