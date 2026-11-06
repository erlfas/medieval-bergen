class_name HUDBuildingBar
extends Control

## Bottom HUD bar displaying:
## - Current building piece (Farmhouse wall, Stabbur pillar, Barn post, Sod roof)
## - Required resources (Timber Logs, Birch Bark, Stones, Turf)
## - Current Inventory counts

@export var player_builder: PlayerBuilder
@export var inventory: InventoryManager

@onready var panel_build: PanelContainer = $PanelBuild
@onready var label_piece_name: Label = $PanelBuild/HBox/VBoxPiece/LabelPieceName
@onready var label_cost: Label = $PanelBuild/HBox/VBoxPiece/LabelCost
@onready var label_controls: Label = $PanelBuild/HBox/LabelControls

@onready var label_logs: Label = $PanelResources/HBoxRes/LabelLogs
@onready var label_bark: Label = $PanelResources/HBoxRes/LabelBark
@onready var label_stone: Label = $PanelResources/HBoxRes/LabelStone
@onready var label_turf: Label = $PanelResources/HBoxRes/LabelTurf

func _ready() -> void:
	if player_builder == null:
		player_builder = get_tree().get_first_node_in_group("player_builder") as PlayerBuilder
	if inventory == null:
		inventory = get_tree().get_first_node_in_group("inventory") as InventoryManager

	if player_builder:
		player_builder.build_mode_toggled.connect(_on_build_mode_toggled)
		player_builder.selected_piece_changed.connect(_on_piece_changed)
		panel_build.visible = player_builder.is_build_mode
		if player_builder.is_build_mode:
			_on_piece_changed(player_builder.get_current_recipe())
	else:
		panel_build.visible = false

	if inventory:
		inventory.inventory_changed.connect(_on_inventory_changed)
		_update_resource_labels(inventory.items)

func _on_build_mode_toggled(active: bool) -> void:
	panel_build.visible = active
	if active and player_builder:
		_on_piece_changed(player_builder.get_current_recipe())

func _on_piece_changed(recipe: BuildingPieceRecipe) -> void:
	if not recipe:
		return
	label_piece_name.text = "[B] Bygg: %s" % recipe.piece_name

	var cost_strings: Array[String] = []
	for res_id: String in recipe.resource_costs:
		var count: int = recipe.resource_costs[res_id]
		cost_strings.append("%s: %d" % [res_id.capitalize(), count])
	label_cost.text = "Kostnad: " + ", ".join(cost_strings)

func _on_inventory_changed(items: Dictionary) -> void:
	_update_resource_labels(items)

func _update_resource_labels(items: Dictionary) -> void:
	label_logs.text = "Tømmer (Logs): %d" % items.get("timber_log", 0)
	label_bark.text = "Never (Bark): %d" % items.get("birch_bark", 0)
	label_stone.text = "Stein (Stone): %d" % items.get("stone", 0)
	label_turf.text = "Torv (Turf): %d" % items.get("turf", 0)
