class_name PlayerBuilder
extends Node3D

## Piece-by-piece building placement controller for the 1360 Bergen settler.
## Allows the settler to chop trees, collect timber, and build:
## 1. Farmhouse (Årestue)
## 2. Storehouse (Stabbur on raised stone pillars)
## 3. Barn (Grindverk Fjøs)
## 4. Sod & Birch bark roofs

signal build_mode_toggled(is_active: bool)
signal selected_piece_changed(recipe: BuildingPieceRecipe)
signal piece_placed(recipe: BuildingPieceRecipe, pos: Vector3)

@export var settler_camera: Camera3D
@export var inventory: InventoryManager
@export var max_build_distance: float = 12.0

var is_build_mode: bool = false
var selected_recipe_index: int = 0
var current_rotation_y: float = 0.0

var ghost_root: Node3D
var ghost_custom_node: Node3D
var ghost_mesh_instance: MeshInstance3D
var catalog: Array[BuildingPieceRecipe] = []

# Materials for ghost preview
var ghost_mat_valid: StandardMaterial3D
var ghost_mat_invalid: StandardMaterial3D
var _current_ghost_mat: StandardMaterial3D = null

func _ready() -> void:
	_init_catalog()
	_init_ghost_materials()
	_create_ghost_instance()

func _init_catalog() -> void:
	# 1. Laftehytte Construction Site (Log-by-Log Build)
	var r_site := BuildingPieceRecipe.new()
	r_site.piece_id = "laftehytte_construction_site"
	r_site.piece_name = "Laftehytte Construction Site (Log-by-Log Build)"
	r_site.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_site.resource_costs = { "stone": 4 } # 4 corner foundation stones to stake plot
	r_site.dimensions = Vector3(4.0, 3.2, 4.0)
	r_site.provides_shelter = true
	catalog.append(r_site)

	# 2. Complete Norwegian Log Cabin (Laftehytte / Årestue Prefab)
	var r_cabin := BuildingPieceRecipe.new()
	r_cabin.piece_id = "cabin_laftehytte"
	r_cabin.piece_name = "Norwegian Log Cabin (Complete Laftehytte)"
	r_cabin.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_cabin.resource_costs = { "timber_log": 6, "stone": 4, "birch_bark": 4, "turf": 4 }
	r_cabin.dimensions = Vector3(5.0, 3.6, 5.0)
	r_cabin.provides_shelter = true
	catalog.append(r_cabin)

	# 2. Cabin Stage 1: Stone Footings & Floor (Grunnmur)
	var r_c_fund := BuildingPieceRecipe.new()
	r_c_fund.piece_id = "cabin_stage_foundation"
	r_c_fund.piece_name = "Cabin Stage 1: Stone Sill & Floor (Grunnmur)"
	r_c_fund.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_c_fund.resource_costs = { "stone": 4, "timber_log": 2 }
	r_c_fund.dimensions = Vector3(5.0, 0.4, 5.0)
	catalog.append(r_c_fund)

	# 3. Cabin Stage 2: Lafteverk Timber Walls (Veggløft)
	var r_c_walls := BuildingPieceRecipe.new()
	r_c_walls.piece_id = "cabin_stage_walls"
	r_c_walls.piece_name = "Cabin Stage 2: Interlocking Log Walls & Door"
	r_c_walls.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_c_walls.resource_costs = { "timber_log": 4 }
	r_c_walls.dimensions = Vector3(5.0, 2.2, 5.0)
	catalog.append(r_c_walls)

	# 4. Cabin Stage 3: Gables, Ridge & Sod Roof (Torvtak)
	var r_c_roof := BuildingPieceRecipe.new()
	r_c_roof.piece_id = "cabin_stage_roof"
	r_c_roof.piece_name = "Cabin Stage 3: Torvtak Sod Roof & Smoke Hole"
	r_c_roof.category = BuildingPieceRecipe.BuildingCategory.ROOFING
	r_c_roof.resource_costs = { "timber_log": 2, "birch_bark": 4, "turf": 4 }
	r_c_roof.dimensions = Vector3(5.0, 1.4, 5.0)
	r_c_roof.provides_shelter = true
	catalog.append(r_c_roof)

	# 5. Cabin Stage 4: Central Stone Hearth & Bench (Åre Ildsted)
	var r_c_hearth := BuildingPieceRecipe.new()
	r_c_hearth.piece_id = "cabin_stage_hearth"
	r_c_hearth.piece_name = "Cabin Stage 4: Central Hearth (Åre) & Bench"
	r_c_hearth.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_c_hearth.resource_costs = { "stone": 4, "firewood": 2 }
	r_c_hearth.dimensions = Vector3(2.0, 0.6, 2.0)
	r_c_hearth.is_hearth = true
	catalog.append(r_c_hearth)

	# 6. Farmhouse Stone Footing & Mudsill (Modular Single Piece)
	var r_stone_footing := BuildingPieceRecipe.new()
	r_stone_footing.piece_id = "farm_stone_footing"
	r_stone_footing.piece_name = "Farmhouse Stone Sill & Plinth (Grunnmur)"
	r_stone_footing.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_stone_footing.resource_costs = { "stone": 4 }
	r_stone_footing.dimensions = Vector3(4.0, 0.4, 0.5)
	catalog.append(r_stone_footing)

	# 7. Hand-Hewn Floor Plank Bay (Gulvbord)
	var r_floor_bay := BuildingPieceRecipe.new()
	r_floor_bay.piece_id = "floor_plank_bay"
	r_floor_bay.piece_name = "Hewn Spruce Plank Floor Bay (Gulvbord)"
	r_floor_bay.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_floor_bay.resource_costs = { "timber_log": 2 }
	r_floor_bay.dimensions = Vector3(4.0, 0.2, 4.0)
	catalog.append(r_floor_bay)

	# 8. Solid 8-Course Notched Log Wall (Lafteverk Vegg)
	var r_solid_wall := BuildingPieceRecipe.new()
	r_solid_wall.piece_id = "laft_wall_solid"
	r_solid_wall.piece_name = "Solid Notched Log Wall (Lafteverk Vegg)"
	r_solid_wall.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_solid_wall.resource_costs = { "timber_log": 2 }
	r_solid_wall.dimensions = Vector3(4.0, 2.28, 0.35)
	catalog.append(r_solid_wall)

	# 9. Farmhouse Lafteverk Log Wall Course with Window & Shutters
	var r_lafte_wall := BuildingPieceRecipe.new()
	r_lafte_wall.piece_id = "farm_lafte_wall"
	r_lafte_wall.piece_name = "Lafteverk Log Wall & Shuttered Window"
	r_lafte_wall.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_lafte_wall.resource_costs = { "timber_log": 2 }
	r_lafte_wall.dimensions = Vector3(4.0, 2.28, 0.35)
	catalog.append(r_lafte_wall)

	# 10. Framed Timber Doorway Wall Piece (Jambs, Lintel, Planked Door & Iron Hinges)
	var r_door_piece := BuildingPieceRecipe.new()
	r_door_piece.piece_id = "modular_doorway_wall"
	r_door_piece.piece_name = "Timber Doorway Piece (Jambs, Lintel & Hinged Door)"
	r_door_piece.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_door_piece.resource_costs = { "timber_log": 2, "stone": 1 }
	r_door_piece.dimensions = Vector3(4.0, 2.28, 0.35)
	catalog.append(r_door_piece)

	# 11. Triangular Notched Log Gable (Gavlvegg)
	var r_gable := BuildingPieceRecipe.new()
	r_gable.piece_id = "laft_gable_triangle"
	r_gable.piece_name = "Triangular Notched Log Gable (Gavlvegg)"
	r_gable.category = BuildingPieceRecipe.BuildingCategory.ROOFING
	r_gable.resource_costs = { "timber_log": 2 }
	r_gable.dimensions = Vector3(5.0, 1.4, 0.35)
	catalog.append(r_gable)

	# 12. Stabbur Stone Pillar (Mushroom Pillar to stop wolves/mice)
	var r_stabbur_pillar := BuildingPieceRecipe.new()
	r_stabbur_pillar.piece_id = "stabbur_stone_pillar"
	r_stabbur_pillar.piece_name = "Stabbur Pillar (Raised Slate Post & Cap)"
	r_stabbur_pillar.category = BuildingPieceRecipe.BuildingCategory.STOREHOUSE
	r_stabbur_pillar.resource_costs = { "stone": 2, "timber_log": 1 }
	r_stabbur_pillar.dimensions = Vector3(0.6, 1.2, 0.6)
	catalog.append(r_stabbur_pillar)

	# 13. Barn Grindverk Post-and-Beam Timber Frame (Posts, Tie Beam & Wind Braces)
	var r_barn_frame := BuildingPieceRecipe.new()
	r_barn_frame.piece_id = "barn_grindverk_post"
	r_barn_frame.piece_name = "Grindverk Lumber Frame (Staves, Tie Beam & Braces)"
	r_barn_frame.category = BuildingPieceRecipe.BuildingCategory.BARN
	r_barn_frame.resource_costs = { "timber_log": 3 }
	r_barn_frame.dimensions = Vector3(4.0, 2.6, 0.35)
	catalog.append(r_barn_frame)

	# 14. Raftered Birch Bark & Sod Roof Section (Torvtak + Sperrer)
	var r_sod_roof := BuildingPieceRecipe.new()
	r_sod_roof.piece_id = "roof_sod_turf"
	r_sod_roof.piece_name = "Raftered Sod Roof Section (Rafters, Birch Bark & Turf)"
	r_sod_roof.category = BuildingPieceRecipe.BuildingCategory.ROOFING
	r_sod_roof.resource_costs = { "timber_log": 1, "birch_bark": 2, "turf": 2 }
	r_sod_roof.dimensions = Vector3(5.0, 1.4, 5.0)
	r_sod_roof.provides_shelter = true
	catalog.append(r_sod_roof)

func _init_ghost_materials() -> void:
	ghost_mat_valid = StandardMaterial3D.new()
	ghost_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat_valid.albedo_color = Color(0.2, 0.88, 0.35, 0.52)

	ghost_mat_invalid = StandardMaterial3D.new()
	ghost_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat_invalid.albedo_color = Color(0.92, 0.22, 0.22, 0.52)

func _create_ghost_instance() -> void:
	ghost_root = Node3D.new()
	ghost_root.name = "GhostRoot"
	ghost_root.visible = false
	add_child(ghost_root)

	ghost_mesh_instance = MeshInstance3D.new()
	ghost_mesh_instance.name = "GhostMesh"
	ghost_mesh_instance.mesh = BoxMesh.new()
	ghost_mesh_instance.visible = true
	ghost_root.add_child(ghost_mesh_instance)

func _unhandled_input(event: InputEvent) -> void:
	# Toggle Build Mode with 'B'
	if event.is_action_pressed("toggle_build_mode"):
		toggle_build_mode()

	if not is_build_mode:
		return

	# Rotate piece with 'R'
	if event.is_action_pressed("rotate_build_piece"):
		current_rotation_y = fmod(current_rotation_y + deg_to_rad(90.0), 2.0 * PI)

	# Cycle piece selection with Scroll or Tab / Numbers
	if event.is_action_pressed("cycle_piece_next"):
		selected_recipe_index = (selected_recipe_index + 1) % catalog.size()
		_update_ghost_mesh()
	elif event.is_action_pressed("cycle_piece_prev"):
		selected_recipe_index = (selected_recipe_index - 1 + catalog.size()) % catalog.size()
		_update_ghost_mesh()

	# Place piece on Left Click
	if event.is_action_pressed("place_build_piece"):
		_try_place_current_piece()

func toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if ghost_root:
		ghost_root.visible = is_build_mode
	build_mode_toggled.emit(is_build_mode)
	if is_build_mode:
		_update_ghost_mesh()

func _physics_process(_delta: float) -> void:
	if not is_build_mode or not settler_camera:
		return

	_update_ghost_position_and_validity()

func _update_ghost_position_and_validity() -> void:
	var space_state := get_world_3d().direct_space_state
	var ray_origin := settler_camera.global_position
	var ray_dir := -settler_camera.global_transform.basis.z
	var ray_end := ray_origin + ray_dir * max_build_distance

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var parent_body := get_parent() as CollisionObject3D
	if parent_body:
		query.exclude = [parent_body.get_rid()]
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		if ghost_root:
			ghost_root.visible = false
		return

	if ghost_root:
		ghost_root.visible = true
	var hit_pos: Vector3 = result.position

	# Snap to nearest 0.5m grid
	var snapped_x := snappedf(hit_pos.x, 0.5)
	var snapped_y := hit_pos.y
	var snapped_z := snappedf(hit_pos.z, 0.5)

	var current_recipe: BuildingPieceRecipe = catalog[selected_recipe_index]
	# All Blender-authored modules have their pivot at ground/base level (Y=0)
	var is_ground_origin := current_recipe.piece_id != "barn_grindverk_post"

	if is_ground_origin:
		ghost_root.global_position = Vector3(snapped_x, snapped_y, snapped_z)
	else:
		var y_center := snapped_y + current_recipe.dimensions.y * 0.5
		ghost_root.global_position = Vector3(snapped_x, y_center, snapped_z)

	ghost_root.rotation = Vector3(0, current_rotation_y, 0)

	# Check resource sufficiency (taking carried log into account)
	var settler: Node = get_parent()
	var is_carrying: bool = settler != null and settler.get("is_carrying_log") == true
	var needed_costs: Dictionary = current_recipe.resource_costs.duplicate()
	if is_carrying and needed_costs.get("timber_log", 0) > 0:
		needed_costs["timber_log"] -= 1
		if needed_costs["timber_log"] <= 0:
			needed_costs.erase("timber_log")

	var can_afford := inventory.has_resources(needed_costs) if inventory else true
	var target_mat := ghost_mat_valid if can_afford else ghost_mat_invalid

	if _current_ghost_mat != target_mat:
		_current_ghost_mat = target_mat
		BuildingAssembler.apply_ghost_material_recursive(ghost_root, target_mat)

func _try_place_current_piece() -> void:
	if not ghost_root or not ghost_root.visible:
		return

	var current_recipe: BuildingPieceRecipe = catalog[selected_recipe_index]

	# Check and consume resources (consume carried log if available)
	var settler: Node = get_parent()
	var is_carrying: bool = settler != null and settler.get("is_carrying_log") == true
	var needed_costs: Dictionary = current_recipe.resource_costs.duplicate()
	var used_carried_log: bool = false

	if is_carrying and needed_costs.get("timber_log", 0) > 0:
		needed_costs["timber_log"] -= 1
		if needed_costs["timber_log"] <= 0:
			needed_costs.erase("timber_log")
		used_carried_log = true

	if inventory:
		if not inventory.consume_resources(needed_costs):
			return # Insufficient resources

	if used_carried_log and settler != null and settler.has_method("consume_carried_log"):
		settler.consume_carried_log()

	# Instantiate physical building piece in the world
	var placed_piece := _spawn_piece_instance(current_recipe)
	var scene_root: Node = get_parent().get_parent()
	if not scene_root and get_tree():
		scene_root = get_tree().current_scene if get_tree().current_scene else get_tree().root
	scene_root.add_child(placed_piece)

	if current_recipe.piece_id.begins_with("cabin") or current_recipe.piece_id == "laftehytte_construction_site":
		placed_piece.global_position = ghost_root.global_position
		placed_piece.rotation.y = current_rotation_y
	else:
		placed_piece.global_transform = ghost_root.global_transform

	piece_placed.emit(current_recipe, placed_piece.global_position)

func _spawn_piece_instance(recipe: BuildingPieceRecipe) -> Node3D:
	if recipe.piece_id == "laftehytte_construction_site":
		var site_script = load("res://scripts/construction/laftehytte_construction_site.gd")
		var site := StaticBody3D.new()
		site.name = "LaftehytteSite_%d" % Time.get_ticks_msec()
		site.set_script(site_script)
		return site
	elif recipe.piece_id == "cabin_laftehytte":
		return BuildingAssembler.assemble_log_cabin(recipe.dimensions.x, recipe.dimensions.z)
	elif recipe.piece_id == "cabin_stage_foundation":
		return BuildingAssembler.assemble_cabin_stage_foundation(recipe.dimensions.x, recipe.dimensions.z)
	elif recipe.piece_id == "cabin_stage_walls":
		return BuildingAssembler.assemble_cabin_stage_walls(recipe.dimensions.x, recipe.dimensions.z)
	elif recipe.piece_id == "cabin_stage_roof":
		return BuildingAssembler.assemble_cabin_stage_roof(recipe.dimensions.x, recipe.dimensions.z)
	elif recipe.piece_id == "cabin_stage_hearth":
		return BuildingAssembler.assemble_cabin_stage_hearth(recipe.dimensions.x, recipe.dimensions.z)

	# 2. Modular piece with Blender .glb mesh + StaticBody3D physics collision
	var piece_node := StaticBody3D.new()
	piece_node.name = "%s_%d" % [recipe.piece_id, randi() % 9999]
	piece_node.add_to_group("building")
	if recipe.provides_shelter:
		piece_node.add_to_group("shelter")

	var mi := MeshInstance3D.new()
	mi.mesh = _generate_placeholder_mesh(recipe)
	piece_node.add_child(mi)

	# Collision Shape (walk-through opening for doorway piece, solid box for walls/floors)
	if recipe.piece_id == "modular_doorway_wall":
		var side_w := (recipe.dimensions.x - 1.12) * 0.5
		BuildingAssembler._add_box_collider(piece_node, Vector3(side_w, recipe.dimensions.y, recipe.dimensions.z), Vector3(-recipe.dimensions.x * 0.5 + side_w * 0.5, recipe.dimensions.y * 0.5, 0.0))
		BuildingAssembler._add_box_collider(piece_node, Vector3(side_w, recipe.dimensions.y, recipe.dimensions.z), Vector3(recipe.dimensions.x * 0.5 - side_w * 0.5, recipe.dimensions.y * 0.5, 0.0))
	else:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = recipe.dimensions
		cs.shape = box
		cs.position = Vector3(0.0, recipe.dimensions.y * 0.5, 0.0)
		piece_node.add_child(cs)

	return piece_node

func _update_ghost_mesh() -> void:
	var recipe: BuildingPieceRecipe = catalog[selected_recipe_index]
	_current_ghost_mat = null

	# Clean up previous custom ghost node
	if ghost_custom_node and is_instance_valid(ghost_custom_node):
		ghost_custom_node.queue_free()
		ghost_custom_node = null

	if recipe.piece_id == "cabin_laftehytte" or recipe.piece_id == "laftehytte_construction_site":
		ghost_mesh_instance.visible = false
		ghost_custom_node = BuildingAssembler.create_cabin_ghost_preview(recipe.dimensions.x, recipe.dimensions.z, ghost_mat_valid)
		ghost_root.add_child(ghost_custom_node)
		selected_piece_changed.emit(recipe)
		return

	ghost_mesh_instance.visible = true
	ghost_mesh_instance.mesh = _generate_placeholder_mesh(recipe)
	selected_piece_changed.emit(recipe)

func _generate_placeholder_mesh(recipe: BuildingPieceRecipe) -> Mesh:
	var piece_to_module := {
		"cabin_stage_foundation": "stage_1_foundation",
		"cabin_stage_walls": "stage_2_walls",
		"cabin_stage_roof": "stage_3_roof",
		"cabin_stage_hearth": "stage_4_hearth",
		"farm_stone_footing": "foundation_plinth_4m",
		"floor_plank_bay": "floor_plank_bay",
		"laft_wall_solid": "laft_wall_solid",
		"farm_lafte_wall": "laft_wall_window",
		"modular_doorway_wall": "laft_wall_doorway",
		"laft_gable_triangle": "laft_gable_triangle",
		"stabbur_stone_pillar": "foundation_pier",
		"roof_sod_turf": "torvtak_roof_slope",
	}

	if piece_to_module.has(recipe.piece_id):
		var mod_mesh := BuildingAssembler.get_laftehytte_module_mesh(piece_to_module[recipe.piece_id])
		if mod_mesh != null:
			return mod_mesh

	var streams: Dictionary = {}
	var w := recipe.dimensions.x
	var h := recipe.dimensions.y

	if recipe.piece_id == "barn_grindverk_post":
		var wins: Array[int] = [1]
		BuildingAssembler._append_grindverk_wall_face(streams, Vector3(0, -h * 0.5, 0), w, h, 0, 0.0, "wood_weathered", 2, -1, wins, false)

	if not streams.is_empty():
		var mi := BuildingAssembler._commit_piece_streams(streams, "PieceMesh")
		var mesh_res := mi.mesh
		mi.free()
		return mesh_res

	var box := BoxMesh.new()
	box.size = recipe.dimensions
	return box

func get_current_recipe() -> BuildingPieceRecipe:
	return catalog[selected_recipe_index]
