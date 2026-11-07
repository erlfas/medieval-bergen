class_name BuildingAssembler
extends Node3D

## Deterministic Piece-by-Piece Procedural Assembler for Medieval Bergen 1360.
## Constructs both City Buildings (Bryggen Sjøstuer, Kontor Halls, Artisan Townhouses)
## and Valley Farmstead Buildings (Lafteverk Årestue, Grindverk Barn/Fjøs, Stabbur)
## out of discrete architectural pieces:
## - Foundation stone piers (Grunnmur), plinths, mudsills (Svillstokker), floor joists & planks
## - Lumber & Framing: Grindverk stave posts, tie beams, diagonal wind braces & Lafteverk notched logs
## - Wall Cladding: Individual vertical weatherboard planks (Stående panel) cut around apertures
## - Doors: Heavy timber jambs, lintels, low-profile walkable thresholds, planked door leaves & iron hinges
## - Windows: Recessed frames, projecting sills, crossbar mullions, crown glass panes & hinged wooden shutters
## - Galleries: Exterior Svalgang cantilevered walkways, balusters & walkable timber stairs
## - Roofs: Individual exposed rafters (Sperrer), purlins, ridge beams, bargeboards (Vindski),
##          birch-bark underlayment (Never), retainer logs (Torvvol), sod turf courses or roof shingles,
##          smoke vents (Ljore), and Hanseatic gable hoist beams (Heisebjelker).
##
## All pieces for a static building are batched by material surface into a single multi-surface
## ArrayMesh via SurfaceTool to stay well below WebGL 2.0 draw-call and MeshInstance3D budgets.

@export var lot_seed: int = 1360
@export var lot_width_meters: float = 8.0   ## Typical narrow Bergen tenement width
@export var lot_depth_meters: float = 16.0  ## Deep tenement strip stretching back from quay
@export var stories: int = 2
@export var has_waterfront_crane: bool = true
@export var has_rear_stone_cellar: bool = true

var _rng: RandomNumberGenerator

# Cached shared materials for WebGL batch efficiency
static var _shared_materials: Dictionary = {}

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = lot_seed

static func get_shared_material(key: String) -> StandardMaterial3D:
	if _shared_materials.has(key):
		return _shared_materials[key]

	var mat := StandardMaterial3D.new()
	match key:
		"wood_spruce":
			mat.albedo_color = Color(0.45, 0.30, 0.17) # Seasoned spruce / pine log lumber
			mat.roughness = 0.86
		"wood_dark":
			mat.albedo_color = Color(0.24, 0.16, 0.10) # Pine-tarred heavy structural frame
			mat.roughness = 0.90
		"wood_weathered":
			mat.albedo_color = Color(0.38, 0.31, 0.24) # Silver-brown rain-weathered boards
			mat.roughness = 0.92
		"ochre_wall":
			mat.albedo_color = Color(0.74, 0.50, 0.21) # Historical Bergen ochre yellow cladding
			mat.roughness = 0.85
		"red_wall":
			mat.albedo_color = Color(0.54, 0.21, 0.17) # Falun / madder red merchant cladding
			mat.roughness = 0.88
		"tan_wall":
			mat.albedo_color = Color(0.62, 0.47, 0.31) # Newly planed larch / birch cladding
			mat.roughness = 0.86
		"stone_foundation":
			mat.albedo_color = Color(0.46, 0.45, 0.43) # Bergen gneiss & slate foundation stone
			mat.roughness = 0.93
		"sod_roof":
			mat.albedo_color = Color(0.24, 0.42, 0.17) # Living turf / moss sod roof
			mat.roughness = 0.95
		"shingle_roof":
			mat.albedo_color = Color(0.20, 0.18, 0.17) # Tarred oak/pine roof shingles (Takspon)
			mat.roughness = 0.90
		"tile_roof":
			mat.albedo_color = Color(0.48, 0.24, 0.16) # Hanseatic clay pan tiles (Tegltak)
			mat.roughness = 0.84
		"birch_bark":
			mat.albedo_color = Color(0.86, 0.82, 0.73) # White birch bark waterproof layer (Never)
			mat.roughness = 0.78
		"iron_hardware":
			mat.albedo_color = Color(0.15, 0.15, 0.17) # Hand-forged wrought iron hinges & fittings
			mat.metallic = 0.65
			mat.roughness = 0.45
		"window_glass":
			mat.albedo_color = Color(0.52, 0.64, 0.58) # Medieval greenish-amber crown glass
			mat.roughness = 0.22
			mat.metallic = 0.25
			mat.emission_enabled = true
			mat.emission = Color(0.42, 0.34, 0.18) # Subtle interior candle/hearth reflection
			mat.emission_energy_multiplier = 0.35
		"shutter_wood":
			mat.albedo_color = Color(0.32, 0.22, 0.14) # Oiled oak window shutters & door leaves
			mat.roughness = 0.85
		_:
			mat.albedo_color = Color(0.42, 0.28, 0.16)
			mat.roughness = 0.88

	_shared_materials[key] = mat
	return mat

# =============================================================================
# LOW-LEVEL GEOMETRIC PIECE PRIMITIVES (Appended into SurfaceTool streams)
# =============================================================================

static var _shared_unit_box: BoxMesh = null
static var _shared_unit_cyl: CylinderMesh = null

## Appends an oriented 3D box piece (timber beam, plank, stone block, shutter, rafter)
static func _append_box_piece(st: SurfaceTool, size: Vector3, pos: Vector3, rot_euler: Vector3 = Vector3.ZERO) -> void:
	if _shared_unit_box == null:
		_shared_unit_box = BoxMesh.new()
		_shared_unit_box.size = Vector3.ONE
	var basis := Basis.from_euler(rot_euler) if rot_euler != Vector3.ZERO else Basis.IDENTITY
	st.append_from(_shared_unit_box, 0, Transform3D(basis.scaled(size), pos))

## Appends an oriented 3D cylinder piece (round log, piling, pulley, rope, baluster)
static func _append_cyl_piece(st: SurfaceTool, top_r: float, bot_r: float, height: float, pos: Vector3, rot_euler: Vector3 = Vector3.ZERO, radial_segs: int = 8) -> void:
	var basis := Basis.from_euler(rot_euler) if rot_euler != Vector3.ZERO else Basis.IDENTITY
	if is_equal_approx(top_r, bot_r) and radial_segs == 8:
		if _shared_unit_cyl == null:
			_shared_unit_cyl = CylinderMesh.new()
			_shared_unit_cyl.top_radius = 1.0
			_shared_unit_cyl.bottom_radius = 1.0
			_shared_unit_cyl.height = 1.0
			_shared_unit_cyl.radial_segments = 8
			_shared_unit_cyl.rings = 1
		st.append_from(_shared_unit_cyl, 0, Transform3D(basis.scaled(Vector3(top_r, height, top_r)), pos))
		return

	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = height
	cyl.radial_segments = radial_segs
	cyl.rings = 1
	st.append_from(cyl, 0, Transform3D(basis, pos))

## Commits a dictionary of SurfaceTools (keyed by material name) into a single compound MeshInstance3D
static func _commit_piece_streams(streams: Dictionary, mesh_name: String) -> MeshInstance3D:
	var arr_mesh := ArrayMesh.new()
	for mat_key in streams.keys():
		var st: SurfaceTool = streams[mat_key]
		st.generate_tangents()
		st.commit(arr_mesh)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = arr_mesh
	return mi

static func _get_stream(streams: Dictionary, mat_key: String) -> SurfaceTool:
	if not streams.has(mat_key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(get_shared_material(mat_key))
		streams[mat_key] = st
	return streams[mat_key]

# =============================================================================
# ARCHITECTURAL PIECE ASSEMBLERS (Foundation, Lumber, Doors, Windows, Roofs)
# =============================================================================

## 1. Foundation Piece Builder: Corner & Bay Stone Piers + Dry-Stone Plinth + Timber Mudsills & Plank Floor
static func _append_foundation_pieces(streams: Dictionary, width: float, depth: float, pier_depth_below: float = 0.45) -> void:
	var st_stone := _get_stream(streams, "stone_foundation")
	var st_dark := _get_stream(streams, "wood_dark")
	var st_floor := _get_stream(streams, "wood_weathered")

	var half_w := width * 0.5
	var half_d := depth * 0.5

	# Corner & intermediate cut stone piers (Grunnmurstein)
	var x_steps := maxi(2, int(round(width / 2.6)) + 1)
	var z_steps := maxi(2, int(round(depth / 2.6)) + 1)
	var pier_h := pier_depth_below + 0.18
	var pier_y := -pier_depth_below * 0.5 + 0.04

	for ix in range(x_steps):
		var px := -half_w + float(ix) / float(x_steps - 1) * width
		_append_box_piece(st_stone, Vector3(0.58, pier_h, 0.58), Vector3(px, pier_y, -half_d))
		_append_box_piece(st_stone, Vector3(0.58, pier_h, 0.58), Vector3(px, pier_y, half_d))

	for iz in range(1, z_steps - 1):
		var pz := -half_d + float(iz) / float(z_steps - 1) * depth
		_append_box_piece(st_stone, Vector3(0.58, pier_h, 0.58), Vector3(-half_w, pier_y, pz))
		_append_box_piece(st_stone, Vector3(0.58, pier_h, 0.58), Vector3(half_w, pier_y, pz))

	# Recessed dry-stone rubble plinth skirt between piers
	_append_box_piece(st_stone, Vector3(width - 0.2, pier_h * 0.85, 0.36), Vector3(0, pier_y - 0.03, -half_d))
	_append_box_piece(st_stone, Vector3(width - 0.2, pier_h * 0.85, 0.36), Vector3(0, pier_y - 0.03, half_d))
	_append_box_piece(st_stone, Vector3(0.36, pier_h * 0.85, depth - 0.2), Vector3(-half_w, pier_y - 0.03, 0))
	_append_box_piece(st_stone, Vector3(0.36, pier_h * 0.85, depth - 0.2), Vector3(half_w, pier_y - 0.03, 0))

	# Heavy tarred timber mudsills (Svillstokker) around perimeter
	var sill_h := 0.18
	var sill_y := 0.09
	_append_box_piece(st_dark, Vector3(width + 0.16, sill_h, 0.26), Vector3(0, sill_y, -half_d))
	_append_box_piece(st_dark, Vector3(width + 0.16, sill_h, 0.26), Vector3(0, sill_y, half_d))
	_append_box_piece(st_dark, Vector3(0.26, sill_h, depth + 0.16), Vector3(-half_w, sill_y, 0))
	_append_box_piece(st_dark, Vector3(0.26, sill_h, depth + 0.16), Vector3(half_w, sill_y, 0))

	# Individual planked floor boards (Gulvbord) laid across joists
	var plank_count := maxi(6, int(round(width / 0.45)))
	var plank_w := (width - 0.28) / float(plank_count)
	for p in range(plank_count):
		var px := -half_w + 0.14 + (float(p) + 0.5) * plank_w
		_append_box_piece(st_floor, Vector3(plank_w * 0.92, 0.08, depth - 0.28), Vector3(px, 0.06, 0))

## 2. Doorway Piece Builder: Jambs, Lintel, Walkable Low Threshold, Planked Door Leaf, Z-Braces & Iron Hinges
static func _append_door_piece(
	streams: Dictionary,
	center_bottom: Vector3,
	wall_yaw: float,
	door_w: float = 1.12,
	door_h: float = 1.96,
	wall_thick: float = 0.34,
	is_open: bool = true
) -> void:
	var st_dark := _get_stream(streams, "wood_dark")
	var st_leaf := _get_stream(streams, "shutter_wood")
	var st_iron := _get_stream(streams, "iron_hardware")
	var st_stone := _get_stream(streams, "stone_foundation")

	var basis := Basis(Vector3.UP, wall_yaw)
	var right := basis.x
	var forward := -basis.z # Outward normal from wall

	# 1. Stepped stone & timber threshold (<= 0.10m high for smooth kinematic floor_snap_length traversal)
	_append_box_piece(st_stone, Vector3(door_w + 0.32, 0.10, 0.46), center_bottom + Vector3(0, 0.05, 0) + forward * 0.20, Vector3(0, wall_yaw, 0))
	_append_box_piece(st_dark, Vector3(door_w + 0.16, 0.08, wall_thick + 0.08), center_bottom + Vector3(0, 0.04, 0), Vector3(0, wall_yaw, 0))

	# 2. Vertical heavy timber jamb posts (Dørstolper)
	var jamb_w := 0.15
	for sign_x: float in [-1.0, 1.0]:
		var j_pos: Vector3 = center_bottom + right * (sign_x * (door_w * 0.5 + jamb_w * 0.45)) + Vector3(0, door_h * 0.5, 0)
		_append_box_piece(st_dark, Vector3(jamb_w, door_h + 0.06, wall_thick + 0.10), j_pos, Vector3(0, wall_yaw, 0))

	# 3. Carved overhead lintel beam & rain hood (Dørbislag)
	var lintel_h := 0.22
	var lintel_pos := center_bottom + Vector3(0, door_h + lintel_h * 0.5, 0)
	_append_box_piece(st_dark, Vector3(door_w + jamb_w * 2.4, lintel_h, wall_thick + 0.12), lintel_pos, Vector3(0, wall_yaw, 0))
	var hood_pos := center_bottom + Vector3(0, door_h + lintel_h + 0.06, 0) + forward * (wall_thick * 0.5 + 0.14)
	_append_box_piece(st_dark, Vector3(door_w + 0.42, 0.07, 0.32), hood_pos, Vector3(deg_to_rad(18.0), wall_yaw, 0))

	# 4. Planked Door Leaf (Dørblad) with individual vertical boards, cross battens & wrought-iron strap hinges
	var leaf_w := door_w - 0.06
	var leaf_h := door_h - 0.08
	var hinge_pivot := center_bottom + right * (-leaf_w * 0.5) + Vector3(0, 0.06, 0) + forward * (wall_thick * 0.38)
	var leaf_yaw := wall_yaw + (deg_to_rad(82.0) if is_open else 0.0)
	var leaf_basis := Basis(Vector3.UP, leaf_yaw)
	var leaf_right := leaf_basis.x
	var leaf_fwd := -leaf_basis.z

	# 4 vertical door planks
	var board_count := 4
	var board_w := leaf_w / float(board_count)
	for b in range(board_count):
		var bx := (float(b) + 0.5) * board_w
		var b_pos := hinge_pivot + leaf_right * bx + Vector3(0, leaf_h * 0.5, 0)
		_append_box_piece(st_leaf, Vector3(board_w * 0.93, leaf_h, 0.07), b_pos, Vector3(0, leaf_yaw, 0))

	# 2 horizontal timber bracing battens across the door leaf
	for by_frac: float in [0.24, 0.76]:
		var bat_pos: Vector3 = hinge_pivot + leaf_right * (leaf_w * 0.5) + Vector3(0, leaf_h * by_frac, 0) - leaf_fwd * 0.045
		_append_box_piece(st_dark, Vector3(leaf_w * 0.92, 0.11, 0.04), bat_pos, Vector3(0, leaf_yaw, 0))

		# Wrought-iron strap hinge (Jernbeslag) on outer face
		var hinge_pos: Vector3 = hinge_pivot + leaf_right * (leaf_w * 0.34) + Vector3(0, leaf_h * by_frac, 0) + leaf_fwd * 0.042
		_append_box_piece(st_iron, Vector3(leaf_w * 0.62, 0.055, 0.02), hinge_pos, Vector3(0, leaf_yaw, 0))

	# Wrought-iron latch plate & handle near leading edge
	var handle_pos := hinge_pivot + leaf_right * (leaf_w * 0.84) + Vector3(0, leaf_h * 0.48, 0) + leaf_fwd * 0.055
	_append_box_piece(st_iron, Vector3(0.08, 0.16, 0.04), handle_pos, Vector3(0, leaf_yaw, 0))

## 3. Window Piece Builder: Recessed Frame, Sill, Crossbar Mullions, Crown Glass & Hinged Shutters
static func _append_window_piece(
	streams: Dictionary,
	center_pos: Vector3,
	wall_yaw: float,
	win_w: float = 0.86,
	win_h: float = 0.94,
	wall_thick: float = 0.30,
	has_glass: bool = true,
	has_shutters: bool = true
) -> void:
	var st_dark := _get_stream(streams, "wood_dark")
	var st_glass := _get_stream(streams, "window_glass" if has_glass else "wood_dark")

	var basis := Basis(Vector3.UP, wall_yaw)
	var right := basis.x
	var forward := -basis.z

	# 1. Projecting bottom sill (Vindusbrett) & top lintel cap
	var sill_pos := center_pos + Vector3(0, -win_h * 0.5 - 0.05, 0) + forward * 0.04
	_append_box_piece(st_dark, Vector3(win_w + 0.24, 0.10, wall_thick + 0.14), sill_pos, Vector3(0, wall_yaw, 0))

	var top_pos := center_pos + Vector3(0, win_h * 0.5 + 0.06, 0) + forward * 0.03
	_append_box_piece(st_dark, Vector3(win_w + 0.26, 0.12, wall_thick + 0.12), top_pos, Vector3(0, wall_yaw, 0))

	# 2. Left & right vertical window jambs (Vinduskarm)
	for sign_x: float in [-1.0, 1.0]:
		var j_pos: Vector3 = center_pos + right * (sign_x * (win_w * 0.5 + 0.05))
		_append_box_piece(st_dark, Vector3(0.11, win_h, wall_thick + 0.08), j_pos, Vector3(0, wall_yaw, 0))

	# 3. Recessed window pane & wooden crossbar mullions (Sprosse)
	_append_box_piece(st_glass, Vector3(win_w - 0.04, win_h - 0.04, 0.06), center_pos, Vector3(0, wall_yaw, 0))
	# Vertical mullion bar
	_append_box_piece(st_dark, Vector3(0.05, win_h - 0.02, 0.10), center_pos + forward * 0.02, Vector3(0, wall_yaw, 0))
	# Horizontal transom bar
	_append_box_piece(st_dark, Vector3(win_w - 0.02, 0.05, 0.10), center_pos + forward * 0.02, Vector3(0, wall_yaw, 0))

	# 4. Left & right hinged wooden storm shutters (Vinduslemmer) flanked open against wall
	if has_shutters:
		var st_shutter := _get_stream(streams, "shutter_wood")
		var st_iron := _get_stream(streams, "iron_hardware")
		var shut_w := win_w * 0.48
		var shut_h := win_h * 0.96
		for sign_x: float in [-1.0, 1.0]:
			var shut_yaw: float = wall_yaw - sign_x * deg_to_rad(18.0)
			var s_pos: Vector3 = center_pos + right * (sign_x * (win_w * 0.5 + shut_w * 0.5 + 0.07)) + forward * (wall_thick * 0.5 + 0.04)
			_append_box_piece(st_shutter, Vector3(shut_w, shut_h, 0.045), s_pos, Vector3(0, shut_yaw, 0))
			# Iron hinge straps on shutter
			for hy: float in [-0.30, 0.30]:
				var h_pos: Vector3 = s_pos + Vector3(0, win_h * hy, 0) + forward * 0.028
				_append_box_piece(st_iron, Vector3(shut_w * 0.78, 0.04, 0.015), h_pos, Vector3(0, shut_yaw, 0))

## 4. Lafteverk Notched Log Wall Builder (Splits individual horizontal logs around doors & windows)
## apertures: Array of Dictionaries: [{"x": offset_along_wall, "y_min": bottom_y, "y_max": top_y, "w": opening_width}]
static func _append_lafteverk_wall_courses(
	streams: Dictionary,
	wall_center_bottom: Vector3,
	wall_span: float,
	wall_h: float,
	wall_yaw: float,
	log_courses: int = 8,
	wall_thick: float = 0.30,
	nov_overhang: float = 0.32,
	apertures: Array = []
) -> void:
	var st_wood := _get_stream(streams, "wood_spruce")
	var st_dark := _get_stream(streams, "wood_dark")

	var basis := Basis(Vector3.UP, wall_yaw)
	var right := basis.x
	var course_h := wall_h / float(log_courses)
	var total_span := wall_span + nov_overhang * 2.0
	var half_span := total_span * 0.5

	for c in range(log_courses):
		var cy := (float(c) + 0.5) * course_h
		var c_bot := float(c) * course_h
		var c_top := float(c + 1) * course_h

		# Collect horizontal intervals [-half_span, +half_span] blocked by apertures at this course height
		var cuts: Array[Vector2] = []
		for ap in apertures:
			var ap_ymin: float = ap.get("y_min", 0.0)
			var ap_ymax: float = ap.get("y_max", 2.0)
			if c_top > ap_ymin + 0.02 and c_bot < ap_ymax - 0.02:
				var ap_x: float = ap.get("x", 0.0)
				var ap_hw: float = ap.get("w", 1.0) * 0.5
				cuts.append(Vector2(ap_x - ap_hw, ap_x + ap_hw))

		# Sort cuts from left to right
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

		# Build non-overlapping log segments across the course
		var seg_start := -half_span
		for cut in cuts:
			if cut.x > seg_start + 0.08:
				var seg_len := cut.x - seg_start
				var seg_mid := (seg_start + cut.x) * 0.5
				var l_pos := wall_center_bottom + right * seg_mid + Vector3(0, cy, 0)
				_append_box_piece(st_wood, Vector3(seg_len, course_h * 0.89, wall_thick), l_pos, Vector3(0, wall_yaw, 0))
				# Dark chinking / moss seam between log courses
				_append_box_piece(st_dark, Vector3(seg_len - 0.08, course_h * 0.12, wall_thick * 0.86), l_pos - Vector3(0, course_h * 0.45, 0), Vector3(0, wall_yaw, 0))
			seg_start = maxf(seg_start, cut.y)

		if half_span > seg_start + 0.08:
			var seg_len := half_span - seg_start
			var seg_mid := (seg_start + half_span) * 0.5
			var l_pos := wall_center_bottom + right * seg_mid + Vector3(0, cy, 0)
			_append_box_piece(st_wood, Vector3(seg_len, course_h * 0.89, wall_thick), l_pos, Vector3(0, wall_yaw, 0))
			_append_box_piece(st_dark, Vector3(seg_len - 0.08, course_h * 0.12, wall_thick * 0.86), l_pos - Vector3(0, course_h * 0.45, 0), Vector3(0, wall_yaw, 0))

		# Notched corner log heads (Laftehode) at both ends
		for end_sign: float in [-1.0, 1.0]:
			var head_pos: Vector3 = wall_center_bottom + right * (end_sign * (half_span + 0.04)) + Vector3(0, cy, 0)
			_append_box_piece(st_dark, Vector3(0.08, course_h * 0.78, wall_thick * 0.88), head_pos, Vector3(0, wall_yaw, 0))

## 5. Grindverk Post-and-Beam & Plank Cladding Wall Builder (For City Tenements & Barns)
static func _append_grindverk_wall_face(
	streams: Dictionary,
	wall_center_bottom: Vector3,
	wall_span: float,
	story_h: float,
	story_index: int,
	wall_yaw: float,
	cladding_mat_key: String,
	bays: int = 3,
	door_bay: int = -1,
	window_bays: Array[int] = [],
	has_glass_windows: bool = true
) -> void:
	var st_frame := _get_stream(streams, "wood_dark")
	var st_clad := _get_stream(streams, cladding_mat_key)

	var basis := Basis(Vector3.UP, wall_yaw)
	var right := basis.x
	var forward := -basis.z

	var half_span := wall_span * 0.5
	var bay_w := wall_span / float(bays)
	var base_y := float(story_index) * story_h
	var wall_thick := 0.24

	# 1. Top wall plate (Stavlegje) & story tie beam (Bete)
	var top_beam_pos := wall_center_bottom + Vector3(0, base_y + story_h - 0.10, 0) + forward * 0.02
	_append_box_piece(st_frame, Vector3(wall_span + 0.18, 0.20, wall_thick + 0.06), top_beam_pos, Vector3(0, wall_yaw, 0))

	if story_index > 0:
		var floor_beam_pos := wall_center_bottom + Vector3(0, base_y + 0.08, 0) + forward * 0.03
		_append_box_piece(st_frame, Vector3(wall_span + 0.20, 0.18, wall_thick + 0.08), floor_beam_pos, Vector3(0, wall_yaw, 0))

	# 2. Vertical stave posts (Staver) at every bay boundary
	for b_idx in range(bays + 1):
		var px := -half_span + float(b_idx) * bay_w
		var post_pos := wall_center_bottom + right * px + Vector3(0, base_y + story_h * 0.5, 0) + forward * 0.02
		_append_box_piece(st_frame, Vector3(0.20, story_h, wall_thick + 0.06), post_pos, Vector3(0, wall_yaw, 0))

	# 3. Bay infill: Individual vertical weatherboard planks (Stående panel), diagonal braces, doors & windows
	for b in range(bays):
		var bay_center_x := -half_span + (float(b) + 0.5) * bay_w
		var bay_origin := wall_center_bottom + right * bay_center_x + Vector3(0, base_y, 0)
		var inner_w := bay_w - 0.18
		var plank_count := maxi(5, int(round(inner_w / 0.24)))
		var plank_w := inner_w / float(plank_count)

		# Diagonal corner wind braces (Skråband) on outer bays
		if b == 0 or b == bays - 1:
			var brace_sign := 1.0 if b == 0 else -1.0
			var brace_pos := bay_origin + right * (-brace_sign * bay_w * 0.24) + Vector3(0, story_h - 0.52, 0) + forward * 0.03
			_append_box_piece(st_frame, Vector3(0.12, 0.85, wall_thick + 0.04), brace_pos, Vector3(0, wall_yaw, brace_sign * deg_to_rad(38.0)))

		if story_index == 0 and b == door_bay:
			# Doorway Bay: Plank cladding on left, right, and above door + full Door Piece
			var door_w := minf(1.16, inner_w * 0.68)
			var door_h := minf(1.96, story_h - 0.22)
			var side_w := (inner_w - door_w) * 0.5
			if side_w > 0.12:
				for side_s: float in [-1.0, 1.0]:
					var s_pos: Vector3 = bay_origin + right * (side_s * (door_w * 0.5 + side_w * 0.5)) + Vector3(0, story_h * 0.5, 0)
					_append_box_piece(st_clad, Vector3(side_w, story_h - 0.18, wall_thick), s_pos, Vector3(0, wall_yaw, 0))
			var over_h := story_h - door_h - 0.14
			if over_h > 0.08:
				var o_pos := bay_origin + Vector3(0, door_h + over_h * 0.5 + 0.04, 0)
				_append_box_piece(st_clad, Vector3(door_w, over_h, wall_thick), o_pos, Vector3(0, wall_yaw, 0))
			_append_door_piece(streams, bay_origin, wall_yaw, door_w, door_h, wall_thick, false)

		elif window_bays.has(b):
			# Window Bay: Individual vertical planks split below, above, and beside the window + full Window Piece
			var win_w := minf(0.88, inner_w * 0.54)
			var win_h := minf(0.92, story_h * 0.42)
			var win_cy := story_h * 0.54
			var bot_h := win_cy - win_h * 0.5
			var top_h := story_h - 0.16 - (win_cy + win_h * 0.5)

			for p in range(plank_count):
				var px := -inner_w * 0.5 + (float(p) + 0.5) * plank_w
				var z_relief := (0.015 if p % 2 == 0 else -0.01)
				if absf(px) > win_w * 0.5:
					# Full-height plank beside window
					var p_pos := bay_origin + right * px + Vector3(0, story_h * 0.5, 0) + forward * z_relief
					_append_box_piece(st_clad, Vector3(plank_w * 0.94, story_h - 0.16, wall_thick), p_pos, Vector3(0, wall_yaw, 0))
				else:
					# Bottom plank below window sill
					if bot_h > 0.10:
						var pb_pos := bay_origin + right * px + Vector3(0, bot_h * 0.5, 0) + forward * z_relief
						_append_box_piece(st_clad, Vector3(plank_w * 0.94, bot_h, wall_thick), pb_pos, Vector3(0, wall_yaw, 0))
					# Top plank above window lintel
					if top_h > 0.10:
						var pt_pos := bay_origin + right * px + Vector3(0, story_h - 0.16 - top_h * 0.5, 0) + forward * z_relief
						_append_box_piece(st_clad, Vector3(plank_w * 0.94, top_h, wall_thick), pt_pos, Vector3(0, wall_yaw, 0))

			_append_window_piece(streams, bay_origin + Vector3(0, win_cy, 0), wall_yaw, win_w, win_h, wall_thick, has_glass_windows, true)

		else:
			# Solid Cladding Bay: Individual alternating vertical board-and-batten planks
			for p in range(plank_count):
				var px := -inner_w * 0.5 + (float(p) + 0.5) * plank_w
				var z_relief := (0.015 if p % 2 == 0 else -0.01)
				var p_pos := bay_origin + right * px + Vector3(0, story_h * 0.5, 0) + forward * z_relief
				_append_box_piece(st_clad, Vector3(plank_w * 0.94, story_h - 0.16, wall_thick), p_pos, Vector3(0, wall_yaw, 0))

## 6. Roof Framing & Covering Piece Builder: Exposed Rafters, Purlins, Bargeboards, Birch Bark & Sod/Shingle Courses
static func _append_roof_assembly(
	streams: Dictionary,
	width: float,
	depth: float,
	wall_h: float,
	gable_h: float,
	roof_mat_key: String = "sod_roof",
	is_sod_roof: bool = true,
	has_ljore: bool = false,
	has_hoist_beam: bool = false
) -> void:
	var st_dark := _get_stream(streams, "wood_dark")
	var st_spruce := _get_stream(streams, "wood_spruce")
	var st_roof := _get_stream(streams, roof_mat_key)

	var half_w := width * 0.5
	var half_d := depth * 0.5
	var eaves_overhang_x := 0.48
	var eaves_overhang_z := 0.45
	var roof_len := depth + eaves_overhang_z * 2.0
	var run_x := half_w + eaves_overhang_x
	var rise_y := gable_h + 0.18
	var slope_len := sqrt(run_x * run_x + rise_y * rise_y)
	var pitch_rad := atan2(rise_y, run_x)
	var ridge_y := wall_h + gable_h

	# 1. Heavy Ridge Beam (Mønsås) & Side Purlins (Åser)
	_append_box_piece(st_dark, Vector3(0.28, 0.28, roof_len + 0.35), Vector3(0, ridge_y + 0.04, 0))
	for sign_x: float in [-1.0, 1.0]:
		_append_box_piece(st_dark, Vector3(0.18, 0.18, roof_len + 0.20), Vector3(sign_x * (half_w * 0.52), wall_h + gable_h * 0.50, 0))

	# 2. Individual Exposed Rafters (Sperrer) with overhanging rafter tails
	var rafter_count := maxi(5, int(round(depth / 1.15)) + 1)
	for r in range(rafter_count):
		var rz := -half_d - eaves_overhang_z * 0.6 + float(r) / float(rafter_count - 1) * (depth + eaves_overhang_z * 1.2)
		for sign_x: float in [-1.0, 1.0]:
			var r_pos := Vector3(sign_x * (run_x * 0.5), wall_h + rise_y * 0.46, rz)
			_append_box_piece(st_spruce, Vector3(slope_len + 0.15, 0.13, 0.12), r_pos, Vector3(0, 0, -sign_x * pitch_rad))

	# 3. Layered Roof Covering Courses (Shingle / Tile courses OR Birch Bark + Sod Turf blocks)
	var course_rows := 5
	var row_span := slope_len / float(course_rows)
	for sign_x: float in [-1.0, 1.0]:
		# Underlayment deck (Birch bark for sod roof, dark plank sheathing for shingle roof)
		var deck_mat := _get_stream(streams, "birch_bark") if is_sod_roof else st_dark
		var deck_pos := Vector3(sign_x * (run_x * 0.5), wall_h + rise_y * 0.52, 0)
		_append_box_piece(deck_mat, Vector3(slope_len + 0.06, 0.06, roof_len), deck_pos, Vector3(0, 0, -sign_x * pitch_rad))

		# Stepped overlapping courses from ridge to eaves
		for c in range(course_rows):
			var t_frac := (float(c) + 0.5) / float(course_rows) # 0 = ridge, 1 = eaves
			var cx: float = sign_x * (t_frac * run_x)
			var cy := wall_h + rise_y * (1.0 - t_frac) + 0.10
			var thick := 0.22 if is_sod_roof else 0.12
			_append_box_piece(st_roof, Vector3(row_span * 1.08, thick, roof_len - 0.04), Vector3(cx, cy, 0), Vector3(0, 0, -sign_x * (pitch_rad - deg_to_rad(1.5))))

		# Eaves retaining logs (Torvvol) & wooden hook brackets (Torvhald) for sod roofs
		if is_sod_roof:
			var st_birch := _get_stream(streams, "birch_bark")
			var eaves_x: float = sign_x * (run_x - 0.06)
			var eaves_y := wall_h - 0.02
			_append_box_piece(st_dark, Vector3(0.18, 0.18, roof_len + 0.12), Vector3(eaves_x, eaves_y + 0.12, 0))
			_append_box_piece(st_birch, Vector3(0.08, 0.07, roof_len + 0.08), Vector3(eaves_x + sign_x * 0.05, eaves_y, 0))
			for hk in range(4):
				var hz := -half_d + (float(hk) + 0.5) * (depth / 4.0)
				_append_box_piece(st_dark, Vector3(0.28, 0.10, 0.09), Vector3(eaves_x, eaves_y + 0.06, hz))

	# Ridge crest cap (Mønskam) sealing the apex between left and right slopes
	_append_box_piece(st_roof, Vector3(0.46, 0.20, roof_len + 0.04), Vector3(0, wall_h + rise_y + 0.12, 0))

	# 4. Gable Bargeboards (Vindski) & Crossed Peak Finials at front and rear
	for sign_z: float in [-1.0, 1.0]:
		var gz: float = sign_z * (roof_len * 0.5)
		for sign_x: float in [-1.0, 1.0]:
			var b_pos := Vector3(sign_x * (run_x * 0.5), wall_h + rise_y * 0.54, gz)
			_append_box_piece(st_dark, Vector3(slope_len + 0.28, 0.22, 0.08), b_pos, Vector3(0, 0, -sign_x * pitch_rad))

	# 5. Optional Rooftop Smoke Hole Frame (Ljore)
	if has_ljore:
		_append_box_piece(st_dark, Vector3(0.86, 0.28, 0.86), Vector3(0, ridge_y + 0.24, 0.15))

	# 6. Optional Hanseatic Gable Cargo Hoist Beam (Heisebjelke), Brace, Pulley & Rope
	if has_hoist_beam:
		var st_iron := _get_stream(streams, "iron_hardware")
		var beam_y := ridge_y - 0.18
		var beam_z := -half_d - 1.15
		_append_box_piece(st_dark, Vector3(0.24, 0.24, 2.7), Vector3(0, beam_y, beam_z))
		# Angled timber knee brace supporting hoist beam
		_append_box_piece(st_dark, Vector3(0.16, 1.15, 0.16), Vector3(0, beam_y - 0.45, -half_d - 0.45), Vector3(deg_to_rad(42.0), 0, 0))
		# Iron pulley wheel & hanging cargo rope
		_append_cyl_piece(st_iron, 0.22, 0.22, 0.09, Vector3(0, beam_y - 0.16, -half_d - 2.15), Vector3(0, 0, deg_to_rad(90.0)))
		_append_cyl_piece(st_spruce, 0.032, 0.032, 2.6, Vector3(0, beam_y - 1.45, -half_d - 2.15))
		_append_box_piece(st_iron, Vector3(0.16, 0.22, 0.08), Vector3(0, beam_y - 2.78, -half_d - 2.15))


# =============================================================================
# HIGH-LEVEL COMPLETE BUILDING ARCHETYPES (Piece-by-Piece Assembled)
# =============================================================================

## 1. Complete Norwegian Medieval Log Cabin / Farmhouse (Laftehytte / Årestue)
static func assemble_log_cabin(width: float = 5.4, depth: float = 6.0) -> StaticBody3D:
	var cabin := StaticBody3D.new()
	cabin.name = "Laftehytte_Cabin_%d" % (randi() % 9999)
	cabin.add_to_group("building")
	cabin.add_to_group("shelter")

	var streams: Dictionary = {}
	var wall_h: float = 2.28
	var ridge_h: float = 3.68
	var gable_h: float = ridge_h - wall_h
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var wall_thick: float = 0.32
	var door_w: float = 1.12
	var door_h: float = 1.95
	var nov_overhang: float = 0.30

	# 1. Foundation piers, plinth, mudsills & planked floor
	_append_foundation_pieces(streams, width, depth, 0.45)

	# 2. Lafteverk 8-Course Notched Log Walls with Window & Door Apertures
	var front_apertures := [
		{"x": 0.0, "y_min": 0.0, "y_max": door_h, "w": door_w}
	]
	_append_lafteverk_wall_courses(streams, Vector3(0, 0, -half_d), width, wall_h, 0.0, 8, wall_thick, nov_overhang, front_apertures)
	_append_door_piece(streams, Vector3(0, 0, -half_d), 0.0, door_w, door_h, wall_thick, true)

	var back_apertures := [
		{"x": 0.0, "y_min": 0.92, "y_max": 1.72, "w": 0.84}
	]
	_append_lafteverk_wall_courses(streams, Vector3(0, 0, half_d), width, wall_h, PI, 8, wall_thick, nov_overhang, back_apertures)
	_append_window_piece(streams, Vector3(0, 1.32, half_d), PI, 0.84, 0.80, wall_thick, true, true)

	var side_apertures := [
		{"x": 0.0, "y_min": 0.92, "y_max": 1.72, "w": 0.88}
	]
	_append_lafteverk_wall_courses(streams, Vector3(-half_w, 0, 0), depth, wall_h, deg_to_rad(-90.0), 8, wall_thick, nov_overhang, side_apertures)
	_append_window_piece(streams, Vector3(-half_w, 1.32, 0), deg_to_rad(-90.0), 0.88, 0.80, wall_thick, true, true)

	_append_lafteverk_wall_courses(streams, Vector3(half_w, 0, 0), depth, wall_h, deg_to_rad(90.0), 8, wall_thick, nov_overhang, side_apertures)
	_append_window_piece(streams, Vector3(half_w, 1.32, 0), deg_to_rad(90.0), 0.88, 0.80, wall_thick, true, true)

	# 3. Stepped Gable Log Courses (6 tapered logs per gable end)
	var st_wood := _get_stream(streams, "wood_spruce")
	var gable_courses := 6
	var g_step_h := gable_h / float(gable_courses)
	for gable_z in [-half_d, half_d]:
		for g in range(gable_courses):
			var frac := (float(g) + 0.5) / float(gable_courses)
			var cur_w := (width + nov_overhang * 1.6) * (1.0 - frac * 0.88)
			var gy := wall_h + (float(g) + 0.5) * g_step_h
			_append_box_piece(st_wood, Vector3(cur_w, g_step_h * 0.92, wall_thick), Vector3(0, gy, gable_z))

	# 4. Interior Sleeping Bench (Langbenk)
	_append_box_piece(st_wood, Vector3(0.76, 0.42, depth * 0.56), Vector3(half_w - 0.56, 0.25, 0.25))

	# 5. Roof Rafters, Purlins, Bargeboards, Birch Bark & Sod Turf Roof with Ljore Smoke Vent
	_append_roof_assembly(streams, width, depth, wall_h, gable_h, "sod_roof", true, true, false)

	var compound_mi := _commit_piece_streams(streams, "CabinPieceAssemblyMesh")
	cabin.add_child(compound_mi)

	# 6. Navigable Walk-In Physics Collisions (Floor, 4 Walls with Open Doorway Cutout, Roof)
	var front_side_w := (width - door_w) * 0.5
	var left_front_x := -half_w + front_side_w * 0.5
	var right_front_x := half_w - front_side_w * 0.5
	var lintel_h := wall_h - door_h

	_add_box_collider(cabin, Vector3(width, 0.2, depth), Vector3(0, 0.0, 0))
	_add_box_collider(cabin, Vector3(width, wall_h, wall_thick), Vector3(0, wall_h * 0.5, half_d))
	_add_box_collider(cabin, Vector3(wall_thick, wall_h, depth), Vector3(-half_w, wall_h * 0.5, 0))
	_add_box_collider(cabin, Vector3(wall_thick, wall_h, depth), Vector3(half_w, wall_h * 0.5, 0))
	_add_box_collider(cabin, Vector3(front_side_w, wall_h, wall_thick), Vector3(left_front_x, wall_h * 0.5, -half_d))
	_add_box_collider(cabin, Vector3(front_side_w, wall_h, wall_thick), Vector3(right_front_x, wall_h * 0.5, -half_d))
	_add_box_collider(cabin, Vector3(door_w, lintel_h, wall_thick), Vector3(0, door_h + lintel_h * 0.5, -half_d))

	# 7. Central Stone Hearth (Åre) Fireplace with Warm Firelight
	var hearth := Node3D.new()
	hearth.name = "CentralHearth"
	hearth.add_to_group("hearth")
	hearth.position = Vector3(0, 0.14, 0.2)
	cabin.add_child(hearth)

	var hearth_streams: Dictionary = {}
	var st_h_stone := _get_stream(hearth_streams, "stone_foundation")
	_append_box_piece(st_h_stone, Vector3(1.32, 0.22, 1.32), Vector3.ZERO)
	hearth.add_child(_commit_piece_streams(hearth_streams, "HearthStoneMesh"))

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
	fire_light.omni_range = 9.5
	fire_light.shadow_enabled = false
	fire_light.position = Vector3(0, 0.65, 0)
	hearth.add_child(fire_light)

	return cabin

## 2. City Tenement / Hanseatic Sjøstue & Valley Townhouse (Piece-by-Piece Grindverk + Cladding)
static func assemble_city_tenement(spec: Dictionary = {}) -> StaticBody3D:
	var t_name: String = spec.get("name", "Bryggen_Sjostue")
	var w: float = spec.get("width", 7.2)
	var d: float = spec.get("depth", 14.4)
	var num_stories: int = spec.get("stories", 2)
	var wall_style: String = spec.get("wall_style", "ochre_wall")
	var roof_style: String = spec.get("roof_style", "shingle_roof")
	var has_hoist: bool = spec.get("has_hoist", true)
	var has_svalgang: bool = spec.get("has_svalgang", true)
	var svalgang_side: float = spec.get("svalgang_side", -1.0)

	var building := StaticBody3D.new()
	building.name = t_name
	building.add_to_group("building")
	building.add_to_group("shelter")

	var streams: Dictionary = {}
	var story_h: float = 2.45
	var total_wall_h: float = float(num_stories) * story_h
	var gable_h: float = w * 0.44
	var half_w := w * 0.5
	var half_d := d * 0.5

	var front_bays := maxi(2, int(round(w / 2.4)))
	var side_bays := maxi(3, int(round(d / 3.0)))

	# 1. Foundation Stone Piers, Plinth, Timber Mudsills & Plank Floor
	_append_foundation_pieces(streams, w, d, 0.55)

	# 2. Multi-Story Grindverk Framing, Plank Cladding, Doors & Shuttered Windows
	for s in range(num_stories):
		var z_jut := float(s) * 0.14
		var cur_d := d + z_jut
		var front_z := -half_d - z_jut

		var f_win_bays: Array[int] = []
		for fb in range(front_bays):
			if s > 0 or fb != 0:
				f_win_bays.append(fb)
		var f_door_bay := 0 if s == 0 else -1
		_append_grindverk_wall_face(streams, Vector3(0, 0, front_z), w, story_h, s, 0.0, wall_style, front_bays, f_door_bay, f_win_bays, true)

		var r_win_bays: Array[int] = [0, front_bays - 1]
		var r_door_bay := int(front_bays / 2) if s == 0 else -1
		_append_grindverk_wall_face(streams, Vector3(0, 0, half_d), w, story_h, s, PI, wall_style, front_bays, r_door_bay, r_win_bays, true)

		var side_win_bays: Array[int] = []
		for sb in range(side_bays):
			if sb % 2 == 1:
				side_win_bays.append(sb)
		var left_door := 1 if (s == 0 and svalgang_side < 0.0) else -1
		var right_door := 1 if (s == 0 and svalgang_side > 0.0) else -1
		_append_grindverk_wall_face(streams, Vector3(-half_w, 0, -z_jut * 0.5), cur_d, story_h, s, deg_to_rad(-90.0), wall_style, side_bays, left_door, side_win_bays, true)
		_append_grindverk_wall_face(streams, Vector3(half_w, 0, -z_jut * 0.5), cur_d, story_h, s, deg_to_rad(90.0), wall_style, side_bays, right_door, side_win_bays, true)

	# 3. Gable Triangle Plank Cladding, Collar Beams & Loft Hoist Hatch
	var st_clad := _get_stream(streams, wall_style)
	var st_dark := _get_stream(streams, "wood_dark")
	var st_shutter := _get_stream(streams, "shutter_wood")
	var top_jut := float(num_stories - 1) * 0.14

	for gz_idx in range(2):
		var gz := (-half_d - top_jut) if gz_idx == 0 else half_d
		var g_steps := 7
		var step_h := gable_h / float(g_steps)
		for g in range(g_steps):
			var frac := (float(g) + 0.5) / float(g_steps)
			var cur_w := w * (1.0 - frac * 0.90)
			var gy := total_wall_h + (float(g) + 0.5) * step_h
			_append_box_piece(st_clad, Vector3(cur_w, step_h * 0.95, 0.24), Vector3(0, gy, gz))
		_append_box_piece(st_dark, Vector3(w * 0.58, 0.16, 0.28), Vector3(0, total_wall_h + gable_h * 0.42, gz))

		if gz_idx == 0 and has_hoist:
			var hatch_y := total_wall_h + gable_h * 0.36
			_append_box_piece(st_dark, Vector3(1.12, 1.18, 0.30), Vector3(0, hatch_y, gz - 0.04))
			_append_box_piece(st_shutter, Vector3(0.92, 1.02, 0.32), Vector3(0, hatch_y, gz - 0.05))

	# 4. Exterior Svalgang Gallery (Cantilevered walkway, balusters & stairs along alley side)
	if has_svalgang and num_stories >= 2:
		_append_svalgang_gallery(streams, w, d, story_h, svalgang_side)

	# 5. Roof Rafters, Purlins, Bargeboards, Shingles/Tiles & Gable Cargo Hoist Beam
	var is_sod := (roof_style == "sod_roof")
	_append_roof_assembly(streams, w, d + top_jut, total_wall_h, gable_h, roof_style, is_sod, false, has_hoist)

	var compound_mi := _commit_piece_streams(streams, "TenementPieceAssemblyMesh")
	building.add_child(compound_mi)

	_add_box_collider(building, Vector3(w, total_wall_h + gable_h * 0.5, d), Vector3(0, (total_wall_h + gable_h * 0.5) * 0.5, 0))

	return building

## Appends an authentic Bryggen Svalgang (cantilevered second-story gallery + exterior stairs)
static func _append_svalgang_gallery(streams: Dictionary, w: float, d: float, story_h: float, side_sign: float) -> void:
	var st_dark := _get_stream(streams, "wood_dark")
	var st_weathered := _get_stream(streams, "wood_weathered")

	var gal_w := 1.25
	var gal_x := side_sign * (w * 0.5 + gal_w * 0.5)
	var outer_x := side_sign * (w * 0.5 + gal_w - 0.08)
	var gal_len := d * 0.78

	var joist_count := 6
	for j in range(joist_count):
		var jz := -gal_len * 0.5 + float(j) / float(joist_count - 1) * gal_len
		_append_box_piece(st_dark, Vector3(gal_w + 0.35, 0.16, 0.16), Vector3(gal_x - side_sign * 0.10, story_h - 0.08, jz))
		_append_box_piece(st_dark, Vector3(0.14, 1.05, 0.14), Vector3(outer_x, story_h + 0.52, jz))

	_append_box_piece(st_weathered, Vector3(gal_w, 0.08, gal_len), Vector3(gal_x, story_h + 0.04, 0))
	_append_box_piece(st_dark, Vector3(0.12, 0.12, gal_len), Vector3(outer_x, story_h + 0.98, 0))
	_append_box_piece(st_weathered, Vector3(0.06, 0.52, gal_len), Vector3(outer_x, story_h + 0.42, 0))

	var step_count := 10
	var stair_run := 2.8
	for st_i in range(step_count):
		var frac := (float(st_i) + 0.5) / float(step_count)
		var sy := frac * story_h
		var sz := -gal_len * 0.5 - (1.0 - frac) * stair_run
		_append_box_piece(st_weathered, Vector3(0.95, 0.10, 0.32), Vector3(gal_x, sy, sz))

## 3. Traditional Norwegian Grindverk Barn / Livestock Shed (Fjøs & Løe) for Valley Farmsteads
static func assemble_grindverk_barn(width: float = 6.2, depth: float = 10.4) -> StaticBody3D:
	var barn := StaticBody3D.new()
	barn.name = "Grindverk_Barn_Fjos"
	barn.add_to_group("building")
	barn.add_to_group("shelter")

	var streams: Dictionary = {}
	var wall_h: float = 2.55
	var gable_h: float = 1.65
	var half_w := width * 0.5
	var half_d := depth * 0.5

	# 1. Stone piers, dry-stone base & timber sill frame
	_append_foundation_pieces(streams, width, depth, 0.50)

	# 2. Grindverk Post-and-Beam Walls with weathered board-and-batten cladding, double barn doors & vent glugger
	var side_wins: Array[int] = [0, 2]
	var empty_wins: Array[int] = []
	var rear_wins: Array[int] = [1]
	_append_grindverk_wall_face(streams, Vector3(0, 0, -half_d), width, wall_h, 0, 0.0, "wood_weathered", 3, 1, empty_wins, false)
	_append_grindverk_wall_face(streams, Vector3(0, 0, half_d), width, wall_h, 0, PI, "wood_weathered", 3, -1, rear_wins, false)
	_append_grindverk_wall_face(streams, Vector3(-half_w, 0, 0), depth, wall_h, 0, deg_to_rad(-90.0), "wood_weathered", 4, -1, side_wins, false)
	_append_grindverk_wall_face(streams, Vector3(half_w, 0, 0), depth, wall_h, 0, deg_to_rad(90.0), "wood_weathered", 4, -1, side_wins, false)

	# 3. Gable Cladding & Hayloft Pitchfork Opening (Løeglugg)
	var st_weathered := _get_stream(streams, "wood_weathered")
	var st_dark := _get_stream(streams, "wood_dark")
	for gz in [-half_d, half_d]:
		var steps := 5
		var sh := gable_h / float(steps)
		for g in range(steps):
			var frac := (float(g) + 0.5) / float(steps)
			var cw := width * (1.0 - frac * 0.88)
			_append_box_piece(st_weathered, Vector3(cw, sh * 0.94, 0.24), Vector3(0, wall_h + (float(g) + 0.5) * sh, gz))
		if gz < 0.0:
			_append_box_piece(st_dark, Vector3(0.86, 0.88, 0.30), Vector3(0, wall_h + gable_h * 0.38, gz - 0.03))

	# 4. Sod Turf Roof (Torvtak) with Exposed Rafters & Birch Bark Underlayment
	_append_roof_assembly(streams, width, depth, wall_h, gable_h, "sod_roof", true, false, false)

	barn.add_child(_commit_piece_streams(streams, "BarnPieceAssemblyMesh"))
	_add_box_collider(barn, Vector3(width, wall_h + gable_h * 0.5, depth), Vector3(0, (wall_h + gable_h * 0.5) * 0.5, 0))

	return barn

static func _add_box_collider(parent: CollisionObject3D, size: Vector3, pos: Vector3, rot_z: float = 0.0) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	if rot_z != 0.0:
		col.rotation.z = rot_z
	parent.add_child(col)


# =============================================================================
# PLAYER BUILDER STAGES & GHOST PREVIEW (Upgraded to Piece-by-Piece Meshes)
# =============================================================================

## Assembles Cabin Stage 1: Stone Footings, Plinth & Heavy Timber Plank Floor
static func assemble_cabin_stage_foundation(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Foundation_%d" % (randi() % 9999)
	stage.add_to_group("building")

	var streams: Dictionary = {}
	_append_foundation_pieces(streams, width, depth, 0.40)
	stage.add_child(_commit_piece_streams(streams, "FoundationStageCompoundMesh"))
	_add_box_collider(stage, Vector3(width, 0.2, depth), Vector3(0, 0.0, 0))
	return stage

## Assembles Cabin Stage 2: 8-Course Lafteverk Timber Walls, Shuttered Windows & Hinged Open Door
static func assemble_cabin_stage_walls(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Walls_%d" % (randi() % 9999)
	stage.add_to_group("building")

	var streams: Dictionary = {}
	var wall_h: float = 2.28
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thick: float = 0.32
	var door_w: float = 1.12
	var door_h: float = 1.95
	var nov_overhang: float = 0.30

	var front_ap := [{"x": 0.0, "y_min": 0.0, "y_max": door_h, "w": door_w}]
	_append_lafteverk_wall_courses(streams, Vector3(0, 0, -half_d), width, wall_h, 0.0, 8, wall_thick, nov_overhang, front_ap)
	_append_door_piece(streams, Vector3(0, 0, -half_d), 0.0, door_w, door_h, wall_thick, true)

	var win_ap := [{"x": 0.0, "y_min": 0.92, "y_max": 1.72, "w": 0.84}]
	_append_lafteverk_wall_courses(streams, Vector3(0, 0, half_d), width, wall_h, PI, 8, wall_thick, nov_overhang, win_ap)
	_append_window_piece(streams, Vector3(0, 1.32, half_d), PI, 0.84, 0.80, wall_thick, true, true)

	_append_lafteverk_wall_courses(streams, Vector3(-half_w, 0, 0), depth, wall_h, deg_to_rad(-90.0), 8, wall_thick, nov_overhang, win_ap)
	_append_window_piece(streams, Vector3(-half_w, 1.32, 0), deg_to_rad(-90.0), 0.84, 0.80, wall_thick, true, true)

	_append_lafteverk_wall_courses(streams, Vector3(half_w, 0, 0), depth, wall_h, deg_to_rad(90.0), 8, wall_thick, nov_overhang, win_ap)
	_append_window_piece(streams, Vector3(half_w, 1.32, 0), deg_to_rad(90.0), 0.84, 0.80, wall_thick, true, true)

	stage.add_child(_commit_piece_streams(streams, "WallsStageCompoundMesh"))

	var front_side_w := (width - door_w) * 0.5
	var left_front_x := -half_w + front_side_w * 0.5
	var right_front_x := half_w - front_side_w * 0.5
	_add_box_collider(stage, Vector3(width, wall_h, wall_thick), Vector3(0, wall_h * 0.5, half_d))
	_add_box_collider(stage, Vector3(wall_thick, wall_h, depth), Vector3(-half_w, wall_h * 0.5, 0))
	_add_box_collider(stage, Vector3(wall_thick, wall_h, depth), Vector3(half_w, wall_h * 0.5, 0))
	_add_box_collider(stage, Vector3(front_side_w, wall_h, wall_thick), Vector3(left_front_x, wall_h * 0.5, -half_d))
	_add_box_collider(stage, Vector3(front_side_w, wall_h, wall_thick), Vector3(right_front_x, wall_h * 0.5, -half_d))
	return stage

## Assembles Cabin Stage 3: Stepped Gables, Exposed Rafters, Ridge Beam & Sod Turf Roof
static func assemble_cabin_stage_roof(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Roof_%d" % (randi() % 9999)
	stage.add_to_group("building")
	stage.add_to_group("shelter")

	var streams: Dictionary = {}
	var wall_h: float = 2.28
	var ridge_h: float = 3.68
	var gable_h: float = ridge_h - wall_h
	var half_d := depth * 0.5
	var st_wood := _get_stream(streams, "wood_spruce")

	for gable_z in [-half_d, half_d]:
		var gable_steps: int = 6
		for g in range(gable_steps):
			var frac: float = float(g + 0.5) / float(gable_steps)
			var cur_w: float = (width + 0.48) * (1.0 - frac * 0.88)
			var gy: float = wall_h + (g + 0.5) * (gable_h / float(gable_steps))
			_append_box_piece(st_wood, Vector3(cur_w, (gable_h / float(gable_steps)) * 0.92, 0.32), Vector3(0, gy, gable_z))

	_append_roof_assembly(streams, width, depth, wall_h, gable_h, "sod_roof", true, true, false)
	stage.add_child(_commit_piece_streams(streams, "RoofStageCompoundMesh"))
	return stage

## Assembles Cabin Stage 4: Central Hearth (Åre) & Sleeping Bench
static func assemble_cabin_stage_hearth(width: float = 5.0, depth: float = 5.0) -> StaticBody3D:
	var stage := StaticBody3D.new()
	stage.name = "CabinStage_Hearth_%d" % (randi() % 9999)
	stage.add_to_group("hearth")

	var half_w := width * 0.5
	var streams: Dictionary = {}
	var st_wood := _get_stream(streams, "wood_spruce")
	var st_stone := _get_stream(streams, "stone_foundation")

	_append_box_piece(st_stone, Vector3(1.3, 0.22, 1.3), Vector3(0, 0.14, 0.2))
	_append_box_piece(st_wood, Vector3(0.75, 0.4, depth * 0.6), Vector3(half_w - 0.55, 0.26, 0.2))
	stage.add_child(_commit_piece_streams(streams, "HearthBenchCompoundMesh"))

	var hearth := Node3D.new()
	hearth.name = "CentralHearth"
	hearth.add_to_group("hearth")
	hearth.position = Vector3(0, 0.14, 0.2)
	stage.add_child(hearth)

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

	return stage

## Creates a transparent 3D architectural ghost preview of the complete cabin
static func create_cabin_ghost_preview(width: float = 5.0, depth: float = 5.0, ghost_mat: Material = null) -> Node3D:
	var preview := Node3D.new()
	preview.name = "CabinGhostPreview"

	var streams: Dictionary = {}
	var wall_h: float = 2.28
	var ridge_h: float = 3.68
	var gable_h: float = ridge_h - wall_h
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var wall_thick: float = 0.32
	var door_w: float = 1.12
	var door_h: float = 1.95

	_append_foundation_pieces(streams, width, depth, 0.20)
	var front_ap := [{"x": 0.0, "y_min": 0.0, "y_max": door_h, "w": door_w}]
	_append_lafteverk_wall_courses(streams, Vector3(0, 0, -half_d), width, wall_h, 0.0, 6, wall_thick, 0.28, front_ap)
	_append_lafteverk_wall_courses(streams, Vector3(0, 0, half_d), width, wall_h, PI, 6, wall_thick, 0.28, [])
	_append_lafteverk_wall_courses(streams, Vector3(-half_w, 0, 0), depth, wall_h, deg_to_rad(-90.0), 6, wall_thick, 0.28, [])
	_append_lafteverk_wall_courses(streams, Vector3(half_w, 0, 0), depth, wall_h, deg_to_rad(90.0), 6, wall_thick, 0.28, [])
	_append_roof_assembly(streams, width, depth, wall_h, gable_h, "sod_roof", true, true, false)

	var mi := _commit_piece_streams(streams, "GhostCabinCompoundMesh")
	preview.add_child(mi)

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
	var tenement := assemble_city_tenement({
		"name": "Tenement_%d" % lot_seed,
		"width": lot_width_meters,
		"depth": lot_depth_meters,
		"stories": stories,
		"has_hoist": has_waterfront_crane
	})
	tenement.transform = lot_transform
	return tenement
