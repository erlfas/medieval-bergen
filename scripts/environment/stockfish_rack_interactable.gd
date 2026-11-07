class_name StockfishRackInteractable
extends StaticBody3D

## Historical Norwegian Stockfish Drying Rack (Fiskehjell) - Bryggen 1360
## Allows settler to hang freshly caught fjord cod (fersk torsk) to dry in the salt sea breeze,
## producing preserved stockfish (tørrfisk) for long-term winter nourishment and Hanseatic trade.

@export var hanging_cod: int = 4
@export var dried_stockfish: int = 2
@export var max_capacity: int = 12
@export var drying_duration: float = 12.0 ## Seconds per fish to cure in coastal wind

var drying_timer: float = 0.0
var fish_bundle_mesh: MeshInstance3D
var prompt_label: Label3D
var feedback_label: Label3D
var feedback_timer: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("stockfish_rack")
	_setup_labels()
	_update_prompt()
	_update_fish_mesh()

func _setup_labels() -> void:
	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.font_size = 20
	prompt_label.outline_size = 5
	prompt_label.modulate = Color(1.0, 0.92, 0.65)
	prompt_label.position = Vector3(0, 2.7, 0)
	add_child(prompt_label)

	feedback_label = Label3D.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.no_depth_test = true
	feedback_label.font_size = 20
	feedback_label.outline_size = 5
	feedback_label.modulate = Color(0.4, 1.0, 0.4)
	feedback_label.position = Vector3(0, 3.0, 0)
	feedback_label.visible = false
	add_child(feedback_label)

func _process(delta: float) -> void:
	if feedback_timer > 0.0:
		feedback_timer -= delta
		if feedback_timer <= 0.0 and feedback_label:
			feedback_label.visible = false

	# Gradually cure hanging cod into stockfish
	if hanging_cod > 0:
		drying_timer += delta
		if drying_timer >= drying_duration:
			drying_timer = 0.0
			hanging_cod -= 1
			dried_stockfish += 1
			_update_prompt()
			_update_fish_mesh()

func on_interact(actor: Node) -> void:
	if actor == null:
		return

	var inv: InventoryManager = actor.get_node_or_null("InventoryManager")
	if inv == null:
		return

	# Priority 1: Harvest cured stockfish
	if dried_stockfish > 0:
		var harvest_amount := dried_stockfish
		dried_stockfish = 0
		inv.add_resource("stockfish", harvest_amount)
		_show_feedback("✓ Høstet %d tørket torsk (tørrfisk) fra hjellen!" % harvest_amount)
		_update_prompt()
		_update_fish_mesh()
		return

	# Priority 2: Hang freshly caught cod
	var player_cod: int = inv.get_count("fresh_cod")
	if player_cod > 0:
		var space := max_capacity - (hanging_cod + dried_stockfish)
		if space <= 0:
			_show_feedback("Hjellen er full! Vent på at fisken tørker.")
			return

		var to_hang := mini(player_cod, space)
		inv.consume_resources({"fresh_cod": to_hang})
		hanging_cod += to_hang
		_show_feedback("✓ Hengte %d fersk torsk til tørking i sjøbrisen." % to_hang)
		_update_prompt()
		_update_fish_mesh()
		return

	_show_feedback("Fiskehjell: Heng opp fersk torsk fra fjorden [6]!")

func _update_prompt() -> void:
	if prompt_label:
		if dried_stockfish > 0:
			prompt_label.text = "🐟 Fiskehjell (%d tørre, %d henger)\n[E] Høst %d tørrfisk" % [dried_stockfish, hanging_cod, dried_stockfish]
		elif hanging_cod > 0:
			prompt_label.text = "🐟 Fiskehjell (%d henger til tørk)\n[E] Heng opp mer fersk torsk" % hanging_cod
		else:
			prompt_label.text = "🐟 Fiskehjell (Tom)\n[E] Heng opp fersk torsk"

func _update_fish_mesh() -> void:
	if fish_bundle_mesh:
		var total_fish := hanging_cod + dried_stockfish
		fish_bundle_mesh.visible = (total_fish > 0)
		var scale_factor := clampf(float(total_fish) / 6.0, 0.4, 1.1)
		fish_bundle_mesh.scale = Vector3(scale_factor, scale_factor, 1.0)

func _show_feedback(msg: String) -> void:
	if feedback_label:
		feedback_label.text = msg
		feedback_label.visible = true
		feedback_timer = 3.5
