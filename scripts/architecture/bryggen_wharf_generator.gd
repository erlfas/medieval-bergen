class_name BryggenWharfGenerator
extends Node

## Procedural Generator for Medieval Bergen's Historic Hanseatic Wharf (Tyskebryggen 1360)
## Creates:
## - Heavy timber wharf quays (trebrygger) with pilings over Vågen bay and mooring bollards
## - 2 Iconic Hanseatic merchant tenements (Sjøstuer) with hoist beams (heisebjelker)
## - Traditional Norwegian stockfish drying racks (fiskehjell)
## - Interactive Hanseatic Kontor trading post with merchant barter system

static func create_bryggen_waterfront(origin: Vector3) -> Node3D:
	var bryggen_root := Node3D.new()
	bryggen_root.name = "BryggenWaterfront_1360"
	bryggen_root.position = origin
	bryggen_root.add_to_group("bryggen")

	# Shared Materials
	var mat_wharf := StandardMaterial3D.new()
	mat_wharf.albedo_color = Color(0.28, 0.22, 0.16) # Tarred pine deck
	mat_wharf.roughness = 0.9

	var mat_wharf_piling := StandardMaterial3D.new()
	mat_wharf_piling.albedo_color = Color(0.20, 0.16, 0.12) # Wet dark submerged timber
	mat_wharf_piling.roughness = 0.85

	var mat_ochre := StandardMaterial3D.new()
	mat_ochre.albedo_color = Color(0.72, 0.48, 0.20) # Historical Bergen ochre red/yellow
	mat_ochre.roughness = 0.85

	var mat_dark_red := StandardMaterial3D.new()
	mat_dark_red.albedo_color = Color(0.52, 0.22, 0.18) # Falun red / madder red tenement
	mat_dark_red.roughness = 0.88

	var mat_timber_frame := StandardMaterial3D.new()
	mat_timber_frame.albedo_color = Color(0.25, 0.18, 0.12) # Heavy tarred framing
	mat_timber_frame.roughness = 0.92

	var mat_roof_tar := StandardMaterial3D.new()
	mat_roof_tar.albedo_color = Color(0.22, 0.20, 0.19) # Dark wood shingle / tarred planks
	mat_roof_tar.roughness = 0.92

	var mat_stockfish := StandardMaterial3D.new()
	mat_stockfish.albedo_color = Color(0.68, 0.58, 0.38) # Dried cod golden amber
	mat_stockfish.roughness = 0.8

	# -------------------------------------------------------------------------
	# 1. Heavy Wooden Wharf Quay Platform (Trebrygge)
	# -------------------------------------------------------------------------
	var quay_body := StaticBody3D.new()
	quay_body.name = "QuayPlatform"

	var deck_mesh := MeshInstance3D.new()
	var box_deck := BoxMesh.new()
	box_deck.size = Vector3(14.0, 0.45, 52.0)
	deck_mesh.mesh = box_deck
	deck_mesh.position = Vector3(0.0, 0.2, 0.0)
	deck_mesh.material_override = mat_wharf
	quay_body.add_child(deck_mesh)

	var deck_col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(14.0, 0.5, 52.0)
	deck_col.shape = box_col
	deck_col.position = deck_mesh.position
	quay_body.add_child(deck_col)

	# Water Pilings (Stolper anchored into the fjord bed)
	for sign_z in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		var piling := MeshInstance3D.new()
		var cyl_p := CylinderMesh.new()
		cyl_p.top_radius = 0.22
		cyl_p.bottom_radius = 0.25
		cyl_p.height = 3.2
		piling.mesh = cyl_p
		piling.position = Vector3(-6.6, -1.3, sign_z)
		piling.material_override = mat_wharf_piling
		quay_body.add_child(piling)

	# Mooring Bollards (Fortøyningspåler along seaward edge)
	for bz in [-15.0, -5.0, 5.0, 15.0]:
		var bollard := MeshInstance3D.new()
		var cyl_b := CylinderMesh.new()
		cyl_b.top_radius = 0.16
		cyl_b.bottom_radius = 0.18
		cyl_b.height = 0.75
		bollard.mesh = cyl_b
		bollard.position = Vector3(-6.7, 0.65, bz)
		bollard.material_override = mat_wharf_piling
		quay_body.add_child(bollard)

	bryggen_root.add_child(quay_body)

	# -------------------------------------------------------------------------
	# 2. Hanseatic Merchant Tenements (Sjøstue 1 - Ochre & Sjøstue 2 - Red)
	# -------------------------------------------------------------------------
	var tenement_1 := _assemble_sjostue(7.4, 15.0, 5.6, mat_ochre, mat_timber_frame, mat_roof_tar, "Sjøstue_Ochsenkopf")
	tenement_1.position = Vector3(11.0, 0.0, -11.0)
	bryggen_root.add_child(tenement_1)

	var tenement_2 := _assemble_sjostue(7.4, 15.0, 5.6, mat_dark_red, mat_timber_frame, mat_roof_tar, "Sjøstue_Bellgaarden")
	tenement_2.position = Vector3(11.0, 0.0, 6.0)
	bryggen_root.add_child(tenement_2)

	# -------------------------------------------------------------------------
	# 3. Stockfish Drying Racks (Fiskehjell)
	# -------------------------------------------------------------------------
	var fish_rack_1 := _assemble_fish_rack(8.0, mat_timber_frame, mat_stockfish)
	fish_rack_1.position = Vector3(2.5, 0.45, -20.0)
	bryggen_root.add_child(fish_rack_1)

	var fish_rack_2 := _assemble_fish_rack(8.0, mat_timber_frame, mat_stockfish)
	fish_rack_2.position = Vector3(2.5, 0.45, 20.0)
	bryggen_root.add_child(fish_rack_2)

	# -------------------------------------------------------------------------
	# 4. Hanseatic Kontor Trading Counter (Interactive Barter Stall)
	# -------------------------------------------------------------------------
	var merchant_stall := _assemble_merchant_counter(mat_timber_frame, mat_wharf, mat_ochre)
	merchant_stall.position = Vector3(1.5, 0.45, -2.5)
	bryggen_root.add_child(merchant_stall)

	return bryggen_root

## Assembles a historical 2-story Hanseatic tenement house (Sjøstue)
static func _assemble_sjostue(w: float, d: float, h: float, mat_wall: Material, mat_frame: Material, mat_roof: Material, t_name: String) -> StaticBody3D:
	var building := StaticBody3D.new()
	building.name = t_name
	building.add_to_group("building")
	building.add_to_group("shelter")

	var half_w := w * 0.5
	var half_d := d * 0.5
	var wall_h := h * 0.72
	var gable_h := h - wall_h

	# Main Structure Block
	var main_block := MeshInstance3D.new()
	var box_m := BoxMesh.new()
	box_m.size = Vector3(w, wall_h, d)
	main_block.mesh = box_m
	main_block.position = Vector3(0, wall_h * 0.5, 0)
	main_block.material_override = mat_wall
	building.add_child(main_block)

	var col_body := CollisionShape3D.new()
	var box_c := BoxShape3D.new()
	box_c.size = Vector3(w, wall_h, d)
	col_body.shape = box_c
	col_body.position = main_block.position
	building.add_child(col_body)

	# Front Timber Gable Facade
	var gable := MeshInstance3D.new()
	var g_box := BoxMesh.new()
	g_box.size = Vector3(w * 0.95, gable_h, 0.4)
	gable.mesh = g_box
	gable.position = Vector3(0, wall_h + gable_h * 0.5, -half_d + 0.2)
	gable.material_override = mat_wall
	building.add_child(gable)

	# Roof Slopes (Steep pitched wood shingle roof)
	var roof_pitch := deg_to_rad(45.0)
	var slope_len := sqrt(pow(half_w + 0.4, 2.0) + pow(gable_h + 0.2, 2.0))
	for sign_x in [-1.0, 1.0]:
		var r_slope := MeshInstance3D.new()
		var r_box := BoxMesh.new()
		r_box.size = Vector3(slope_len, 0.25, d + 0.6)
		r_slope.mesh = r_box
		r_slope.position = Vector3(sign_x * (half_w * 0.5 + 0.05), wall_h + gable_h * 0.52, 0)
		r_slope.rotation.z = sign_x * roof_pitch
		r_slope.material_override = mat_roof
		building.add_child(r_slope)

	# Iconic Hanseatic Hoist Gantry Beam (Heisebjelke) extending forward from peak
	var hoist_beam := MeshInstance3D.new()
	var h_box := BoxMesh.new()
	h_box.size = Vector3(0.25, 0.25, 2.8)
	hoist_beam.mesh = h_box
	hoist_beam.position = Vector3(0, wall_h + gable_h + 0.05, -half_d - 0.9)
	hoist_beam.material_override = mat_frame
	building.add_child(hoist_beam)

	# Hanging cargo rope & hook
	var hoist_rope := MeshInstance3D.new()
	var cyl_r := CylinderMesh.new()
	cyl_r.top_radius = 0.03
	cyl_r.bottom_radius = 0.03
	cyl_r.height = 2.2
	hoist_rope.mesh = cyl_r
	hoist_rope.position = Vector3(0, wall_h + gable_h - 1.05, -half_d - 2.1)
	hoist_rope.material_override = mat_frame
	building.add_child(hoist_rope)

	return building

## Assembles an authentic Norwegian Stockfish Drying Rack (Fiskehjell)
static func _assemble_fish_rack(length: float, mat_frame: Material, mat_fish: Material) -> Node3D:
	var rack := Node3D.new()
	rack.name = "StockfishRack"

	# A-frame Timber Uprights
	var half_len := length * 0.5
	for z_pos in [-half_len, half_len]:
		for sign_x in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var cyl_l := CylinderMesh.new()
			cyl_l.top_radius = 0.09
			cyl_l.bottom_radius = 0.11
			cyl_l.height = 2.6
			leg.mesh = cyl_l
			leg.position = Vector3(sign_x * 0.65, 1.3, z_pos)
			leg.rotation.z = -sign_x * deg_to_rad(15.0)
			leg.material_override = mat_frame
			rack.add_child(leg)

	# Top Horizontal Ridge Pole (Rie)
	var pole := MeshInstance3D.new()
	var cyl_p := CylinderMesh.new()
	cyl_p.top_radius = 0.08
	cyl_p.bottom_radius = 0.08
	cyl_p.height = length + 0.4
	pole.mesh = cyl_p
	pole.rotation.x = deg_to_rad(90.0)
	pole.position = Vector3(0, 2.5, 0)
	pole.material_override = mat_frame
	rack.add_child(pole)

	# Suspended Bundles of Dried Cod (Tørrfisk)
	var fish_bundle := MeshInstance3D.new()
	var box_f := BoxMesh.new()
	box_f.size = Vector3(0.45, 0.85, length * 0.88)
	fish_bundle.mesh = box_f
	fish_bundle.position = Vector3(0, 1.85, 0)
	fish_bundle.material_override = mat_fish
	rack.add_child(fish_bundle)

	return rack

## Assembles the Hanseatic Trading Counter & Barter Desk
static func _assemble_merchant_counter(mat_frame: Material, mat_top: Material, mat_canopy: Material) -> StaticBody3D:
	var stall := MerchantInteractable.new()
	stall.name = "HansaMerchantKontor"

	# Heavy Timber Counter Table
	var counter_m := MeshInstance3D.new()
	var box_c := BoxMesh.new()
	box_c.size = Vector3(1.6, 0.95, 2.8)
	counter_m.mesh = box_c
	counter_m.position = Vector3(0, 0.48, 0)
	counter_m.material_override = mat_top
	stall.add_child(counter_m)

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(1.6, 1.0, 2.8)
	col.shape = box_col
	col.position = counter_m.position
	stall.add_child(col)

	# Striped Merchant Cloth Awning / Canopy Roof
	var awning := MeshInstance3D.new()
	var box_a := BoxMesh.new()
	box_a.size = Vector3(2.0, 0.1, 3.2)
	awning.mesh = box_a
	awning.position = Vector3(0, 2.1, 0)
	awning.rotation.z = deg_to_rad(-8.0)
	awning.material_override = mat_canopy
	stall.add_child(awning)

	# 2 Wooden Cargo Barrels beside counter
	for sign_z in [-1.0, 1.0]:
		var barrel := MeshInstance3D.new()
		var cyl_b := CylinderMesh.new()
		cyl_b.top_radius = 0.28
		cyl_b.bottom_radius = 0.28
		cyl_b.height = 0.75
		barrel.mesh = cyl_b
		barrel.position = Vector3(0.9, 0.38, sign_z * 0.9)
		barrel.material_override = mat_frame
		stall.add_child(barrel)

	return stall
