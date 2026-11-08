class_name HUDBuildingBar
extends Control

## HUD controller for:
## - Resource counts (Timber, Bark, Stone, Turf)
## - Building mode bar (Piece selector, costs, carried log deduction)
## - Physical carried log notification banner
## - Settler Cabin Building Quest tracker
## - In-Game "How to Build a Cabin" Codex (Byggebok)

@export var player_builder: PlayerBuilder
@export var inventory: InventoryManager
@export var settler: CharacterBody3D

@onready var panel_build: PanelContainer = $PanelBuild
@onready var label_piece_name: Label = $PanelBuild/HBox/VBoxPiece/LabelPieceName
@onready var label_cost: Label = $PanelBuild/HBox/VBoxPiece/LabelCost
@onready var label_controls: Label = $PanelBuild/HBox/LabelControls

@onready var panel_resources: PanelContainer = $PanelResources
@onready var label_logs: Label = $PanelResources/HBoxRes/LabelLogs
@onready var label_bark: Label = $PanelResources/HBoxRes/LabelBark
@onready var label_stone: Label = $PanelResources/HBoxRes/LabelStone
@onready var label_turf: Label = $PanelResources/HBoxRes/LabelTurf
@onready var label_rope: Label = $PanelResources/HBoxRes/LabelRope

@onready var panel_carried_log: PanelContainer = get_node_or_null("PanelCarriedLog")
@onready var label_carried_log: Label = get_node_or_null("PanelCarriedLog/LabelCarried")

@onready var panel_quest: PanelContainer = get_node_or_null("PanelQuest")
@onready var label_quest_status: Label = get_node_or_null("PanelQuest/VBox/LabelQuestDetails")

@onready var modal_cabin_guide: PanelContainer = get_node_or_null("ModalCabinGuide")
@onready var btn_guide_close: Button = get_node_or_null("ModalCabinGuide/VBox/HeaderHBox/BtnCloseGuide")
@onready var btn_open_guide: Button = get_node_or_null("PanelResources/HBoxRes/BtnOpenGuide")

var is_carrying_log: bool = false
var has_built_cabin: bool = false

func _ready() -> void:
	add_to_group("hud_building_bar")

	if player_builder == null:
		player_builder = get_tree().get_first_node_in_group("player_builder") as PlayerBuilder
	if inventory == null:
		inventory = get_tree().get_first_node_in_group("inventory") as InventoryManager
	if settler == null:
		settler = get_tree().get_first_node_in_group("settler") as CharacterBody3D

	if player_builder:
		player_builder.build_mode_toggled.connect(_on_build_mode_toggled)
		player_builder.selected_piece_changed.connect(_on_piece_changed)
		player_builder.piece_placed.connect(_on_piece_placed)
		panel_build.visible = player_builder.is_build_mode
		if player_builder.is_build_mode:
			_on_piece_changed(player_builder.get_current_recipe())
	else:
		panel_build.visible = false

	if settler and settler.has_signal("carrying_state_changed"):
		settler.carrying_state_changed.connect(_on_carrying_state_changed)
		_on_carrying_state_changed(settler.get("is_carrying_log") == true)

	if inventory:
		inventory.inventory_changed.connect(_on_inventory_changed)
		_update_resource_labels(inventory.items)

	if btn_open_guide:
		btn_open_guide.pressed.connect(toggle_cabin_guide)
	if btn_guide_close:
		btn_guide_close.pressed.connect(close_cabin_guide)

	if modal_cabin_guide:
		modal_cabin_guide.visible = false

	_update_quest_tracker()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and modal_cabin_guide and modal_cabin_guide.visible:
		close_cabin_guide()
		get_viewport().set_input_as_handled()

func toggle_cabin_guide() -> void:
	if not modal_cabin_guide:
		return
	var new_state: bool = not modal_cabin_guide.visible
	modal_cabin_guide.visible = new_state
	if new_state:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func close_cabin_guide() -> void:
	if modal_cabin_guide:
		modal_cabin_guide.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_build_mode_toggled(active: bool) -> void:
	panel_build.visible = active
	if active and player_builder:
		_on_piece_changed(player_builder.get_current_recipe())
	_update_quest_tracker()

func _on_carrying_state_changed(carrying: bool) -> void:
	is_carrying_log = carrying
	if panel_carried_log:
		panel_carried_log.visible = carrying
	if player_builder and player_builder.is_build_mode:
		_on_piece_changed(player_builder.get_current_recipe())
	_update_quest_tracker()

func _on_piece_placed(recipe: BuildingPieceRecipe, _pos: Vector3) -> void:
	if recipe and recipe.piece_id.begins_with("cabin"):
		has_built_cabin = true
	_update_quest_tracker()

func _on_piece_changed(recipe: BuildingPieceRecipe) -> void:
	if not recipe:
		return
	label_piece_name.text = "[B] Bygg: %s" % recipe.piece_name

	var cost_strings: Array[String] = []
	for res_id: String in recipe.resource_costs:
		var count: int = recipe.resource_costs[res_id]
		if res_id == "timber_log" and is_carrying_log and count > 0:
			cost_strings.append("Tømmer: %d (1 i favnen!)" % count)
		else:
			cost_strings.append("%s: %d" % [res_id.capitalize(), count])
	label_cost.text = "Kostnad: " + ", ".join(cost_strings)

	if is_carrying_log and recipe.resource_costs.get("timber_log", 0) > 0:
		label_controls.text = "🌲 Bærer stokk (-1 kostnad) | [R] Roter dør | [Tab] Neste | [L-Klikk] Bygg"
	else:
		label_controls.text = "[R] Roter dør | [Tab] Neste | [L-Klikk] Bygg"

func _on_inventory_changed(items: Dictionary) -> void:
	_update_resource_labels(items)
	_update_quest_tracker()

func _update_resource_labels(items: Dictionary) -> void:
	label_logs.text = "Tømmer (Logs): %d" % items.get("timber_log", 0)
	label_bark.text = "Never (Bark): %d" % items.get("birch_bark", 0)
	label_stone.text = "Stein (Stone): %d" % items.get("stone", 0)
	label_turf.text = "Torv (Turf): %d" % items.get("turf", 0)
	if label_rope:
		label_rope.text = "Klatretau (Rope): %d" % items.get("climbing_rope", 0)

func _update_quest_tracker() -> void:
	if not label_quest_status:
		return

	var logs := inventory.get_count("timber_log") if inventory else 0
	var stones := inventory.get_count("stone") if inventory else 0

	var log_check := "[X]" if (logs >= 6 or (logs >= 5 and is_carrying_log) or has_built_cabin) else "[ ]"
	var stone_check := "[X]" if (stones >= 4 or has_built_cabin) else "[ ]"
	var build_check := "[X]" if (player_builder and player_builder.is_build_mode) else "[ ]"
	var placed_check := "[X]" if has_built_cabin else "[ ]"

	var text := ""
	text += "%s 1. Samle tømmer (6 logs) [%d/6%s]\n" % [log_check, logs, " +1 i favnen" if is_carrying_log else ""]
	text += "%s 2. Samle stein (4 stein) [%d/4]\n" % [stone_check, stones]
	text += "%s 3. Åpne byggemodus [B]\n" % [build_check]
	text += "%s 4. Roter døråpning [R] & plasser [L-Klikk]\n" % [placed_check]
	if has_built_cabin:
		text += "* Laftehytte fullført! Gå inn og varm deg ved Åre-ildstedet."
	else:
		text += "* Trykk [C] for Byggebok (How to build guide)"

	label_quest_status.text = text

func _show_placement_error(msg: String) -> void:
	if label_quest_status:
		label_quest_status.text = "⚠️ " + msg
		get_tree().create_timer(3.5).timeout.connect(_update_quest_tracker)
