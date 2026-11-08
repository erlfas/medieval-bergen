class_name CarryableLog
extends RigidBody3D

## Physical Timber Log that can be picked up, carried in arms, and dropped anywhere in the world.
## Spawned when a harvestable tree falls, or dropped by the settler.

enum LogType { SPRUCE, BIRCH }

@export var log_type: LogType = LogType.SPRUCE
@export var timber_logs_yield: int = 1
@export var firewood_yield: int = 1
@export var birch_bark_yield: int = 2

var prompt_label: Label3D
var mesh_instance: MeshInstance3D
var col_shape: CollisionShape3D
var is_focused: bool = false
var focus_cooldown: float = 0.0

static var _shared_log_capsule: CapsuleShape3D = null
static var _shared_log_cyl: CylinderMesh = null
static var _shared_mat_spruce: StandardMaterial3D = null
static var _shared_mat_birch: StandardMaterial3D = null

func _ready() -> void:
	_ensure_setup()
	set_process(false)

func _ensure_setup() -> void:
	if mesh_instance != null:
		return

	add_to_group("carryable_log")
	add_to_group("carryable_logs")
	add_to_group("interactable")

	# Physics parameters
	mass = 16.0
	contact_monitor = true
	max_contacts_reported = 2
	angular_damp = 3.5
	linear_damp = 1.5

	_setup_collision_and_mesh()
	_setup_prompt_ui()

func _setup_collision_and_mesh() -> void:
	if _shared_log_capsule == null:
		_shared_log_capsule = CapsuleShape3D.new()
		_shared_log_capsule.radius = 0.22
		_shared_log_capsule.height = 1.6
		_shared_log_cyl = CylinderMesh.new()
		_shared_log_cyl.top_radius = 0.20
		_shared_log_cyl.bottom_radius = 0.22
		_shared_log_cyl.height = 1.55
		_shared_log_cyl.radial_segments = 12
		_shared_mat_spruce = StandardMaterial3D.new()
		_shared_mat_spruce.albedo_color = Color(0.38, 0.25, 0.15)
		_shared_mat_spruce.roughness = 0.88
		_shared_mat_birch = StandardMaterial3D.new()
		_shared_mat_birch.albedo_color = Color(0.88, 0.86, 0.82)
		_shared_mat_birch.roughness = 0.75

	# Horizontal capsule collision shape
	if not has_node("CollisionShape3D"):
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"
		col_shape.shape = _shared_log_capsule
		# Align capsule horizontally along local Z axis
		col_shape.rotation.x = deg_to_rad(90.0)
		add_child(col_shape)
	else:
		col_shape = get_node("CollisionShape3D")

	# Visual Cylinder Mesh for the physical timber log
	if not has_node("LogMesh"):
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "LogMesh"
		mesh_instance.mesh = _shared_log_cyl
		# Align mesh horizontally
		mesh_instance.rotation.x = deg_to_rad(90.0)
		mesh_instance.material_override = _shared_mat_spruce if log_type == LogType.SPRUCE else _shared_mat_birch
		add_child(mesh_instance)
	else:
		mesh_instance = get_node("LogMesh")

func _setup_prompt_ui() -> void:
	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.font_size = 22
	prompt_label.outline_size = 6
	prompt_label.modulate = Color(1.0, 0.9, 0.45)
	prompt_label.outline_modulate = Color(0.05, 0.05, 0.05, 0.95)
	prompt_label.position = Vector3(0.0, 0.45, 0.0)
	prompt_label.visible = false

	var type_name := "Gran (Spruce)" if log_type == LogType.SPRUCE else "Bjørk (Birch)"
	prompt_label.text = "[E] Bær Tømmerstokk (%s)" % type_name
	add_child(prompt_label)

func _process(delta: float) -> void:
	if focus_cooldown > 0.0:
		focus_cooldown -= delta
		if focus_cooldown <= 0.0:
			is_focused = false
			if prompt_label:
				prompt_label.visible = false
			set_process(false)

func set_settler_focus(settler: Node) -> void:
	_ensure_setup()
	if settler != null:
		is_focused = true
		focus_cooldown = 0.35
		set_process(true)
		if prompt_label:
			prompt_label.visible = true
	else:
		is_focused = false
		if prompt_label:
			prompt_label.visible = false
		set_process(false)

func on_interact(actor: Node) -> void:
	_ensure_setup()
	if actor and actor.has_method("pick_up_log") and actor.get("is_carrying_log") == false:
		actor.pick_up_log(self)
	else:
		collect(actor)

func take_damage(_amount: float, actor: Node) -> void:
	on_interact(actor)

func collect(actor: Node) -> void:
	if actor and actor.has_node("InventoryManager"):
		var inv: InventoryManager = actor.get_node("InventoryManager")
		if log_type == LogType.SPRUCE:
			inv.add_resource("timber_log", timber_logs_yield)
			inv.add_resource("firewood", firewood_yield)
		else:
			inv.add_resource("birch_bark", birch_bark_yield)
			inv.add_resource("timber_log", timber_logs_yield)
			inv.add_resource("firewood", firewood_yield)

		_spawn_floating_pickup_feedback(actor)

	queue_free()

func _spawn_floating_pickup_feedback(_actor: Node) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 26
	label.outline_size = 6
	label.modulate = Color(0.4, 1.0, 0.4)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	if log_type == LogType.SPRUCE:
		label.text = "+%d Tømmerstokk (Timber Log)" % timber_logs_yield
	else:
		label.text = "+%d Bjørkestokk +%d Never" % [timber_logs_yield, birch_bark_yield]

	var parent := get_parent()
	if parent:
		parent.add_child(label)
		var base_pos := global_position if is_inside_tree() else position
		label.position = base_pos + Vector3(0.0, 0.6, 0.0)
		var tween := label.create_tween()
		tween.tween_property(label, "position:y", label.position.y + 0.9, 0.9)
		tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
		tween.tween_callback(label.queue_free)

static func create_log(p_type: LogType = LogType.SPRUCE) -> RigidBody3D:
	var script_res = load("res://scripts/environment/carryable_log.gd")
	var new_log := RigidBody3D.new()
	new_log.set_script(script_res)
	new_log.log_type = p_type
	new_log.add_to_group("carryable_log")
	new_log.add_to_group("carryable_logs")
	new_log.add_to_group("interactable")
	new_log._setup_collision_and_mesh()
	new_log._setup_prompt_ui()
	return new_log
