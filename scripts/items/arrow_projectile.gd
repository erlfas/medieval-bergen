class_name ArrowProjectile
extends Node3D

## Physics-driven hunting arrow projectile for Medieval Bergen 1360:
## - Ballistic gravity trajectory and continuous raycast collision
## - Penetrates / embeds into target fauna, harvestable trees, and terrain
## - Accurate damage scaling based on bow draw time
## - Procedural 3D arrow model: ash wood shaft, iron broadhead, goose feather fletchings

@export var damage: float = 40.0
@export var gravity: float = 9.8
@export var despawn_time: float = 20.0

var velocity: Vector3 = Vector3.ZERO
var shooter: Node = null
var is_stuck: bool = false
var elapsed_time: float = 0.0

var shaft_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var fletchings: Array[MeshInstance3D] = []
var arrow_model: Node3D

static var _shared_mat_wood: StandardMaterial3D
static var _shared_mat_iron: StandardMaterial3D
static var _shared_mat_feather: StandardMaterial3D
static var _shared_cyl_shaft: CylinderMesh
static var _shared_cone_head: CylinderMesh
static var _shared_box_fletch: BoxMesh

func _enter_tree() -> void:
	add_to_group("projectiles")
	_build_arrow_model()

func _ready() -> void:
	add_to_group("projectiles")
	_build_arrow_model()
	_align_to_velocity()

func _align_to_velocity() -> void:
	if velocity.length_squared() > 0.01:
		var dir := velocity.normalized()
		var up_vec := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		look_at(global_position + velocity, up_vec)

func _build_arrow_model() -> void:
	if shaft_mesh != null or arrow_model != null:
		return

	var arrow_glb_scene = load("res://assets/weapons/arrow.glb")
	if arrow_glb_scene:
		arrow_model = arrow_glb_scene.instantiate()
		add_child(arrow_model)
		return

	if _shared_mat_wood == null:
		_shared_mat_wood = StandardMaterial3D.new()
		_shared_mat_wood.albedo_color = Color(0.68, 0.52, 0.35) # Ash wood
		_shared_mat_wood.roughness = 0.75

		_shared_mat_iron = StandardMaterial3D.new()
		_shared_mat_iron.albedo_color = Color(0.60, 0.63, 0.68)
		_shared_mat_iron.metallic = 0.85
		_shared_mat_iron.roughness = 0.35

		_shared_mat_feather = StandardMaterial3D.new()
		_shared_mat_feather.albedo_color = Color(0.88, 0.88, 0.86) # Goose quill fletching
		_shared_mat_feather.roughness = 0.9

		_shared_cyl_shaft = CylinderMesh.new()
		_shared_cyl_shaft.top_radius = 0.012
		_shared_cyl_shaft.bottom_radius = 0.012
		_shared_cyl_shaft.height = 0.72
		_shared_cyl_shaft.radial_segments = 8

		_shared_cone_head = CylinderMesh.new()
		_shared_cone_head.top_radius = 0.001
		_shared_cone_head.bottom_radius = 0.028
		_shared_cone_head.height = 0.09
		_shared_cone_head.radial_segments = 4

		_shared_box_fletch = BoxMesh.new()
		_shared_box_fletch.size = Vector3(0.002, 0.038, 0.12)

	# 1. Wooden Shaft (length 0.72m, diameter 0.024m)
	shaft_mesh = MeshInstance3D.new()
	shaft_mesh.mesh = _shared_cyl_shaft
	shaft_mesh.material_override = _shared_mat_wood
	shaft_mesh.rotation_degrees = Vector3(90, 0, 0)
	shaft_mesh.position = Vector3(0, 0, 0.36)
	add_child(shaft_mesh)

	# 2. Iron Broadhead Arrowhead (pointed cone / wedge at front Z = 0)
	head_mesh = MeshInstance3D.new()
	head_mesh.mesh = _shared_cone_head
	head_mesh.material_override = _shared_mat_iron
	head_mesh.rotation_degrees = Vector3(-90, 0, 0)
	head_mesh.position = Vector3(0, 0, -0.045)
	add_child(head_mesh)

	# 3. Feather Fletchings (3 quills at rear Z = 0.62)
	for i in range(3):
		var fletch := MeshInstance3D.new()
		fletch.mesh = _shared_box_fletch
		fletch.material_override = _shared_mat_feather
		var angle := i * (TAU / 3.0)
		fletch.rotation.z = angle
		fletch.position = Vector3(sin(angle) * 0.024, cos(angle) * 0.024, 0.62)
		add_child(fletch)
		fletchings.append(fletch)

func _physics_process(delta: float) -> void:
	if is_stuck:
		elapsed_time += delta
		if elapsed_time >= despawn_time:
			queue_free()
		return

	elapsed_time += delta
	if elapsed_time > 10.0:
		queue_free()
		return

	# Apply gravity arc
	velocity.y -= gravity * delta

	# Continuous raycast step to prevent tunneling through targets or terrain
	var step := velocity * delta
	var start_pos := global_position
	var end_pos := start_pos + step

	var space_state := get_world_3d().direct_space_state
	if space_state:
		var query := PhysicsRayQueryParameters3D.create(start_pos, end_pos)
		var exclude_rids: Array[RID] = []
		if shooter and is_instance_valid(shooter):
			if shooter is CollisionObject3D:
				exclude_rids.append((shooter as CollisionObject3D).get_rid())
			for child in shooter.get_children():
				if child is CollisionObject3D:
					exclude_rids.append(child.get_rid())
		query.exclude = exclude_rids

		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			_on_impact(hit)
			return

	global_position = end_pos
	_align_to_velocity()

func _on_impact(hit: Dictionary) -> void:
	is_stuck = true
	elapsed_time = 0.0
	global_position = hit.position

	var collider = hit.collider
	if collider:
		if collider.has_method("take_damage"):
			collider.take_damage(damage, shooter)
		elif collider.has_method("chop"):
			collider.chop(shooter)

		# Reparent to hit object if it is a Node3D so arrow sticks to moving prey/trees
		if collider is Node3D and is_instance_valid(collider):
			var prev_xform := global_transform
			get_parent().remove_child(self)
			collider.add_child(self)
			global_transform = prev_xform

	# Stick depth: advance slightly into the impact point
	var embed_offset := velocity.normalized() * 0.12
	global_position += embed_offset
