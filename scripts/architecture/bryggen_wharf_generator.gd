class_name BryggenWharfGenerator
extends Node

## Procedural Piece-by-Piece Generator for Medieval Bergen's Historic Hanseatic Wharf (Tyskebryggen 1360)
## and Adjacent Flat Valley Town District:
## - Heavy timber wharf quays (trebrygger) with planked decking, stringer beams, walkable access ramps,
##   and deep submerged pilings (y = -2.4m) that trigger Gerstner water depth-foam rings
## - 4 Iconic Hanseatic merchant tenement rows (Sjøstuer: Finnegården, Bellgården, Svensgården, Enhjørningsgården)
##   built piece-by-piece (stone piers, Grindverk posts/braces, plank cladding, doors, shuttered windows,
##   Svalgang galleries, exposed rafters, shingle/tile roofs, and gable cargo hoist beams)
## - Plank-paved narrow wooden alleyways (Passasjer) between tenement rows
## - 3 Rear Valley Plain Town Buildings (Skjøtstue Assembly Hall, Bakersmauet House, Øvregaten Cooperage)
## - Traditional Norwegian stockfish drying racks (Fiskehjell) & Hanseatic Kontor barter counter

static func create_bryggen_waterfront(origin: Vector3, terrain_generator: BergenTerrainGenerator = null) -> Node3D:
	var bryggen_root := Node3D.new()
	bryggen_root.name = "BryggenWaterfront_1360"
	bryggen_root.position = origin
	bryggen_root.add_to_group("bryggen")

	var mat_wharf := BuildingAssembler.get_shared_material("wood_weathered")
	var mat_timber_frame := BuildingAssembler.get_shared_material("wood_dark")
	var mat_ochre := BuildingAssembler.get_shared_material("ochre_wall")

	var mat_stockfish := StandardMaterial3D.new()
	mat_stockfish.albedo_color = Color(0.68, 0.58, 0.38) # Dried cod golden amber
	mat_stockfish.roughness = 0.8

	# -------------------------------------------------------------------------
	# 1. Piece-Built Wooden Wharf Quay Platform (Trebrygge) & Submerged Pilings
	# -------------------------------------------------------------------------
	var quay_body := _assemble_piece_quay_platform(16.0, 68.0)
	bryggen_root.add_child(quay_body)

	# -------------------------------------------------------------------------
	# 2. Front Hanseatic Merchant Tenement Row (4 Gabled Sjøstuer Facing Vågen)
	#    Oriented with -Z facing West (-X) over the quay deck (rotation.y = PI * 0.5)
	# -------------------------------------------------------------------------
	var front_tenement_specs := [
		{
			"name": "Sjostue_Finnegaarden",
			"x": 15.5, "z": -22.0,
			"width": 7.0, "depth": 14.8, "stories": 3,
			"wall_style": "ochre_wall", "roof_style": "shingle_roof",
			"has_hoist": true, "has_svalgang": true, "svalgang_side": 1.0
		},
		{
			"name": "Sjostue_Bellgaarden",
			"x": 15.5, "z": -7.5,
			"width": 7.2, "depth": 15.2, "stories": 2,
			"wall_style": "red_wall", "roof_style": "tile_roof",
			"has_hoist": true, "has_svalgang": true, "svalgang_side": -1.0
		},
		{
			"name": "Sjostue_Svensgaarden",
			"x": 15.5, "z": 7.5,
			"width": 7.0, "depth": 14.8, "stories": 3,
			"wall_style": "tan_wall", "roof_style": "shingle_roof",
			"has_hoist": true, "has_svalgang": true, "svalgang_side": 1.0
		},
		{
			"name": "Sjostue_Enhjorningsgaarden",
			"x": 15.5, "z": 22.0,
			"width": 6.8, "depth": 14.4, "stories": 2,
			"wall_style": "ochre_wall", "roof_style": "shingle_roof",
			"has_hoist": true, "has_svalgang": true, "svalgang_side": -1.0
		}
	]

	for spec in front_tenement_specs:
		var tx: float = spec["x"]
		var tz: float = spec["z"]
		var local_y := _sample_local_y(origin, tx, tz, terrain_generator)
		var tenement := BuildingAssembler.assemble_city_tenement(spec)
		tenement.position = Vector3(tx, local_y, tz)
		# Rotate +90 deg so the front gable (-Z in local space) faces West (-X) toward Vågen bay
		tenement.rotation.y = deg_to_rad(90.0)
		bryggen_root.add_child(tenement)

	# -------------------------------------------------------------------------
	# 3. Rear Valley Plain Town Row (Artisan Houses & Skjøtstue Assembly Hall)
	#    Located on the flat valley plain immediately east of the front wharf row
	# -------------------------------------------------------------------------
	var rear_town_specs := [
		{
			"name": "Town_Skjotstue_AssemblyHall",
			"x": 34.0, "z": -16.0,
			"width": 7.6, "depth": 12.6, "stories": 2,
			"wall_style": "wood_spruce", "roof_style": "sod_roof",
			"has_hoist": false, "has_svalgang": true, "svalgang_side": -1.0
		},
		{
			"name": "Town_Bakersmauet_ArtisanHouse",
			"x": 34.0, "z": 0.0,
			"width": 6.8, "depth": 11.8, "stories": 2,
			"wall_style": "red_wall", "roof_style": "tile_roof",
			"has_hoist": false, "has_svalgang": false, "svalgang_side": 1.0
		},
		{
			"name": "Town_Ovregaten_Cooperage",
			"x": 34.0, "z": 16.0,
			"width": 7.0, "depth": 12.2, "stories": 2,
			"wall_style": "tan_wall", "roof_style": "sod_roof",
			"has_hoist": true, "has_svalgang": true, "svalgang_side": 1.0
		}
	]

	for r_spec in rear_town_specs:
		var rx: float = r_spec["x"]
		var rz: float = r_spec["z"]
		var r_local_y := _sample_local_y(origin, rx, rz, terrain_generator)
		var town_house := BuildingAssembler.assemble_city_tenement(r_spec)
		town_house.position = Vector3(rx, r_local_y, rz)
		town_house.rotation.y = deg_to_rad(90.0)
		bryggen_root.add_child(town_house)

	# -------------------------------------------------------------------------
	# 4. Stockfish Drying Racks (Fiskehjell) on North & South Quay Ends
	# -------------------------------------------------------------------------
	var fish_rack_1 := _assemble_fish_rack(8.0, mat_timber_frame, mat_stockfish)
	fish_rack_1.position = Vector3(1.5, 0.36, -26.0)
	bryggen_root.add_child(fish_rack_1)

	var fish_rack_2 := _assemble_fish_rack(8.0, mat_timber_frame, mat_stockfish)
	fish_rack_2.position = Vector3(1.5, 0.36, 26.0)
	bryggen_root.add_child(fish_rack_2)

	# -------------------------------------------------------------------------
	# 5. Hanseatic Kontor Trading Counter (Interactive Barter Stall)
	# -------------------------------------------------------------------------
	var merchant_stall := _assemble_merchant_counter(mat_timber_frame, mat_wharf, mat_ochre)
	merchant_stall.position = Vector3(1.2, 0.36, -1.5)
	bryggen_root.add_child(merchant_stall)

	return bryggen_root

static func _sample_local_y(origin: Vector3, local_x: float, local_z: float, terrain_generator: BergenTerrainGenerator) -> float:
	if terrain_generator == null:
		return 0.0
	var world_y := terrain_generator.sample_height(origin.x + local_x, origin.z + local_z)
	return world_y - origin.y

## Assembles the timber wharf quay platform piece-by-piece:
## - Individual transverse deck planks, heavy stringer beams, edge curb timbers
## - Deep submerged timber pilings (reaching y = -2.4m into Vågen bay for water shader contact foam)
## - Walkable sloped boarding ramps on the landward side so the settler steps up smoothly
## - Timber alley boardwalks (Passasjer) extending between the tenement rows
static func _assemble_piece_quay_platform(width: float, length: float) -> StaticBody3D:
	var quay_body := StaticBody3D.new()
	quay_body.name = "QuayPlatform"

	var streams: Dictionary = {}
	var st_deck := BuildingAssembler._get_stream(streams, "wood_weathered")
	var st_dark := BuildingAssembler._get_stream(streams, "wood_dark")

	var half_w := width * 0.5
	var half_l := length * 0.5
	var deck_y := 0.18

	# 1. Longitudinal stringer beams under the deck
	for sx in [-half_w + 0.4, -half_w * 0.35, half_w * 0.35, half_w - 0.4]:
		BuildingAssembler._append_box_piece(st_dark, Vector3(0.32, 0.28, length), Vector3(sx, deck_y - 0.12, 0))

	# 2. Individual transverse wharf deck planks (48 plank courses along the quay)
	var plank_courses := 48
	var plank_step := length / float(plank_courses)
	for p in range(plank_courses):
		var pz := -half_l + (float(p) + 0.5) * plank_step
		BuildingAssembler._append_box_piece(st_deck, Vector3(width, 0.12, plank_step * 0.91), Vector3(0, deck_y + 0.06, pz))

	# 3. Timber Alley Boardwalks (Passasjer) running east between the tenement rows
	for alley_z in [-14.8, 0.0, 14.8]:
		BuildingAssembler._append_box_piece(st_deck, Vector3(24.0, 0.10, 3.2), Vector3(half_w + 12.0, 0.05, alley_z))
		for side_s in [-1.0, 1.0]:
			BuildingAssembler._append_box_piece(st_dark, Vector3(24.0, 0.14, 0.18), Vector3(half_w + 12.0, 0.07, alley_z + side_s * 1.55))

	# 4. Deep Submerged Wharf Pilings (Bryggepåler) & Mooring Bollards
	var piling_z_rows := 11
	for pz_i in range(piling_z_rows):
		var pz := -half_l + 2.0 + float(pz_i) / float(piling_z_rows - 1) * (length - 4.0)
		# Outer water-edge pilings extending down 3.6m into the fjord
		BuildingAssembler._append_cyl_piece(st_dark, 0.23, 0.26, 3.8, Vector3(-half_w + 0.45, -1.55, pz))
		# Mid-wharf support pilings
		BuildingAssembler._append_cyl_piece(st_dark, 0.21, 0.24, 3.2, Vector3(-2.0, -1.35, pz))
		# Mooring bollards along western quay edge every second bay
		if pz_i % 2 == 0:
			BuildingAssembler._append_cyl_piece(st_dark, 0.17, 0.19, 0.78, Vector3(-half_w + 0.55, deck_y + 0.45, pz))
			BuildingAssembler._append_box_piece(st_dark, Vector3(0.44, 0.10, 0.12), Vector3(-half_w + 0.55, deck_y + 0.68, pz))

	quay_body.add_child(BuildingAssembler._commit_piece_streams(streams, "WharfQuayPieceAssemblyMesh"))

	# Physics collision for quay platform (low-profile 0.30m deck so floor_snap_length climbs effortlessly)
	var deck_col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(width + 0.6, 0.36, length + 0.6)
	deck_col.shape = box_col
	deck_col.position = Vector3(0.0, 0.18, 0.0)
	quay_body.add_child(deck_col)

	return quay_body

## Assembles an authentic Norwegian Stockfish Drying Rack (Fiskehjell)
static func _assemble_fish_rack(length: float, mat_frame: Material, mat_fish: Material) -> StaticBody3D:
	var rack := StockfishRackInteractable.new()
	rack.name = "StockfishRack"

	var st_rack := SurfaceTool.new()
	st_rack.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_rack.set_material(mat_frame)

	var half_len := length * 0.5
	var cyl_l := CylinderMesh.new()
	cyl_l.top_radius = 0.09
	cyl_l.bottom_radius = 0.11
	cyl_l.height = 2.6
	for z_pos in [-half_len, 0.0, half_len]:
		for sign_x in [-1.0, 1.0]:
			var rot_leg := Basis(Vector3.FORWARD, -sign_x * deg_to_rad(15.0))
			st_rack.append_from(cyl_l, 0, Transform3D(rot_leg, Vector3(sign_x * 0.65, 1.3, z_pos)))

	var cyl_p := CylinderMesh.new()
	cyl_p.top_radius = 0.08
	cyl_p.bottom_radius = 0.08
	cyl_p.height = length + 0.4
	var rot_pole := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	st_rack.append_from(cyl_p, 0, Transform3D(rot_pole, Vector3(0, 2.5, 0)))

	st_rack.generate_tangents()
	var frame_mi := MeshInstance3D.new()
	frame_mi.name = "FishRackFrameCompoundMesh"
	frame_mi.mesh = st_rack.commit()
	rack.add_child(frame_mi)

	var fish_bundle := MeshInstance3D.new()
	var box_f := BoxMesh.new()
	box_f.size = Vector3(0.45, 0.85, length * 0.88)
	fish_bundle.mesh = box_f
	fish_bundle.position = Vector3(0, 1.85, 0)
	fish_bundle.material_override = mat_fish
	rack.add_child(fish_bundle)
	rack.fish_bundle_mesh = fish_bundle

	var col := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(1.6, 2.6, length + 0.4)
	col.shape = col_box
	col.position = Vector3(0, 1.3, 0)
	rack.add_child(col)

	return rack

## Assembles the Hanseatic Trading Counter & Barter Desk
static func _assemble_merchant_counter(mat_frame: Material, mat_top: Material, mat_canopy: Material) -> StaticBody3D:
	var stall := MerchantInteractable.new()
	stall.name = "HansaMerchantKontor"

	var streams: Dictionary = {}
	var st_top := BuildingAssembler._get_stream(streams, "wood_weathered")
	var st_frame := BuildingAssembler._get_stream(streams, "wood_dark")
	var st_canopy := BuildingAssembler._get_stream(streams, "ochre_wall")
	var st_iron := BuildingAssembler._get_stream(streams, "iron_hardware")

	# Counter legs, planked front & top table planks
	BuildingAssembler._append_box_piece(st_top, Vector3(1.6, 0.92, 2.8), Vector3(0, 0.46, 0))
	BuildingAssembler._append_box_piece(st_frame, Vector3(1.72, 0.08, 2.95), Vector3(0, 0.94, 0))

	# 4 corner canopy posts
	for sx in [-0.75, 0.75]:
		for sz in [-1.3, 1.3]:
			BuildingAssembler._append_box_piece(st_frame, Vector3(0.12, 2.15, 0.12), Vector3(sx, 1.08, sz))

	# Pitched merchant cloth awning roof
	BuildingAssembler._append_box_piece(st_canopy, Vector3(2.1, 0.10, 3.2), Vector3(0, 2.15, 0), Vector3(0, 0, deg_to_rad(-8.0)))

	# 2 Wooden Cargo Barrels with iron hoops beside counter
	for sign_z: float in [-1.0, 1.0]:
		var bz: float = sign_z * 1.85
		BuildingAssembler._append_cyl_piece(st_frame, 0.28, 0.28, 0.76, Vector3(0.5, 0.38, bz))
		BuildingAssembler._append_cyl_piece(st_iron, 0.29, 0.29, 0.05, Vector3(0.5, 0.56, bz))
		BuildingAssembler._append_cyl_piece(st_iron, 0.29, 0.29, 0.05, Vector3(0.5, 0.20, bz))

	stall.add_child(BuildingAssembler._commit_piece_streams(streams, "MerchantCounterPieceMesh"))

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(1.6, 1.0, 2.8)
	col.shape = box_col
	col.position = Vector3(0, 0.5, 0)
	stall.add_child(col)

	return stall
