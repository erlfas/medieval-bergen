class_name CampfireInteractable
extends StaticBody3D

## Campfire & Hearth Cooking Station for Medieval Bergen 1360:
## - Stone ring with crossed pine logs and glowing ember bed
## - Radiates warmth (+8/s warmth, -12/s wetness) to nearby settlers within 4.5m
## - Deters hungry predators (wolves flee within 9m)
## - Interactive Cooking & Whittling: roasts raw meats and carves hunting arrows

@export var is_lit: bool = true
@export var warmth_radius: float = 4.5
@export var fuel_time_remaining: float = 600.0 ## 10 minutes real time

var fire_light: OmniLight3D
var ember_mesh: MeshInstance3D
var feedback_label: Label3D
var feedback_timer: float = 0.0

func _ready() -> void:
	add_to_group("campfire")
	add_to_group("hearth")
	_build_campfire_model()

func _build_campfire_model() -> void:
	# Materials
	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.42, 0.44, 0.46) # Mountain granite
	mat_stone.roughness = 0.9

	var mat_log := StandardMaterial3D.new()
	mat_log.albedo_color = Color(0.36, 0.24, 0.16) # Charred pine bark
	mat_log.roughness = 0.85

	var mat_embers := StandardMaterial3D.new()
	mat_embers.albedo_color = Color(1.0, 0.42, 0.08) # Glowing fiery amber
	mat_embers.emission_enabled = true
	mat_embers.emission = Color(1.0, 0.38, 0.05)
	mat_embers.emission_energy_multiplier = 2.4

	# 1. Stone Ring (8 river stones arranged circularly)
	var stones_parent := Node3D.new()
	stones_parent.name = "StoneRing"
	add_child(stones_parent)

	for i in range(8):
		var stone := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.18
		sph.height = 0.26
		sph.radial_segments = 6
		sph.rings = 4
		stone.mesh = sph
		stone.material_override = mat_stone
		var angle := i * (TAU / 8.0)
		stone.position = Vector3(cos(angle) * 0.72, 0.10, sin(angle) * 0.72)
		stone.scale = Vector3(1.1, 0.8, 1.2)
		stones_parent.add_child(stone)

	# 2. Crossed Firewood Logs (3 logs resting over embers)
	for i in range(3):
		var wood := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.08
		cyl.height = 1.1
		cyl.radial_segments = 6
		wood.mesh = cyl
		wood.material_override = mat_log
		wood.rotation_degrees = Vector3(12.0, i * 60.0, 0.0)
		wood.position = Vector3(0.0, 0.14, 0.0)
		add_child(wood)

	# 3. Glowing Ember Bed (center dome)
	ember_mesh = MeshInstance3D.new()
	var ember_sph := SphereMesh.new()
	ember_sph.radius = 0.45
	ember_sph.height = 0.32
	ember_sph.radial_segments = 8
	ember_sph.rings = 4
	ember_mesh.mesh = ember_sph
	ember_mesh.material_override = mat_embers
	ember_mesh.position = Vector3(0.0, 0.08, 0.0)
	add_child(ember_mesh)

	# 4. OmniLight3D (Warm flickering campfire glow)
	fire_light = OmniLight3D.new()
	fire_light.name = "CampfireLight"
	fire_light.light_color = Color(1.0, 0.62, 0.22)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 9.5
	fire_light.shadow_enabled = false
	fire_light.distance_fade_enabled = true
	fire_light.distance_fade_begin = 28.0
	fire_light.distance_fade_length = 10.0
	fire_light.position = Vector3(0.0, 0.45, 0.0)
	add_child(fire_light)

	# 5. Collision Shape for physical interaction
	var col := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 0.85
	cyl_shape.height = 0.5
	col.shape = cyl_shape
	col.position = Vector3(0.0, 0.25, 0.0)
	add_child(col)

	# 6. Floating Feedback Label
	feedback_label = Label3D.new()
	feedback_label.position = Vector3(0.0, 1.25, 0.0)
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.font_size = 20
	feedback_label.modulate = Color(1.0, 0.92, 0.65)
	feedback_label.visibility_range_end = 14.0
	feedback_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	feedback_label.text = "[E] Bål: Stek kjøtt / Spikk piler"
	add_child(feedback_label)

func _process(delta: float) -> void:
	if not is_lit:
		if fire_light: fire_light.visible = false
		if ember_mesh: ember_mesh.visible = false
		return

	# Gentle warmth and flicker
	if fire_light:
		var flicker := sin(Time.get_ticks_msec() * 0.015) * 0.15 + cos(Time.get_ticks_msec() * 0.033) * 0.10
		fire_light.light_energy = 1.7 + flicker

	if feedback_timer > 0.0:
		feedback_timer -= delta
		if feedback_timer <= 0.0 and feedback_label:
			feedback_label.text = "[E] Bål: Stek kjøtt / Spikk piler"

func on_interact(actor: Node) -> void:
	if not is_lit:
		return

	var inv: InventoryManager = actor.get_node_or_null("InventoryManager") as InventoryManager
	var equip: EquipmentManager = actor.get_node_or_null("EquipmentManager") as EquipmentManager
	var stats: SurvivalStats = actor.get_node_or_null("SurvivalStats") as SurvivalStats

	var actions_taken: Array[String] = []

	if inv:
		# 1. Roast raw meats
		var venison := inv.get_count("raw_venison")
		if venison > 0:
			inv.consume_resources({"raw_venison": venison})
			inv.add_resource("cooked_venison", venison)
			actions_taken.append("Stekte %d hjortekjøtt" % venison)

		var hare := inv.get_count("raw_hare")
		if hare > 0:
			inv.consume_resources({"raw_hare": hare})
			inv.add_resource("roasted_hare", hare)
			actions_taken.append("Stekte %d harekjøtt" % hare)

		var mutton := inv.get_count("raw_mutton")
		if mutton > 0:
			inv.consume_resources({"raw_mutton": mutton})
			inv.add_resource("roasted_mutton", mutton)
			actions_taken.append("Stekte %d sauekjøtt" % mutton)

		var beef := inv.get_count("raw_beef")
		if beef > 0:
			inv.consume_resources({"raw_beef": beef})
			inv.add_resource("cooked_beef", beef)
			actions_taken.append("Stekte %d storfekjøtt" % beef)

		var cod := inv.get_count("fresh_cod")
		if cod > 0:
			inv.consume_resources({"fresh_cod": cod})
			inv.add_resource("cooked_fish", cod)
			actions_taken.append("Grillet %d fersk torsk" % cod)

		var herring := inv.get_count("fresh_herring")
		if herring > 0:
			inv.consume_resources({"fresh_herring": herring})
			inv.add_resource("cooked_fish", herring)
			actions_taken.append("Røkte %d fersk sild" % herring)

		# 2. Whittle arrows if holding timber
		var timber := inv.get_count("timber_log")
		if timber > 0 and equip:
			inv.consume_resources({"timber_log": 1})
			equip.arrow_count += 8
			equip.arrow_count_updated.emit(equip.arrow_count)
			actions_taken.append("Spikket 8 jaktpiler")

		# 3. Char firewood into bloomery smelting charcoal (Trekol)
		var firewood := inv.get_count("firewood")
		if firewood >= 4:
			inv.consume_resources({"firewood": 2})
			inv.add_resource("charcoal", 2)
			actions_taken.append("Brente 2 trekol (charcoal) til blæstring")

		# 4. Brew pine-needle tea / warm broth
		if stats and stats.thirst < 85.0:
			stats.drink_water(true)
			stats.warmth = minf(100.0, stats.warmth + 25.0)
			actions_taken.append("Drakk varm furu-te")

	if actions_taken.is_empty():
		_show_feedback("Bålet varmer godt! (Trenger vilt, fisk, ved eller tømmer)")
	else:
		_show_feedback("✓ " + " • ".join(actions_taken))

func _show_feedback(msg: String) -> void:
	if feedback_label:
		feedback_label.text = msg
		feedback_timer = 4.0
