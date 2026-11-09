extends SceneTree

func _init() -> void:
	print("=== Running Character Modular System & Weapons Test ===")

	var box_man_script = load("res://scripts/player/box_man_model.gd")
	if not box_man_script:
		printerr("FAIL: Could not load box_man_model.gd")
		quit(1)
		return

	var model = Node3D.new()
	model.set_script(box_man_script)
	root.add_child(model)
	model._build_box_man()

	# 1. Verify Modular 3D Meshes exist and are parented to proper bone pivots
	assert(model.get("char_head_mesh") != null, "Character head mesh should exist")
	assert(model.get("char_torso_mesh") != null, "Character torso mesh should exist")
	assert(model.get("char_sleeve_l_mesh") != null, "Character left sleeve mesh should exist")
	assert(model.get("char_sleeve_r_mesh") != null, "Character right sleeve mesh should exist")
	assert(model.get("char_hand_l_mesh") != null, "Character left hand mesh should exist")
	assert(model.get("char_hand_r_mesh") != null, "Character right hand mesh should exist")
	assert(model.get("char_leg_l_mesh") != null, "Character left leg mesh should exist")
	assert(model.get("char_leg_r_mesh") != null, "Character right leg mesh should exist")
	assert(model.get("helmet_mesh_instance") != null, "Character helmet mesh should exist")
	assert(model.get("belt_mesh_instance") != null, "Character belt mesh should exist")
	print("✓ Base body, clothes, helmet, and belt modular instances created on skeleton pivots successfully!")

	# 2. Verify Bow and Arrow 3D models
	var bow_mesh: Node3D = model.get("bow_mesh")
	assert(bow_mesh != null, "Bow mesh should exist")
	var bow_3d = bow_mesh.get_node_or_null("Bow3DModel")
	assert(bow_3d != null, "Bow3DModel (bow.glb) should be attached to bow_mesh")

	var arrow_hand_mesh: Node3D = model.get("arrow_hand_mesh")
	assert(arrow_hand_mesh != null, "Arrow hand mesh should exist")
	var arrow_3d = arrow_hand_mesh.get_node_or_null("Arrow3DModel")
	assert(arrow_3d != null, "Arrow3DModel (arrow.glb) should be attached to arrow_hand_mesh")
	print("✓ Bow.glb and Arrow.glb properly attached to character sockets!")

	# 3. Verify Sword 3D model & Sheath
	var sword_mesh: Node3D = model.get("sword_mesh")
	assert(sword_mesh != null, "Sword hand mesh should exist")
	var sword_3d = sword_mesh.get_node_or_null("Sword3DModel")
	assert(sword_3d != null, "Sword3DModel (sword.glb) should be attached to sword_mesh")

	var stowed_sword_mesh: Node3D = model.get("stowed_sword_mesh")
	assert(stowed_sword_mesh != null, "Stowed hip sword mesh should exist")
	var stowed_3d = stowed_sword_mesh.get_node_or_null("SheathedSword3DModel")
	assert(stowed_3d != null, "SheathedSword3DModel (sword.glb) should be attached to hip sheath")
	print("✓ Sword.glb hand mesh and hip sheath properly attached!")

	# 4. Verify Slot switching & Sword sheathing logic
	# When Axe is equipped (Slot 1), sword should be in hip sheath
	model.set_equipped_item(1)
	assert(sword_mesh.visible == false, "Sword in hand should be hidden when Axe equipped")
	assert(stowed_sword_mesh.visible == true, "Sword should be visible in hip sheath when Axe equipped")

	# When Sword is equipped (Slot 7), sword should be drawn in hand
	model.set_equipped_item(7)
	assert(sword_mesh.visible == true, "Sword in hand should be visible when Sword equipped")
	assert(stowed_sword_mesh.visible == false, "Hip sheath should be empty when Sword equipped")
	print("✓ Weapon sheathing and draw logic validated!")

	# 5. Verify Bow Aiming & Arrow visibility
	model.set_equipped_item(4) # BOW
	model.set_bow_aim(false, 0.0)
	assert(bow_mesh.visible == true, "Bow should be visible")
	assert(arrow_hand_mesh.visible == false, "Held arrow should be hidden when not aiming")
	model.set_bow_aim(true, 0.8)
	assert(arrow_hand_mesh.visible == true, "Held arrow should be visible when drawing bow")
	print("✓ Bow aiming and held arrow tension validated!")

	# 6. Verify ArrowProjectile uses arrow.glb
	var arrow_proj_script = load("res://scripts/items/arrow_projectile.gd")
	assert(arrow_proj_script != null, "ArrowProjectile script should load")
	var arrow_proj = arrow_proj_script.new()
	root.add_child(arrow_proj)
	if arrow_proj.get("arrow_model") == null:
		arrow_proj._build_arrow_model()
	assert(arrow_proj.get("arrow_model") != null, "ArrowProjectile should instantiate arrow.glb model")
	arrow_proj.free()
	print("✓ ArrowProjectile 3D model validated!")

	# 7. Verify Clothing toggles & Clothed vs Naked layer switching
	model.set_clothing_visible(false)
	assert(model.get("char_torso_mesh").visible == false, "Cloths torso should be hidden when clothing is off")
	assert(model.get("char_torso_naked_mesh").visible == true, "Naked torso should be visible when clothing is off")
	model.set_clothing_visible(true)
	assert(model.get("char_torso_mesh").visible == true, "Cloths torso should be visible when clothing is on")
	assert(model.get("char_torso_naked_mesh").visible == false, "Naked torso should be hidden when clothing is on")

	model.set_helmet_visible(false)
	assert(model.get("helmet_mesh_instance").visible == false, "Helmet should be toggleable off")
	model.set_helmet_visible(true)
	assert(model.get("helmet_mesh_instance").visible == true, "Helmet should be toggleable on")

	model.set_belt_visible(false)
	assert(model.get("belt_mesh_instance").visible == false, "Belt should be toggleable off")
	model.set_belt_visible(true)
	assert(model.get("belt_mesh_instance").visible == true, "Belt should be toggleable on")
	print("✓ Modular clothing, naked layer toggles, and armor visibility validated!")

	# 8. Verify Greybox placeholder meshes are hidden
	var torso_child_box = model.get("torso_node").get_child(0)
	assert(torso_child_box.visible == false, "Procedural placeholder torso box mesh must be hidden")
	var head_child_box = model.get("head_node").get_child(0)
	assert(head_child_box.visible == false, "Procedural placeholder head box mesh must be hidden")
	print("✓ Placeholder greybox meshes successfully hidden (no mutant greybox mixture)!")

	# 8. Clean up
	model.free()
	print("✓ ALL TESTS PASSED SUCCESSFULLY!")
	quit(0)
