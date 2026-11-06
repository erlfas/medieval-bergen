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

var ghost_mesh_instance: MeshInstance3D
var catalog: Array[BuildingPieceRecipe] = []

# Materials for ghost preview
var ghost_mat_valid: StandardMaterial3D
var ghost_mat_invalid: StandardMaterial3D

func _ready() -> void:
	_init_catalog()
	_init_ghost_materials()
	_create_ghost_instance()

func _init_catalog() -> void:
	# 1. Complete Norwegian Log Cabin (Laftehytte / Årestue)
	var r_cabin := BuildingPieceRecipe.new()
	r_cabin.piece_id = "cabin_laftehytte"
	r_cabin.piece_name = "Norwegian Log Cabin (Laftehytte)"
	r_cabin.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_cabin.resource_costs = { "timber_log": 6, "stone": 4, "birch_bark": 4, "turf": 4 }
	r_cabin.dimensions = Vector3(5.0, 3.6, 5.0)
	r_cabin.provides_shelter = true
	catalog.append(r_cabin)

	# 2. Farmhouse Stone Footing
	var r_stone_footing := BuildingPieceRecipe.new()
	r_stone_footing.piece_id = "farm_stone_footing"
	r_stone_footing.piece_name = "Farmhouse Stone Sill (Grunnmur)"
	r_stone_footing.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_stone_footing.resource_costs = { "stone": 4 }
	r_stone_footing.dimensions = Vector3(4.0, 0.4, 0.5)
	catalog.append(r_stone_footing)

	# 2. Farmhouse Lafteverk Log Wall Course
	var r_lafte_wall := BuildingPieceRecipe.new()
	r_lafte_wall.piece_id = "farm_lafte_wall"
	r_lafte_wall.piece_name = "Lafteverk Timber Wall (Spruce Logs)"
	r_lafte_wall.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_lafte_wall.resource_costs = { "timber_log": 2 }
	r_lafte_wall.dimensions = Vector3(4.0, 1.0, 0.35)
	catalog.append(r_lafte_wall)

	# 3. Farmhouse Central Stone Hearth (Åre)
	var r_hearth := BuildingPieceRecipe.new()
	r_hearth.piece_id = "farm_stone_hearth"
	r_hearth.piece_name = "Central Hearth (Åre Fireplace)"
	r_hearth.category = BuildingPieceRecipe.BuildingCategory.FARMHOUSE
	r_hearth.resource_costs = { "stone": 6, "firewood": 2 }
	r_hearth.dimensions = Vector3(1.4, 0.35, 1.4)
	r_hearth.is_hearth = true
	catalog.append(r_hearth)

	# 4. Stabbur Stone Pillar (Mushroom Pillar to stop wolves/mice)
	var r_stabbur_pillar := BuildingPieceRecipe.new()
	r_stabbur_pillar.piece_id = "stabbur_stone_pillar"
	r_stabbur_pillar.piece_name = "Stabbur Pillar (Raised Slate Post)"
	r_stabbur_pillar.category = BuildingPieceRecipe.BuildingCategory.STOREHOUSE
	r_stabbur_pillar.resource_costs = { "stone": 3, "timber_log": 1 }
	r_stabbur_pillar.dimensions = Vector3(0.5, 1.2, 0.5)
	catalog.append(r_stabbur_pillar)

	# 5. Stabbur Timber Wall & Food Drying Loft
	var r_stabbur_wall := BuildingPieceRecipe.new()
	r_stabbur_wall.piece_id = "stabbur_log_wall"
	r_stabbur_wall.piece_name = "Stabbur Heavy Log Wall"
	r_stabbur_wall.category = BuildingPieceRecipe.BuildingCategory.STOREHOUSE
	r_stabbur_wall.resource_costs = { "timber_log": 3 }
	r_stabbur_wall.dimensions = Vector3(3.0, 1.2, 0.4)
	catalog.append(r_stabbur_wall)

	# 6. Barn Grindverk Post-and-Beam Timber Frame
	var r_barn_frame := BuildingPieceRecipe.new()
	r_barn_frame.piece_id = "barn_grindverk_post"
	r_barn_frame.piece_name = "Barn Grindverk Timber Frame"
	r_barn_frame.category = BuildingPieceRecipe.BuildingCategory.BARN
	r_barn_frame.resource_costs = { "timber_log": 3 }
	r_barn_frame.dimensions = Vector3(0.4, 3.2, 0.4)
	catalog.append(r_barn_frame)

	# 7. Timber Roof Rafter (A-Frame)
	var r_rafter := BuildingPieceRecipe.new()
	r_rafter.piece_id = "roof_rafter_pair"
	r_rafter.piece_name = "A-Frame Timber Roof Rafter"
	r_rafter.category = BuildingPieceRecipe.BuildingCategory.ROOFING
	r_rafter.resource_costs = { "timber_log": 2 }
	r_rafter.dimensions = Vector3(4.0, 2.0, 0.3)
	catalog.append(r_rafter)

	# 8. Birch Bark & Sod Roof Tile (Torvtak)
	var r_sod_roof := BuildingPieceRecipe.new()
	r_sod_roof.piece_id = "roof_sod_turf"
	r_sod_roof.piece_name = "Sod Turf Tile (Birch Bark + Turf)"
	r_sod_roof.category = BuildingPieceRecipe.BuildingCategory.ROOFING
	r_sod_roof.resource_costs = { "birch_bark": 2, "turf": 2 }
	r_sod_roof.dimensions = Vector3(2.0, 0.25, 2.0)
	catalog.append(r_sod_roof)

func _init_ghost_materials() -> void:
	ghost_mat_valid = StandardMaterial3D.new()
	ghost_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat_valid.albedo_color = Color(0.2, 0.85, 0.3, 0.5)

	ghost_mat_invalid = StandardMaterial3D.new()
	ghost_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat_invalid.albedo_color = Color(0.9, 0.2, 0.2, 0.5)

func _create_ghost_instance() -> void:
	ghost_mesh_instance = MeshInstance3D.new()
	ghost_mesh_instance.mesh = BoxMesh.new()
	ghost_mesh_instance.visible = false
	add_child(ghost_mesh_instance)

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
	ghost_mesh_instance.visible = is_build_mode
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
		ghost_mesh_instance.visible = false
		return

	ghost_mesh_instance.visible = true
	var hit_pos: Vector3 = result.position
	var normal: Vector3 = result.normal

	# Snap to nearest 0.5m grid
	var snapped_x := snappedf(hit_pos.x, 0.5)
	var snapped_y := hit_pos.y
	var snapped_z := snappedf(hit_pos.z, 0.5)

	var current_recipe: BuildingPieceRecipe = catalog[selected_recipe_index]
	var y_center := snapped_y + current_recipe.dimensions.y * 0.5
	ghost_mesh_instance.global_position = Vector3(snapped_x, y_center, snapped_z)
	ghost_mesh_instance.rotation = Vector3(0, current_rotation_y, 0)

	# Check resource sufficiency (taking carried log into account)
	var settler: Node = get_parent()
	var is_carrying: bool = settler != null and settler.get("is_carrying_log") == true
	var needed_costs: Dictionary = current_recipe.resource_costs.duplicate()
	if is_carrying and needed_costs.get("timber_log", 0) > 0:
		needed_costs["timber_log"] -= 1
		if needed_costs["timber_log"] <= 0:
			needed_costs.erase("timber_log")

	var can_afford := inventory.has_resources(needed_costs) if inventory else true
	ghost_mesh_instance.material_override = ghost_mat_valid if can_afford else ghost_mat_invalid

func _try_place_current_piece() -> void:
	if not ghost_mesh_instance.visible:
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
			return # Insufficient timber logs / stone

	if used_carried_log and settler != null and settler.has_method("consume_carried_log"):
		settler.consume_carried_log()

	# Instantiate physical building piece in the world
	var placed_piece := _spawn_piece_instance(current_recipe)
	get_parent().get_parent().add_child(placed_piece)

	if current_recipe.piece_id == "cabin_laftehytte":
		# Cabin origin is at floor level (Y=0)
		var base_y := ghost_mesh_instance.global_position.y - current_recipe.dimensions.y * 0.5
		placed_piece.global_position = Vector3(ghost_mesh_instance.global_position.x, base_y, ghost_mesh_instance.global_position.z)
		placed_piece.rotation.y = current_rotation_y
	else:
		placed_piece.global_transform = ghost_mesh_instance.global_transform

	piece_placed.emit(current_recipe, placed_piece.global_position)

func _spawn_piece_instance(recipe: BuildingPieceRecipe) -> Node3D:
	# 1. Complete Norwegian Log Cabin (Laftehytte / Årestue)
	if recipe.piece_id == "cabin_laftehytte":
		return BuildingAssembler.assemble_log_cabin(recipe.dimensions.x, recipe.dimensions.z)

	# 2. If user provided a 3D model (.gltf, .obj, .tscn), instantiate it directly!
	if recipe.custom_scene != null:
		var custom_instance := recipe.custom_scene.instantiate() as Node3D
		if custom_instance:
			custom_instance.name = "%s_%d" % [recipe.piece_id, randi() % 9999]
			return custom_instance

	# 3. Procedural geometric piece
	var piece_node := StaticBody3D.new()
	piece_node.name = "%s_%d" % [recipe.piece_id, randi() % 9999]

	# Visual Mesh
	var mi := MeshInstance3D.new()
	mi.mesh = _generate_placeholder_mesh(recipe)

	var mat := StandardMaterial3D.new()
	if recipe.category == BuildingPieceRecipe.BuildingCategory.ROOFING:
		mat.albedo_color = Color(0.28, 0.42, 0.22) # Green turf roof
	elif recipe.piece_id.contains("stone"):
		mat.albedo_color = Color(0.5, 0.48, 0.45) # Slate / field stone
	else:
		mat.albedo_color = Color(0.42, 0.32, 0.22) # Pine / spruce timber
	mi.material_override = mat
	piece_node.add_child(mi)

	# Collision Shape
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = recipe.dimensions
	cs.shape = box
	piece_node.add_child(cs)

	return piece_node

func _update_ghost_mesh() -> void:
	var recipe: BuildingPieceRecipe = catalog[selected_recipe_index]

	# If custom 3D model has mesh children, extract mesh for preview
	if recipe.custom_scene != null:
		var temp_node := recipe.custom_scene.instantiate()
		var mesh_found: Mesh = null
		if temp_node is MeshInstance3D:
			mesh_found = temp_node.mesh
		else:
			for child in temp_node.get_children():
				if child is MeshInstance3D:
					mesh_found = child.mesh
					break
		temp_node.queue_free()

		if mesh_found:
			ghost_mesh_instance.mesh = mesh_found
			selected_piece_changed.emit(recipe)
			return

	# Fallback placeholder mesh
	ghost_mesh_instance.mesh = _generate_placeholder_mesh(recipe)
	selected_piece_changed.emit(recipe)

func _generate_placeholder_mesh(recipe: BuildingPieceRecipe) -> Mesh:
	var box := BoxMesh.new()
	box.size = recipe.dimensions
	return box

func get_current_recipe() -> BuildingPieceRecipe:
	return catalog[selected_recipe_index]
