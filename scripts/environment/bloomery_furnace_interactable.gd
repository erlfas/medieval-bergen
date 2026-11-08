class_name BloomeryFurnaceInteractable
extends StaticBody3D

## Traditional Norwegian Bloomery Furnace & Smithing Anvil (Blæsterovn & Ambolt) - 1360
## The historical iron smelting furnace of medieval Norway. Direct reduction of bog iron
## ore (myrmalm) using wood charcoal (trekol) or peat (brenntorv) in a stone & clay shaft,
## producing a workable iron bloom (jernlupp) forged into architectural iron nails (jernsøm).

@export var is_smelting: bool = false
@export var smelt_duration: float = 10.0
@export var stored_iron_blooms: int = 1 ## Starts with 1 smelted bloom ready to hammer!

var smelt_timer: float = 0.0
var ore_loaded: int = 0
var fuel_loaded: int = 0

var furnace_light: OmniLight3D
var prompt_label: Label3D
var feedback_label: Label3D
var feedback_timer: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("bloomery_furnace")
	add_to_group("hearth")
	_build_furnace_model()
	_setup_ui()
	_update_prompt()
	set_process(is_smelting)

func _build_furnace_model() -> void:
	# Materials
	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.38, 0.36, 0.34) # Heat-tempered mountain stone
	mat_stone.roughness = 0.90
	mat_stone.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT

	var mat_clay := StandardMaterial3D.new()
	mat_clay.albedo_color = Color(0.48, 0.28, 0.18) # Baked red-brown furnace clay
	mat_clay.roughness = 0.85
	mat_clay.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.32, 0.22, 0.14)
	mat_wood.roughness = 0.80
	mat_wood.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT

	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = Color(0.58, 0.60, 0.64)
	mat_iron.metallic = 0.85
	mat_iron.roughness = 0.40
	mat_iron.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT

	# SurfaceTool Compound Assembly: 1 single draw call for the entire smelting station
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_clay)

	# 1. Conical stone & clay shaft furnace (Blæsterovn sjakt)
	var cyl_shaft := CylinderMesh.new()
	cyl_shaft.top_radius = 0.45
	cyl_shaft.bottom_radius = 0.85
	cyl_shaft.height = 1.75
	cyl_shaft.radial_segments = 10
	st.append_from(cyl_shaft, 0, Transform3D(Basis(), Vector3(0, 0.875, 0)))

	# 2. Stone base reinforcement ring
	st.set_material(mat_stone)
	var cyl_base := CylinderMesh.new()
	cyl_base.top_radius = 0.95
	cyl_base.bottom_radius = 1.05
	cyl_base.height = 0.55
	cyl_base.radial_segments = 10
	st.append_from(cyl_base, 0, Transform3D(Basis(), Vector3(0, 0.275, 0)))

	# 3. Wooden Bellows Stand (Blåsebenk) on the left
	st.set_material(mat_wood)
	var box_bench := BoxMesh.new()
	box_bench.size = Vector3(0.65, 0.50, 1.2)
	st.append_from(box_bench, 0, Transform3D(Basis(), Vector3(-1.15, 0.25, 0)))

	# 4. Stone anvil base block & heavy forged iron anvil top (Ambolt)
	var box_anvil_stone := BoxMesh.new()
	box_anvil_stone.size = Vector3(0.55, 0.55, 0.55)
	st.append_from(box_anvil_stone, 0, Transform3D(Basis(), Vector3(0, 0.275, 1.25)))

	st.set_material(mat_iron)
	var box_anvil_iron := BoxMesh.new()
	box_anvil_iron.size = Vector3(0.40, 0.25, 0.70)
	st.append_from(box_anvil_iron, 0, Transform3D(Basis(), Vector3(0, 0.675, 1.25)))

	st.generate_tangents()

	var furnace_mesh := MeshInstance3D.new()
	furnace_mesh.name = "BloomeryCompoundMesh"
	furnace_mesh.mesh = st.commit()
	add_child(furnace_mesh)

	# Physical Collision Shape
	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(2.6, 1.85, 2.6)
	col.shape = box_col
	col.position = Vector3(-0.15, 0.90, 0.40)
	add_child(col)

	# Smelting Fire Glow Light
	furnace_light = OmniLight3D.new()
	furnace_light.name = "FurnaceLight"
	furnace_light.light_color = Color(1.0, 0.45, 0.12)
	furnace_light.light_energy = 1.8
	furnace_light.omni_range = 6.0
	furnace_light.shadow_enabled = false
	furnace_light.position = Vector3(0, 0.95, 0)
	furnace_light.visible = false
	add_child(furnace_light)

func _setup_ui() -> void:
	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.visibility_range_end = 14.0
	prompt_label.font_size = 20
	prompt_label.outline_size = 5
	prompt_label.modulate = Color(1.0, 0.88, 0.55)
	prompt_label.position = Vector3(0, 2.25, 0)
	add_child(prompt_label)

	feedback_label = Label3D.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.no_depth_test = true
	feedback_label.visibility_range_end = 14.0
	feedback_label.font_size = 20
	feedback_label.outline_size = 5
	feedback_label.modulate = Color(0.4, 1.0, 0.4)
	feedback_label.position = Vector3(0, 2.65, 0)
	feedback_label.visible = false
	add_child(feedback_label)

func _process(delta: float) -> void:
	if feedback_timer > 0.0:
		feedback_timer -= delta
		if feedback_timer <= 0.0 and feedback_label:
			feedback_label.visible = false

	# Smelting reduction process
	if is_smelting:
		smelt_timer += delta
		if furnace_light:
			furnace_light.light_energy = 1.6 + sin(Time.get_ticks_msec() * 0.02) * 0.4

		if smelt_timer >= smelt_duration:
			is_smelting = false
			smelt_timer = 0.0
			stored_iron_blooms += 1
			if furnace_light: furnace_light.visible = false
			_show_feedback("🔥 Blæstring fullført! En glødende jernlupp (iron bloom) er klar til smiing.")
			_update_prompt()

	if not is_smelting and feedback_timer <= 0.0:
		set_process(false)

func on_interact(actor: Node) -> void:
	if actor == null:
		return

	var inv: InventoryManager = actor.get_node_or_null("InventoryManager")
	var stats: SurvivalStats = actor.get_node_or_null("SurvivalStats")

	if inv == null:
		return

	# Priority 1: Forge ready iron bloom on anvil into 8 iron nails (jernsøm)
	if stored_iron_blooms > 0:
		stored_iron_blooms -= 1
		inv.add_resource("iron_nails", 8)
		if stats:
			stats.consume_stamina(14.0)
		_show_feedback("⚒ Smidde jernlupp på ambolten: +8 Jernsøm (Iron Nails)!")
		_update_prompt()
		return

	# Priority 2: Check if currently smelting
	if is_smelting:
		var progress := int((smelt_timer / smelt_duration) * 100.0)
		_show_feedback("Blæsterovnen reduserer myrmalm... %d%% ferdig" % progress)
		return

	# Priority 3: Charge and ignite furnace with bog ore + fuel
	var bog_ore: int = inv.get_count("bog_iron_ore")
	var charcoal: int = inv.get_count("charcoal")
	var peat: int = inv.get_count("peat_fuel")
	var wood: int = inv.get_count("firewood")

	var fuel_type := ""
	if charcoal >= 2:
		fuel_type = "charcoal"
	elif peat >= 2:
		fuel_type = "peat_fuel"
	elif wood >= 2:
		fuel_type = "firewood"

	if bog_ore >= 2 and not fuel_type.is_empty():
		inv.consume_resources({"bog_iron_ore": 2, fuel_type: 2})
		is_smelting = true
		smelt_timer = 0.0
		set_process(true)
		if furnace_light: furnace_light.visible = true
		if stats:
			stats.consume_stamina(8.0)
		_show_feedback("🔥 Fylte blæsterovnen med 2 myrmalm & 2 brensel! Blæstring igang.")
		_update_prompt()
		return

	_show_feedback("Trenger 2 Myrmalm (Bog Iron) og 2 Brensel (Torv/Trekol/Ved) for å blæstre!")

func _update_prompt() -> void:
	if prompt_label:
		if stored_iron_blooms > 0:
			prompt_label.text = "⚒ Blæsterovn (%d jernlupp klar)\n[E] Smi jernlupp på ambolten ➔ 8 Jernsøm" % stored_iron_blooms
		elif is_smelting:
			prompt_label.text = "🔥 Blæsterovn (Smelter myrmalm...)\nVennligst vent på reduksjonsprosessen"
		else:
			prompt_label.text = "⚒ Blæsterovn & Ambolt (Klar)\n[E] Fyll 2 Myrmalm + 2 Brensel for å blæstre jern"

func _show_feedback(msg: String) -> void:
	if feedback_label:
		feedback_label.text = msg
		feedback_label.visible = true
		feedback_timer = 3.8
		set_process(true)
