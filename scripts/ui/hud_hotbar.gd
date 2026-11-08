class_name HUDHotbar
extends Control

## Bottom-screen Hotbar HUD for Medieval Bergen 1360:
## - Displays 5 active weapon and tool slots:
##     [1] Øks (Woodcutter's Axe)
##     [2] Drikkehorn (Water Bottle / Backpack Reservoir)
##     [3] Jaktkniv (Hunting Knife)
##     [4] Langbue (Hunting Recurve Bow & Arrow count / draw gauge)
##     [5] Tjærefakkel (Pine-tar Torch)
## - Dynamic active slot highlighting, reservoir meter, arrow ammo count, and bow tension bar

@export var equipment_manager: EquipmentManager

# UI Slot containers
@onready var slot_panels: Array[PanelContainer] = [
	$PanelCenter/HBoxSlots/Slot1,
	$PanelCenter/HBoxSlots/Slot2,
	$PanelCenter/HBoxSlots/Slot3,
	$PanelCenter/HBoxSlots/Slot4,
	$PanelCenter/HBoxSlots/Slot5,
	$PanelCenter/HBoxSlots/Slot6
]

@onready var label_water: Label = $PanelCenter/HBoxSlots/Slot2/VBox/LabelSub
@onready var label_arrows: Label = $PanelCenter/HBoxSlots/Slot4/VBox/LabelSub
@onready var label_fishing: Label = $PanelCenter/HBoxSlots/Slot6/VBox/LabelSub
@onready var bow_charge_bar: ProgressBar = $PanelCenter/HBoxSlots/Slot4/VBox/BowChargeBar

var active_style: StyleBoxFlat
var inactive_style: StyleBoxFlat

var reticle_label: Label

func _ready() -> void:
	_create_styles()
	_create_aim_reticle()
	_find_equipment_manager()
	_connect_slot_clicks()

func _create_aim_reticle() -> void:
	reticle_label = Label.new()
	reticle_label.name = "ArcheryReticle"
	reticle_label.text = "[ + ]"
	reticle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle_label.add_theme_font_size_override("font_size", 18)
	reticle_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 0.85))
	reticle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle_label.visible = false

	# Position near center of screen
	reticle_label.set_anchors_preset(Control.PRESET_CENTER)
	reticle_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	reticle_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	reticle_label.offset_left = -30
	reticle_label.offset_right = 30
	reticle_label.offset_top = -15
	reticle_label.offset_bottom = 15

	call_deferred("_attach_reticle")

func _attach_reticle() -> void:
	var hud_layer := get_parent()
	if hud_layer:
		hud_layer.add_child(reticle_label)
	else:
		add_child(reticle_label)

func _create_styles() -> void:
	inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.10, 0.11, 0.13, 0.85)
	inactive_style.border_color = Color(0.36, 0.32, 0.26, 0.75)
	inactive_style.border_width_left = 1
	inactive_style.border_width_top = 1
	inactive_style.border_width_right = 1
	inactive_style.border_width_bottom = 1
	inactive_style.corner_radius_top_left = 6
	inactive_style.corner_radius_top_right = 6
	inactive_style.corner_radius_bottom_right = 6
	inactive_style.corner_radius_bottom_left = 6

	active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.24, 0.18, 0.10, 0.95)
	active_style.border_color = Color(0.96, 0.78, 0.24, 1.0) # Bright medieval gold
	active_style.border_width_left = 2
	active_style.border_width_top = 2
	active_style.border_width_right = 2
	active_style.border_width_bottom = 2
	active_style.corner_radius_top_left = 6
	active_style.corner_radius_top_right = 6
	active_style.corner_radius_bottom_right = 6
	active_style.corner_radius_bottom_left = 6

func _find_equipment_manager() -> void:
	if equipment_manager == null:
		equipment_manager = get_tree().get_first_node_in_group("equipment_manager") as EquipmentManager

	if equipment_manager:
		equipment_manager.slot_changed.connect(_on_slot_changed)
		equipment_manager.water_reservoir_updated.connect(_on_water_updated)
		equipment_manager.arrow_count_updated.connect(_on_arrows_updated)
		equipment_manager.bow_aim_state_changed.connect(_on_bow_aim_changed)
		equipment_manager.fishing_state_changed.connect(_on_fishing_state_changed)
		_highlight_slot(equipment_manager.current_slot)
		_on_water_updated(equipment_manager.water_reservoir, equipment_manager.max_water_reservoir)
		_on_arrows_updated(equipment_manager.arrow_count)
	else:
		_highlight_slot(1)

func _connect_slot_clicks() -> void:
	for i in range(slot_panels.size()):
		var idx := i + 1
		var panel := slot_panels[i]
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if equipment_manager:
					equipment_manager.select_slot(idx)
		)

func _on_slot_changed(new_slot: int, _old_slot: int) -> void:
	_highlight_slot(new_slot)

func _highlight_slot(slot_idx: int) -> void:
	for i in range(slot_panels.size()):
		var panel := slot_panels[i]
		var is_selected := (i + 1 == slot_idx)
		panel.add_theme_stylebox_override("panel", active_style if is_selected else inactive_style)

		# Subtly tint labels for selected slot
		var title_label := panel.get_node_or_null("VBox/LabelTitle") as Label
		if title_label:
			title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65) if is_selected else Color(0.85, 0.85, 0.85))

func _on_water_updated(current: float, maximum: float) -> void:
	if label_water:
		var pct := int(round((current / maxf(maximum, 1.0)) * 100.0))
		label_water.text = "%d%% Sekk" % pct
		label_water.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0) if current > 20.0 else Color(1.0, 0.4, 0.3))

func _on_arrows_updated(count: int) -> void:
	if label_arrows:
		label_arrows.text = "%d Pil" % count
		label_arrows.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85) if count > 0 else Color(1.0, 0.3, 0.3))

var _last_reticle_tier: int = -1

func _on_bow_aim_changed(is_aiming: bool, draw_progress: float) -> void:
	if bow_charge_bar:
		bow_charge_bar.visible = is_aiming
		bow_charge_bar.value = draw_progress * 100.0

	if reticle_label:
		reticle_label.visible = is_aiming
		if is_aiming:
			var tier := 2 if draw_progress > 0.85 else (1 if draw_progress > 0.4 else 0)
			if tier != _last_reticle_tier:
				_last_reticle_tier = tier
				if tier == 2:
					reticle_label.text = "[+]"
					reticle_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
				elif tier == 1:
					reticle_label.text = "[ + ]"
					reticle_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75, 0.9))
				else:
					reticle_label.text = "( + )"
					reticle_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.65))
		else:
			_last_reticle_tier = -1

func _on_fishing_state_changed(state: int, message: String) -> void:
	if label_fishing:
		match state:
			1: # WAITING_FOR_BITE
				label_fishing.text = "Jukser..."
				label_fishing.add_theme_color_override("font_color", Color(0.3, 0.9, 0.95))
			2: # HOOKED
				label_fishing.text = "NAPP! [KLIKK]"
				label_fishing.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
			_: # IDLE
				label_fishing.text = "Juksa / Fjord"
				label_fishing.add_theme_color_override("font_color", Color(0.4, 0.85, 0.95))

	if reticle_label and equipment_manager and equipment_manager.current_slot == EquipmentManager.Slot.FISHING_LINE:
		if state == 2: # HOOKED
			reticle_label.visible = true
			reticle_label.text = message if not message.is_empty() else "[ NAPP! KLIKK! ]"
			reticle_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1, 1.0))
		elif not message.is_empty():
			reticle_label.visible = true
			reticle_label.text = message
			reticle_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.9))
		elif not equipment_manager.is_aiming_bow:
			reticle_label.visible = false
