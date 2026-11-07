class_name MerchantInteractable
extends StaticBody3D

## Hanseatic League Merchant Counter (Hansa Kontor) - Bryggen 1360
## Allows settler to barter harvested timber, fur, and firewood for
## continental trade goods: iron nails, salt, dried cod (tørrfisk), and rye bread.

@export var merchant_name: String = "Kjøpmann Hinrich van Bremen"

var prompt_label: Label3D
var last_trade_feedback: Label3D
var trade_timer: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("merchant")
	_setup_ui()

func _setup_ui() -> void:
	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.font_size = 22
	prompt_label.outline_size = 6
	prompt_label.modulate = Color(1.0, 0.90, 0.55) # Hanseatic gold
	prompt_label.outline_modulate = Color(0.08, 0.06, 0.04, 0.95)
	prompt_label.text = "⚓ %s\n[E] Handel (Tørrfisk / Tømmer / Pels ➔ Søm, Salt & Brød)" % merchant_name
	prompt_label.position = Vector3(0, 2.2, 0)
	add_child(prompt_label)

	last_trade_feedback = Label3D.new()
	last_trade_feedback.name = "FeedbackLabel"
	last_trade_feedback.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	last_trade_feedback.no_depth_test = true
	last_trade_feedback.font_size = 20
	last_trade_feedback.outline_size = 5
	last_trade_feedback.modulate = Color(0.4, 1.0, 0.4) # Success green
	last_trade_feedback.outline_modulate = Color(0.05, 0.05, 0.05, 0.95)
	last_trade_feedback.position = Vector3(0, 2.6, 0)
	last_trade_feedback.visible = false
	add_child(last_trade_feedback)

func _process(delta: float) -> void:
	if trade_timer > 0.0:
		trade_timer -= delta
		if trade_timer <= 0.0 and last_trade_feedback:
			last_trade_feedback.visible = false

func on_interact(actor: Node) -> void:
	if actor == null:
		return

	var inv: InventoryManager = actor.get_node_or_null("InventoryManager")
	var stats: SurvivalStats = actor.get_node_or_null("SurvivalStats")

	if inv == null:
		return

	# Priority 1: Historic Bergen Stockfish Trade (Hanseatic League's primary export)
	# Trade 2 stockfish for continental iron nails, salt cask, and Baltic rye bread
	if inv.get_count("stockfish") >= 2:
		inv.consume_resources({"stockfish": 2})
		inv.add_resource("iron_nails", 8)
		inv.add_resource("salt_cask", 1)
		inv.add_resource("rye_bread", 2)
		_show_feedback("✓ Hansakontoret: Byttet 2 Tørrfisk mot 8 Jernsøm, Salt & Rugbrød!")
		if stats:
			stats.eat_food(20.0, true)
		return

	# Priority 2: Trade 2 fresh fjord cod for iron nails and rye bread
	if inv.get_count("fresh_cod") >= 2:
		inv.consume_resources({"fresh_cod": 2})
		inv.add_resource("iron_nails", 5)
		inv.add_resource("rye_bread", 1)
		_show_feedback("✓ Handlet: Byttet 2 Fersk Torsk mot 5 Jernsøm & Rugbrød!")
		if stats:
			stats.eat_food(15.0, true)
		return

	# Priority 3: Trade 2 timber logs for 6 iron nails and 2 dried fish (tørrfisk)
	if inv.get_count("timber_log") >= 2:
		inv.consume_resources({"timber_log": 2})
		inv.add_resource("iron_nails", 6)
		inv.add_resource("stockfish", 2)
		_show_feedback("✓ Handlet: Byttet 2 Tømmer mot 6 Jernsøm & 2 Tørrfisk!")
		if stats:
			stats.eat_food(15.0, true)
		return

	# Priority 4: Trade 1 hare fur or wool fleece for salt and rye bread
	if inv.get_count("hare_fur") >= 1:
		inv.consume_resources({"hare_fur": 1})
		inv.add_resource("salt_cask", 1)
		inv.add_resource("rye_bread", 2)
		_show_feedback("✓ Handlet: Byttet Harepels mot Salt & Rugbrød!")
		if stats:
			stats.eat_food(25.0, true)
		return

	if inv.get_count("wool_fleece") >= 1:
		inv.consume_resources({"wool_fleece": 1})
		inv.add_resource("salt_cask", 1)
		inv.add_resource("iron_nails", 4)
		_show_feedback("✓ Handlet: Byttet Saueull mot Salt & Jernsøm!")
		return

	# Priority 3: Trade 4 firewood for fresh rye bread
	if inv.get_count("firewood") >= 4:
		inv.consume_resources({"firewood": 4})
		inv.add_resource("rye_bread", 1)
		_show_feedback("✓ Handlet: Byttet 4 Ved mot Nystekt Rugbrød!")
		if stats:
			stats.eat_food(25.0, true)
		return

	_show_feedback("Trenger minst 2 Tømmer, 1 Pels/Ull eller 4 Ved å handle!")

func _show_feedback(msg: String) -> void:
	if last_trade_feedback:
		last_trade_feedback.text = msg
		last_trade_feedback.visible = true
		trade_timer = 3.5
