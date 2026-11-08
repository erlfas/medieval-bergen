class_name BogOreDeposit
extends StaticBody3D

## Historical Norwegian Bog Iron Ore & Peat Deposit (Myrmalm & Torv) - Medieval Bergen 1360
## Found in waterlogged peat bogs along mountain streams. Limonite nodules precipitated
## by iron-oxidizing groundwater bacteria formed the basis of medieval Scandinavian bloomery iron.

@export var charges: int = 4
@export var max_charges: int = 4

var prompt_label: Label3D
var feedback_label: Label3D
var feedback_timer: float = 0.0
var deposit_mesh_node: MeshInstance3D

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("bog_ore_deposit")
	_build_deposit_geometry()
	_setup_ui()
	_update_prompt()
	set_process(false)

func _build_deposit_geometry() -> void:
	# Materials
	var mat_peat := StandardMaterial3D.new()
	mat_peat.albedo_color = Color(0.22, 0.17, 0.12) # Dark organic peat soil
	mat_peat.roughness = 0.95
	mat_peat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT

	var mat_limonite := StandardMaterial3D.new()
	mat_limonite.albedo_color = Color(0.55, 0.28, 0.12) # Rust-orange bog ore limonite
	mat_limonite.roughness = 0.65
	mat_limonite.metallic = 0.40
	mat_limonite.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT

	# SurfaceTool compound mesh generation: 1 single draw call for entire deposit
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_peat)

	# 1. Low mound of spongy peat bog turf
	var sph_mound := SphereMesh.new()
	sph_mound.radius = 1.15
	sph_mound.height = 0.55
	sph_mound.radial_segments = 8
	sph_mound.rings = 4
	st.append_from(sph_mound, 0, Transform3D(Basis(), Vector3(0, 0.12, 0)))

	# 2. Rust-orange bog ore nodules (myrmalmklumper)
	st.set_material(mat_limonite)
	var sph_nodule := SphereMesh.new()
	sph_nodule.radius = 0.22
	sph_nodule.height = 0.28
	sph_nodule.radial_segments = 6
	sph_nodule.rings = 4

	var nodule_positions := [
		Vector3(0.42, 0.28, 0.25),
		Vector3(-0.38, 0.26, -0.32),
		Vector3(0.18, 0.32, -0.45),
		Vector3(-0.45, 0.25, 0.30)
	]

	for pos in nodule_positions:
		st.append_from(sph_nodule, 0, Transform3D(Basis(), pos))

	st.generate_tangents()

	deposit_mesh_node = MeshInstance3D.new()
	deposit_mesh_node.name = "DepositCompoundMesh"
	deposit_mesh_node.mesh = st.commit()
	add_child(deposit_mesh_node)

	# Interaction collision
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.25
	cyl.height = 0.65
	col.shape = cyl
	col.position = Vector3(0, 0.30, 0)
	add_child(col)

func _setup_ui() -> void:
	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.visibility_range_end = 14.0
	prompt_label.font_size = 20
	prompt_label.outline_size = 5
	prompt_label.modulate = Color(0.95, 0.82, 0.55)
	prompt_label.position = Vector3(0, 1.35, 0)
	add_child(prompt_label)

	feedback_label = Label3D.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.no_depth_test = true
	feedback_label.visibility_range_end = 14.0
	feedback_label.font_size = 20
	feedback_label.outline_size = 5
	feedback_label.modulate = Color(0.4, 1.0, 0.4)
	feedback_label.position = Vector3(0, 1.70, 0)
	feedback_label.visible = false
	add_child(feedback_label)

func _process(delta: float) -> void:
	if feedback_timer > 0.0:
		feedback_timer -= delta
		if feedback_timer <= 0.0:
			if feedback_label:
				feedback_label.visible = false
			set_process(false)

func on_interact(actor: Node) -> void:
	if actor == null:
		return

	if charges <= 0:
		_show_feedback("Myrleiet er tomt. Ny malm feller ut fra grunnvannet over tid.")
		return

	var inv: InventoryManager = actor.get_node_or_null("InventoryManager")
	var stats: SurvivalStats = actor.get_node_or_null("SurvivalStats")

	if inv:
		charges -= 1
		inv.add_resource("bog_iron_ore", 2)
		inv.add_resource("peat_fuel", 1)

		if stats:
			stats.consume_stamina(8.0)

		_show_feedback("✓ Grov ut 2 Myrmalm (Bog Iron) & 1 Brenntorv!")
		_update_prompt()

		if charges <= 0 and deposit_mesh_node:
			deposit_mesh_node.scale = Vector3(0.9, 0.6, 0.9)

func _update_prompt() -> void:
	if prompt_label:
		if charges > 0:
			prompt_label.text = "⛏ Myrmalm & Torv (%d/%d igjenn)\n[E] Grav ut jernmalm til blæstring" % [charges, max_charges]
		else:
			prompt_label.text = "⛏ Utvunnet myrmalmleie (Tomt)"

func _show_feedback(msg: String) -> void:
	if feedback_label:
		feedback_label.text = msg
		feedback_label.visible = true
		feedback_timer = 3.5
		set_process(true)
