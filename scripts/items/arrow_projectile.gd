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

func _enter_tree() -> void:
	add_to_group("projectiles")

func _ready() -> void:
	add_to_group("projectiles")
	_build_arrow_model()
	# Align initial rotation to launch velocity
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)

func _build_arrow_model() -> void:
	# Materials
	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.68, 0.52, 0.35) # Ash wood
	mat_wood.roughness = 0.75

	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = Color(0.60, 0.63, 0.68)
	mat_iron.metallic = 0.85
	mat_iron.roughness = 0.35

	var mat_feather := StandardMaterial3D.new()
	mat_feather.albedo_color = Color(0.88, 0.88, 0.86) # Goose quill fletching
	mat_feather.roughness = 0.9

	# 1. Wooden Shaft (length 0.72m, diameter 0.024m)
	shaft_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.72
	cyl.radial_segments = 8
	shaft_mesh.mesh = cyl
	shaft_mesh.material_override = mat_wood
	# In Godot, forward is -Z. Cylinder height is along Y. Rotate 90 deg on X to align along Z.
	shaft_mesh.rotation_degrees = Vector3(90, 0, 0)
	shaft_mesh.position = Vector3(0, 0, 0.36)
	add_child(shaft_mesh)

	# 2. Iron Broadhead Arrowhead (pointed cone / wedge at front Z = 0)
	head_mesh = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.001
	cone.bottom_radius = 0.028
	cone.height = 0.09
	cone.radial_segments = 4 # 4-sided diamond / broadhead cross-section
	head_mesh.mesh = cone
	head_mesh.material_override = mat_iron
	head_mesh.rotation_degrees = Vector3(-90, 0, 0)
	head_mesh.position = Vector3(0, 0, -0.045)
	add_child(head_mesh)

	# 3. Feather Fletchings (3 quills at rear Z = 0.62)
	for i in range(3):
		var fletch := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.002, 0.038, 0.12)
		fletch.mesh = box
		fletch.material_override = mat_feather
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
		if shooter and shooter is CollisionObject3D:
			exclude_rids.append((shooter as CollisionObject3D).get_rid())
		query.exclude = exclude_rids

		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			_on_impact(hit)
			return

	global_position = end_pos

	# Align rotation to velocity vector
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)

func _on_impact(hit: Dictionary) -> void:
	is_stuck = true
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
