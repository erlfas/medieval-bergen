class_name CarryableLog
extends RigidBody3D

## Physical Timber Log that can be picked up, carried in arms, and dropped anywhere in the world.
## Spawned when a harvestable tree falls, or dropped by the settler.

enum LogType { SPRUCE, BIRCH }

@export var log_type: LogType = LogType.SPRUCE
@export var log_length: float = 4.0
@export var timber_logs_yield: int = 1
@export var firewood_yield: int = 1
@export var birch_bark_yield: int = 2

var prompt_label: Label3D
var mesh_instance: MeshInstance3D
var col_shape: CollisionShape3D
var is_focused: bool = false
var focus_cooldown: float = 0.0

static var _shared_log_capsule_4m: CapsuleShape3D = null
static var _shared_log_cyl_4m: CylinderMesh = null
static var _shared_mat_spruce: StandardMaterial3D = null
static var _shared_mat_birch: StandardMaterial3D = null
static var _shared_log_phys_mat: PhysicsMaterial = null

var _rest_timer: float = 0.0

func _ready() -> void:
	_ensure_setup()
	set_process(false)
	set_physics_process(true)

func _ensure_setup() -> void:
	if mesh_instance != null:
		return

	add_to_group("carryable_log")
	add_to_group("carryable_logs")
	add_to_group("interactable")

	# Physics parameters - High friction & angular damp prevents rolling down hills to the sea
	mass = 24.0
	contact_monitor = true
	max_contacts_reported = 2
	angular_damp = 18.0
	linear_damp = 5.0
	can_sleep = true

	if _shared_log_phys_mat == null:
		_shared_log_phys_mat = PhysicsMaterial.new()
		_shared_log_phys_mat.friction = 1.0
		_shared_log_phys_mat.rough = true
		_shared_log_phys_mat.bounce = 0.05
	physics_material_override = _shared_log_phys_mat

	_setup_collision_and_mesh()
	_setup_prompt_ui()

func _setup_collision_and_mesh() -> void:
	if _shared_log_capsule_4m == null:
		_shared_log_capsule_4m = CapsuleShape3D.new()
		_shared_log_capsule_4m.radius = 0.22
		_shared_log_capsule_4m.height = 4.0
		_shared_log_cyl_4m = CylinderMesh.new()
		_shared_log_cyl_4m.top_radius = 0.20
		_shared_log_cyl_4m.bottom_radius = 0.22
		_shared_log_cyl_4m.height = 3.95
		_shared_log_cyl_4m.radial_segments = 14
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
		if is_equal_approx(log_length, 4.0):
			col_shape.shape = _shared_log_capsule_4m
		else:
			var custom_cap := CapsuleShape3D.new()
			custom_cap.radius = 0.22
			custom_cap.height = log_length
			col_shape.shape = custom_cap
		# Align capsule horizontally along local Z axis
		col_shape.rotation.x = deg_to_rad(90.0)
		add_child(col_shape)
	else:
		col_shape = get_node("CollisionShape3D")

	# Visual Cylinder Mesh for the physical timber log
	if not has_node("LogMesh"):
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "LogMesh"
		if is_equal_approx(log_length, 4.0):
			mesh_instance.mesh = _shared_log_cyl_4m
		else:
			var custom_cyl := CylinderMesh.new()
			custom_cyl.top_radius = 0.20
			custom_cyl.bottom_radius = 0.22
			custom_cyl.height = log_length - 0.05
			custom_cyl.radial_segments = 14
			mesh_instance.mesh = custom_cyl
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
	prompt_label.text = "[E] Bær 4m Tømmerstokk (%s)" % type_name
	add_child(prompt_label)

func _process(delta: float) -> void:
	if focus_cooldown > 0.0:
		focus_cooldown -= delta
		if focus_cooldown <= 0.0:
			is_focused = false
			if prompt_label:
				prompt_label.visible = false
			set_process(false)

func _physics_process(delta: float) -> void:
	# 1. Anti-Roll Resting Stabilization:
	# When log has settled to a near stop on ground/slopes, sleep it so it doesn't slip down into the sea
	var lin_spd_sq := linear_velocity.length_squared()
	var ang_spd_sq := angular_velocity.length_squared()
	if lin_spd_sq < 0.08 and ang_spd_sq < 0.12:
		_rest_timer += delta
		if _rest_timer > 0.4:
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			sleeping = true
	else:
		_rest_timer = 0.0

	# 2. Water Buoyancy: If log touches the sea/river (y <= 0.25), float horizontally
	if global_position.y < 0.25:
		var submergence := 0.25 - global_position.y
		apply_central_force(Vector3.UP * (submergence * 280.0 + 35.0))
		linear_velocity.x *= 0.94
		linear_velocity.z *= 0.94
		angular_velocity *= 0.92

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
		var inv: Node = actor.get_node("InventoryManager")
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
	new_log._ensure_setup()
	return new_log

