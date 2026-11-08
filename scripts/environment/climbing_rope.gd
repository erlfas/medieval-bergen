class_name ClimbingRope
extends Area3D

## Climbing Rope tool entity for Medieval Bergen 1360:
## - Fixed to mountain cliff edge via iron piton stake and ring
## - Braided hemp rope drops down cliff face with knotted handholds
## - Provides safe, effortless climbing up [W] and smooth rappelling down [S]
## - Settler can retrieve the rope [R] when standing near the anchor

signal rope_retrieved

@export var max_rope_length: float = 35.0
@export var rope_radius: float = 0.045
@export var top_anchor_position: Vector3 = Vector3.ZERO
@export var bottom_position: Vector3 = Vector3.ZERO
@export var rope_length: float = 10.0

var anchor_node: Node3D
var rope_mesh_instance: MeshInstance3D
var knots_container: Node3D
var collision_shape: CollisionShape3D

static func create_rope(anchor_pos: Vector3, wall_normal: Vector3, world_state: PhysicsDirectSpaceState3D) -> ClimbingRope:
	var rope := ClimbingRope.new()
	rope.name = "ClimbingRope_%d" % Time.get_ticks_msec()
	rope.top_anchor_position = anchor_pos

	# Raycast downward from anchor point to find cliff base / ground
	var ray_start := anchor_pos + Vector3(0.0, -0.3, 0.0) - wall_normal * 0.15
	var ray_end := ray_start + Vector3.DOWN * 40.0
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	var hit := world_state.intersect_ray(query)

	var ground_y := anchor_pos.y - 12.0
	if not hit.is_empty():
		ground_y = (hit.position as Vector3).y

	var calculated_length := clampf(anchor_pos.y - ground_y, 2.5, 38.0)
	rope.rope_length = calculated_length
	rope.bottom_position = anchor_pos + Vector3(0.0, -calculated_length, 0.0) - wall_normal * 0.1

	return rope

func _ready() -> void:
	add_to_group("climbing_rope")
	_build_rope_mesh()
	_build_collision()

func _build_rope_mesh() -> void:
	# Shared Materials
	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = Color(0.28, 0.29, 0.31)
	mat_iron.metallic = 0.85
	mat_iron.roughness = 0.35

	var mat_hemp := StandardMaterial3D.new()
	mat_hemp.albedo_color = Color(0.72, 0.60, 0.42) # Warm natural Norwegian hemp rope
	mat_hemp.roughness = 0.95

	var mat_knot := StandardMaterial3D.new()
	mat_knot.albedo_color = Color(0.62, 0.50, 0.35)
	mat_knot.roughness = 0.95

	anchor_node = Node3D.new()
	anchor_node.name = "AnchorNode"
	anchor_node.position = top_anchor_position
	add_child(anchor_node)

	knots_container = Node3D.new()
	knots_container.name = "Knots"
	add_child(knots_container)

	var arr_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()

	# 1. Iron Piton & Ring Surface
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_iron)
	var box_pin := BoxMesh.new()
	box_pin.size = Vector3(0.08, 0.35, 0.08)
	st.append_from(box_pin, 0, Transform3D(Basis.IDENTITY, top_anchor_position + Vector3(0.0, 0.1, 0.0)))

	var torus_ring := TorusMesh.new()
	torus_ring.inner_radius = 0.07
	torus_ring.outer_radius = 0.12
	torus_ring.rings = 10
	torus_ring.ring_segments = 6
	var ring_basis := Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0))
	st.append_from(torus_ring, 0, Transform3D(ring_basis, top_anchor_position + Vector3(0.0, 0.22, 0.0)))
	st.generate_tangents()
	st.commit(arr_mesh)

	# 2. Main Hanging Braided Hemp Rope Surface
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_hemp)
	var cyl := CylinderMesh.new()
	cyl.top_radius = rope_radius
	cyl.bottom_radius = rope_radius
	cyl.height = rope_length
	cyl.radial_segments = 10
	var mid_y := top_anchor_position.y - (rope_length * 0.5)
	st.append_from(cyl, 0, Transform3D(Basis.IDENTITY, Vector3(top_anchor_position.x, mid_y, top_anchor_position.z)))
	st.generate_tangents()
	st.commit(arr_mesh)

	# 3. Knots along the rope every 1.6 meters batched into a single surface
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat_knot)
	var sph := SphereMesh.new()
	sph.radius = rope_radius * 1.8
	sph.height = rope_radius * 2.8
	sph.radial_segments = 8
	sph.rings = 4
	var knot_spacing := 1.6
	var current_y := top_anchor_position.y - 1.2
	var has_knots := false
	while current_y > (top_anchor_position.y - rope_length + 0.6):
		st.append_from(sph, 0, Transform3D(Basis.IDENTITY, Vector3(top_anchor_position.x, current_y, top_anchor_position.z)))
		has_knots = true
		current_y -= knot_spacing
	if has_knots:
		st.generate_tangents()
		st.commit(arr_mesh)

	rope_mesh_instance = MeshInstance3D.new()
	rope_mesh_instance.name = "RopeCompoundMesh"
	rope_mesh_instance.mesh = arr_mesh
	add_child(rope_mesh_instance)

func _build_collision() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "RopeAreaShape"
	var cap := CylinderShape3D.new()
	cap.radius = 0.85
	cap.height = rope_length
	collision_shape.shape = cap
	var mid_y := top_anchor_position.y - (rope_length * 0.5)
	collision_shape.position = Vector3(top_anchor_position.x, mid_y, top_anchor_position.z)
	add_child(collision_shape)

## Returns the top anchor point where settler can disembark onto ledge
func get_top_position() -> Vector3:
	return top_anchor_position

## Returns the bottom point of the rope hanging above ground
func get_bottom_position() -> Vector3:
	return top_anchor_position + Vector3(0.0, -rope_length, 0.0)

## Projects any 3D coordinate onto the vertical rope axis
func get_closest_point(pos: Vector3) -> Vector3:
	var clamped_y := clampf(pos.y, top_anchor_position.y - rope_length, top_anchor_position.y)
	return Vector3(top_anchor_position.x, clamped_y, top_anchor_position.z)

## Retrieves / packs up the rope back into the player's inventory
func retrieve_rope(settler: Node) -> void:
	if settler:
		var inv: InventoryManager = settler.get("inventory") as InventoryManager
		if inv == null:
			inv = settler.get_node_or_null("InventoryManager") as InventoryManager
		if inv:
			inv.add_resource("climbing_rope", 1)
	rope_retrieved.emit()
	queue_free()
