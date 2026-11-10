class_name HarvestableTree
extends StaticBody3D

## Harvestable tree (Birch or Spruce) for Medieval Bergen 1360:
## - Requires exactly 10 chops to fell (`chop_hits_required = 10`)
## - Displays 3D floating progress bar & counter ("Chop 3/10") above trunk notch
## - Displays predicted fall direction (away from settler) & ground trajectory / landing zone
## - Animates realistic topple physics rotation upon 10th chop
## - Spawns physical CarryableLog instances on ground impact

enum TreeType { BIRCH, SPRUCE }

@export var tree_type: TreeType = TreeType.SPRUCE
@export var chop_hits_required: int = 10
@export var timber_logs_yield: int = 4
@export var birch_bark_yield: int = 6
@export var firewood_yield: int = 3
@export var tree_height: float = 8.5

var current_hits: int = 0
var is_felled: bool = false
var is_falling: bool = false

# Topple Physics
var fall_direction: Vector3 = Vector3.FORWARD
var fall_rotation_axis: Vector3 = Vector3.RIGHT
var fall_angle: float = 0.0
var fall_angular_velocity: float = 0.0
var natural_lean: Vector3 = Vector3.ZERO

# Interaction & UI Focus
var focused_settler: Node3D = null
var focus_timer: float = 0.0
var trunk_shake_timer: float = 0.0
var trunk_shake_intensity: float = 0.0

# Hierarchy nodes
var model_pivot: Node3D
var col_shape: CollisionShape3D
var progress_tracker: Node3D
var tracker_label: Label3D
var bar_fill: MeshInstance3D
var bar_bg: MeshInstance3D
var trajectory_indicator: Node3D
var arrow_markers: Array[MeshInstance3D] = []
var arc_beads: Array[MeshInstance3D] = []
var landing_zone_marker: Node3D
var landing_label: Label3D
var notch_mesh: MeshInstance3D
var terrain_generator: Node = null
var multimesh_instance: MultiMeshInstance3D = null
var multimesh_index: int = -1

func _ready() -> void:
	_ensure_setup()
	set_process(false)
	set_physics_process(false)

func _ensure_setup() -> void:
	if model_pivot != null:
		return

	add_to_group("harvestable_trees")
	add_to_group("interactable")

	if is_inside_tree():
		terrain_generator = get_tree().get_first_node_in_group("terrain_generator")

	var current_pos := _get_pos(self)
	var lean_seed := fmod(absf(current_pos.x * 12.9898 + current_pos.z * 78.233), TAU)
	natural_lean = Vector3(sin(lean_seed), 0.0, cos(lean_seed)).normalized()
	if fall_direction == Vector3.FORWARD:
		fall_direction = natural_lean

	_setup_model_pivot()

func _ensure_interaction_ui() -> void:
	if progress_tracker != null:
		return

	_setup_progress_tracker()
	_setup_trajectory_indicator()
	_setup_notch()

	_update_progress_display()
	_update_fall_direction_display()

func _get_pos(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else n.position

func _setup_model_pivot() -> void:
	model_pivot = Node3D.new()
	model_pivot.name = "ModelPivot"
	add_child(model_pivot)

	# Reparent existing visual meshes into model_pivot so whole tree can topple around origin
	var meshes_to_move: Array[Node] = []
	for child in get_children():
		if child is MeshInstance3D and child != model_pivot:
			meshes_to_move.append(child)
		elif child is CollisionShape3D:
			col_shape = child

	for m in meshes_to_move:
		m.reparent(model_pivot)

	# If tree created standalone without procedural generator, construct default meshes
	if model_pivot.get_child_count() == 0 and multimesh_instance == null:
		_build_default_meshes()

func _build_default_meshes() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 4.0
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.14) if tree_type == TreeType.SPRUCE else Color(0.9, 0.9, 0.85)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 1.6 if tree_type == TreeType.SPRUCE else 1.9
	cone.height = 5.0 if tree_type == TreeType.SPRUCE else 3.5
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.14, 0.28, 0.12) if tree_type == TreeType.SPRUCE else Color(0.35, 0.52, 0.18)

	var arr_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(trunk_mat)
	st.append_from(trunk_mesh, 0, Transform3D(Basis(), Vector3(0, 2.0, 0)))
	st.generate_tangents()
	st.commit(arr_mesh)

	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(canopy_mat)
	var canopy_y: float = 5.2 if tree_type == TreeType.SPRUCE else 4.0
	st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, canopy_y, 0)))
	st.generate_tangents()
	st.commit(arr_mesh)

	var tree_mesh := MeshInstance3D.new()
	tree_mesh.name = "TreeCompoundMesh"
	tree_mesh.mesh = arr_mesh
	model_pivot.add_child(tree_mesh)

	if not col_shape:
		col_shape = CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 4.0
		col_shape.shape = capsule
		col_shape.position.y = 2.0
		add_child(col_shape)

func _setup_progress_tracker() -> void:
	progress_tracker = Node3D.new()
	progress_tracker.name = "ProgressTracker"
	# Positioned 0.95m next to the tree trunk at eye level 2.05m
	progress_tracker.position = Vector3(0.95, 2.05, 0.0)
	add_child(progress_tracker)

	# 3D Billboard Chop Counter & Progress Gauge ("Chop 3/10")
	tracker_label = Label3D.new()
	tracker_label.name = "ChopCounterLabel"
	tracker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tracker_label.no_depth_test = true
	tracker_label.render_priority = 15
	tracker_label.font_size = 28
	tracker_label.outline_size = 7
	tracker_label.modulate = Color(1.0, 0.90, 0.35) # Golden amber
	tracker_label.outline_modulate = Color(0.06, 0.05, 0.04, 0.95)
	tracker_label.position = Vector3(0.0, 0.28, 0.0)
	progress_tracker.add_child(tracker_label)

	# 3D Floating Progress Bar Background Frame
	bar_bg = MeshInstance3D.new()
	bar_bg.name = "ProgressBarBG"
	var quad_bg := QuadMesh.new()
	quad_bg.size = Vector2(1.24, 0.15)
	bar_bg.mesh = quad_bg
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.10, 0.11, 0.14, 0.94)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 10
	bar_bg.material_override = bg_mat
	bar_bg.position = Vector3(0.0, 0.02, 0.0)
	progress_tracker.add_child(bar_bg)

	# 3D Floating Progress Bar Fill (Green/Gold fill)
	bar_fill = MeshInstance3D.new()
	bar_fill.name = "ProgressBarFill"
	var quad_fill := QuadMesh.new()
	quad_fill.size = Vector2(1.18, 0.09)
	bar_fill.mesh = quad_fill
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = Color(0.96, 0.78, 0.22, 0.98) # Warm gold
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.no_depth_test = true
	fill_mat.render_priority = 11
	bar_fill.material_override = fill_mat
	bar_fill.position = Vector3(0.0, 0.02, 0.01)
	progress_tracker.add_child(bar_fill)

func _setup_trajectory_indicator() -> void:
	trajectory_indicator = Node3D.new()
	trajectory_indicator.name = "TrajectoryIndicator"
	add_child(trajectory_indicator)

	# Ground Directional Fall Arrow / Corridor markers
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(1.0, 0.76, 0.18, 0.85) # Amber warning glow
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var segment_distances := [1.2, 2.2, 3.2, 4.2, 5.2, 6.2]
	var shared_seg_box := BoxMesh.new()
	shared_seg_box.size = Vector3(0.35, 0.05, 0.6)
	for _d in segment_distances:
		var marker := MeshInstance3D.new()
		marker.mesh = shared_seg_box
		marker.material_override = arrow_mat
		trajectory_indicator.add_child(marker)
		arrow_markers.append(marker)

	# Arrowhead marker at 6.8m
	var tip := MeshInstance3D.new()
	var prism := BoxMesh.new()
	prism.size = Vector3(0.7, 0.05, 0.5)
	tip.mesh = prism
	tip.material_override = arrow_mat
	trajectory_indicator.add_child(tip)
	arrow_markers.append(tip)

	# Landing Zone Target Marker
	landing_zone_marker = Node3D.new()
	landing_zone_marker.name = "LandingZoneMarker"
	trajectory_indicator.add_child(landing_zone_marker)

	# Circular Target Ring
	var ring_mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.15
	torus.outer_radius = 1.35
	ring_mesh.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.70, 0.15, 0.90)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mesh.material_override = ring_mat
	landing_zone_marker.add_child(ring_mesh)

	# Target Crosshair
	var cross1 := MeshInstance3D.new()
	var cbox1 := BoxMesh.new()
	cbox1.size = Vector3(0.12, 0.04, 2.2)
	cross1.mesh = cbox1
	cross1.material_override = ring_mat
	landing_zone_marker.add_child(cross1)

	var cross2 := MeshInstance3D.new()
	var cbox2 := BoxMesh.new()
	cbox2.size = Vector3(2.2, 0.04, 0.12)
	cross2.mesh = cbox2
	cross2.material_override = ring_mat
	landing_zone_marker.add_child(cross2)

	# 3D Billboard Landing Zone Title
	landing_label = Label3D.new()
	landing_label.name = "LandingLabel"
	landing_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	landing_label.no_depth_test = true
	landing_label.font_size = 24
	landing_label.outline_size = 6
	landing_label.modulate = Color(1.0, 0.85, 0.25)
	landing_label.outline_modulate = Color(0.05, 0.04, 0.03, 0.95)
	landing_label.text = "🎯 PREDICTED LANDING ZONE (Fallretning)"
	landing_label.position = Vector3(0.0, 0.6, 0.0)
	landing_zone_marker.add_child(landing_label)

	# Projected Dotted Trajectory Arc
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = Color(0.35, 0.95, 0.45, 0.90) # Radiant arc green
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var arc_bead_count := 10
	var shared_bead_sphere := SphereMesh.new()
	shared_bead_sphere.radius = 0.09
	shared_bead_sphere.height = 0.18
	for i in range(arc_bead_count):
		var bead := MeshInstance3D.new()
		bead.mesh = shared_bead_sphere
		bead.material_override = arc_mat
		trajectory_indicator.add_child(bead)
		arc_beads.append(bead)

func _setup_notch() -> void:
	notch_mesh = MeshInstance3D.new()
	notch_mesh.name = "TrunkNotch"
	var wedge := BoxMesh.new()
	wedge.size = Vector3(0.32, 0.18, 0.24)
	notch_mesh.mesh = wedge
	var notch_mat := StandardMaterial3D.new()
	notch_mat.albedo_color = Color(0.85, 0.72, 0.48) # Freshly cut inner wood grain
	notch_mesh.material_override = notch_mat
	notch_mesh.position = Vector3(0.0, 1.1, 0.2)
	notch_mesh.visible = false
	if model_pivot:
		model_pivot.add_child(notch_mesh)
	else:
		add_child(notch_mesh)

var _last_displayed_fall_dir: Vector3 = Vector3.ZERO
static var _shared_stump_mesh: CylinderMesh = null
static var _shared_stump_shape: CylinderShape3D = null
static var _shared_stump_mat_spruce: StandardMaterial3D = null
static var _shared_stump_mat_birch: StandardMaterial3D = null

func _process(delta: float) -> void:
	if is_falling or is_felled:
		return

	# Handle focus timeout & smooth fall direction calculation
	if focus_timer > 0.0:
		focus_timer -= delta
		if progress_tracker:
			progress_tracker.visible = true
		if trajectory_indicator:
			trajectory_indicator.visible = true

		if focused_settler and is_instance_valid(focused_settler):
			var my_pos := _get_pos(self)
			var settler_pos := _get_pos(focused_settler)
			var dist := my_pos.distance_to(settler_pos)
			# As long as settler is within 4.5m, maintain active focus
			if dist < 4.5:
				focus_timer = maxf(focus_timer, 2.5)

			# Tree falls away from settler
			var away_dir: Vector3 = my_pos - settler_pos
			away_dir.y = 0.0
			if away_dir.length_squared() > 0.01:
				var target_dir := away_dir.normalized()
				fall_direction = fall_direction.slerp(target_dir, delta * 8.0).normalized()

		if fall_direction.distance_squared_to(_last_displayed_fall_dir) > 0.0004:
			_update_fall_direction_display()
		_update_tracker_orientation()

		if focus_timer <= 0.0:
			if progress_tracker:
				progress_tracker.visible = false
			if trajectory_indicator:
				trajectory_indicator.visible = false
			focused_settler = null

	# Visual trunk tremor / shake reaction on axe chop
	if trunk_shake_timer > 0.0:
		trunk_shake_timer -= delta
		if model_pivot:
			var damp := trunk_shake_timer / 0.25
			var shake_offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (trunk_shake_intensity * damp)
			model_pivot.position = shake_offset
		if trunk_shake_timer <= 0.0 and model_pivot:
			model_pivot.position = Vector3.ZERO

	if focus_timer <= 0.0 and trunk_shake_timer <= 0.0:
		set_process(false)

func _physics_process(delta: float) -> void:
	if not is_falling:
		return

	# Realistic gravity torque acceleration: tau = M * g * (L/2) * sin(theta)
	var torque: float = 4.8 * sin(maxf(fall_angle, 0.08))
	fall_angular_velocity += torque * delta
	fall_angle += fall_angular_velocity * delta

	if model_pivot:
		model_pivot.transform.basis = Basis(fall_rotation_axis, fall_angle)

	# When tree tilts past 88 degrees, it impacts ground
	if fall_angle >= deg_to_rad(88.0):
		_on_hit_ground()

func _update_tracker_orientation() -> void:
	if not progress_tracker or not progress_tracker.visible:
		return

	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	var observer: Node3D = focused_settler if focused_settler and is_instance_valid(focused_settler) else cam
	if observer:
		var my_pos := _get_pos(self)
		var obs_pos := _get_pos(observer)
		var to_obs: Vector3 = obs_pos - my_pos
		to_obs.y = 0.0
		if to_obs.length_squared() > 0.01:
			var obs_dir := to_obs.normalized()
			var side_dir := obs_dir.cross(Vector3.UP).normalized()
			var target_pos := side_dir * 0.95 + obs_dir * 0.25 + Vector3(0.0, 2.05, 0.0)
			progress_tracker.position = progress_tracker.position.lerp(target_pos, 0.15)

	if cam:
		var dir := cam.global_position - progress_tracker.global_position
		if Vector2(dir.x, dir.z).length_squared() > 0.01:
			progress_tracker.rotation = Vector3(0.0, atan2(dir.x, dir.z), 0.0)

func _update_progress_display() -> void:
	if not progress_tracker:
		return

	var type_name := "🌲 Gran (Spruce)" if tree_type == TreeType.SPRUCE else "🪵 Bjørk (Birch)"
	var meter := ""
	for i in range(chop_hits_required):
		if i < current_hits:
			meter += "■ "
		else:
			meter += "□ "
	meter = meter.strip_edges()

	if tracker_label:
		tracker_label.text = "%s\nChop %d / %d\n[ %s ]" % [type_name, current_hits, chop_hits_required, meter]

	if bar_fill:
		var ratio := clampf(float(current_hits) / float(chop_hits_required), 0.0, 1.0)
		bar_fill.scale.x = maxf(0.01, ratio)
		# Left-align the fill bar within the 1.18 width frame
		bar_fill.position.x = -0.59 * (1.0 - ratio)

		# Color transition: Warm gold -> Vibrant Emerald Green as chopping finishes
		var mat := bar_fill.material_override as StandardMaterial3D
		if mat:
			if ratio < 0.6:
				mat.albedo_color = Color(0.96, 0.78, 0.22, 0.98) # Gold
			else:
				mat.albedo_color = Color(0.28, 0.88, 0.36, 0.98) # Green

func _update_fall_direction_display() -> void:
	if not trajectory_indicator or not trajectory_indicator.visible:
		return

	_last_displayed_fall_dir = fall_direction
	var horiz_dir := Vector3(fall_direction.x, 0.0, fall_direction.z).normalized()
	if horiz_dir.length_squared() < 0.01:
		horiz_dir = Vector3.FORWARD

	var target_dist := 7.5
	var segment_distances := [1.2, 2.2, 3.2, 4.2, 5.2, 6.2, 6.8]
	var rot_y := atan2(horiz_dir.x, horiz_dir.z)

	# Update Ground Directional Arrow Markers
	for i in range(min(arrow_markers.size(), segment_distances.size())):
		var d: float = segment_distances[i]
		var marker := arrow_markers[i]
		var world_pos := global_position + horiz_dir * d
		var ground_y := _sample_ground_height(world_pos.x, world_pos.z)
		marker.global_position = Vector3(world_pos.x, ground_y + 0.08, world_pos.z)
		marker.rotation.y = rot_y

	# Update Landing Zone Target Marker
	if landing_zone_marker:
		var landing_world := global_position + horiz_dir * target_dist
		var landing_ground_y := _sample_ground_height(landing_world.x, landing_world.z)
		landing_zone_marker.global_position = Vector3(landing_world.x, landing_ground_y + 0.06, landing_world.z)
		landing_zone_marker.rotation.y = rot_y

	# Update Projected Trajectory Arc beads (quarter circle from top down to ground impact)
	var arc_count := arc_beads.size()
	for i in range(arc_count):
		var frac := float(i) / float(arc_count - 1)
		var angle := frac * (PI * 0.5)
		var r_y := tree_height * cos(angle)
		var r_d := target_dist * sin(angle)

		var bead := arc_beads[i]
		var bead_pos := global_position + horiz_dir * r_d + Vector3(0.0, r_y, 0.0)
		bead.global_position = bead_pos

func _update_notch_display() -> void:
	if notch_mesh:
		if current_hits > 0:
			notch_mesh.visible = true
			var ratio := float(current_hits) / float(chop_hits_required)
			notch_mesh.scale = Vector3(1.0 + ratio * 0.5, 1.0 + ratio * 0.4, 0.4 + ratio * 1.6)
			notch_mesh.position = fall_direction * 0.18 + Vector3(0.0, 1.1, 0.0)
		else:
			notch_mesh.visible = false

func _sample_ground_height(x: float, z: float) -> float:
	if terrain_generator and terrain_generator.has_method("sample_height"):
		return terrain_generator.sample_height(x, z)
	return global_position.y

func set_settler_focus(settler: Node) -> void:
	if is_felled or is_falling:
		return

	_ensure_setup()
	_ensure_interaction_ui()

	if settler != null and settler is Node3D:
		focused_settler = settler as Node3D
		focus_timer = 2.5
		set_process(true)
		if progress_tracker:
			progress_tracker.visible = true
		if trajectory_indicator:
			trajectory_indicator.visible = true

		var away_dir: Vector3 = _get_pos(self) - _get_pos(focused_settler)
		away_dir.y = 0.0
		if away_dir.length_squared() > 0.01:
			fall_direction = away_dir.normalized()

		_update_progress_display()
		_update_fall_direction_display()
		_update_notch_display()
	else:
		if focus_timer > 1.2:
			focus_timer = 1.2

func on_interact(actor: Node) -> void:
	chop(actor)

func take_damage(_amount: float = 0.0, actor: Node = null) -> void:
	chop(actor)

func chop(actor: Node) -> void:
	if is_felled or is_falling:
		return

	_ensure_setup()
	set_settler_focus(actor)
	focus_timer = 4.0 # Keep displayed for 4 seconds after chopping
	set_process(true)

	if actor and actor is Node3D:
		var away_dir: Vector3 = _get_pos(self) - _get_pos(actor as Node3D)
		away_dir.y = 0.0
		if away_dir.length_squared() > 0.01:
			fall_direction = away_dir.normalized()

	current_hits += 1

	if actor and actor.has_node("SurvivalStats"):
		var stats: Node = actor.get_node("SurvivalStats")
		if stats and stats.get("stamina") != null and float(stats.get("stamina")) > 0.0:
			stats.call("consume_stamina", 6.0)

	trunk_shake_intensity = 0.08
	trunk_shake_timer = 0.25

	_update_progress_display()
	_update_fall_direction_display()
	_update_notch_display()

	if current_hits >= chop_hits_required:
		fell_tree(actor)

func fell_tree(_harvester: Node) -> void:
	is_falling = true
	set_process(false)
	set_physics_process(true)

	# If attached to a MultiMesh instance, hide that instance in MultiMesh
	if multimesh_instance and is_instance_valid(multimesh_instance) and multimesh_index >= 0:
		var mm: MultiMesh = multimesh_instance.multimesh
		if mm and multimesh_index < mm.instance_count:
			mm.set_instance_transform(multimesh_index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -999, 0)))

	# Ensure we have a visual compound mesh in model_pivot to animate the toppling fall
	if model_pivot and model_pivot.get_child_count() == 0:
		_build_default_meshes()

	# Hide tracker and ground indicator during falling animation
	if progress_tracker:
		progress_tracker.visible = false
	if trajectory_indicator:
		trajectory_indicator.visible = false

	# Disable collision shape so settler does not snag on trunk during topple
	if col_shape:
		col_shape.disabled = true
	collision_layer = 0
	collision_mask = 0

	# Lock in final fall direction
	var horiz_dir := Vector3(fall_direction.x, 0.0, fall_direction.z).normalized()
	if horiz_dir.length_squared() < 0.01:
		horiz_dir = Vector3.FORWARD
	fall_direction = horiz_dir

	# Fall rotation axis is perpendicular to fall direction and UP
	fall_rotation_axis = Vector3.UP.cross(fall_direction).normalized()
	if fall_rotation_axis.length_squared() < 0.01:
		fall_rotation_axis = Vector3.RIGHT

	fall_angle = 0.03
	fall_angular_velocity = 0.0

func _on_hit_ground() -> void:
	is_falling = false
	is_felled = true

	# Spawn physical FallenTreeStem with visual cut guides for bucking into 4m logs
	_spawn_fallen_stem()

	# Spawn cut tree stump at original position
	_spawn_tree_stump()

	queue_free()

func _spawn_fallen_stem() -> void:
	var parent := get_parent()
	if not parent:
		return

	var stem_script = load("res://scripts/environment/fallen_tree_stem.gd")
	var stem := StaticBody3D.new()
	stem.name = "FallenStem_%d" % Time.get_ticks_msec()
	stem.set_script(stem_script)
	stem.set("tree_type", tree_type)
	stem.set("total_length", 12.0)
	stem.set("log_section_length", 4.0)

	parent.add_child(stem)
	stem.global_position = global_position
	var rot_y := atan2(fall_direction.x, fall_direction.z)
	stem.rotation.y = rot_y

func _spawn_carryable_logs() -> void:
	_spawn_fallen_stem()
	var parent := get_parent()
	if not parent:
		return

	var log_script = load("res://scripts/environment/carryable_log.gd")
	var distances := [2.0, 3.8, 5.6]
	var log_type_val = (0 if tree_type == TreeType.SPRUCE else 1)

	for i in range(distances.size()):
		var d: float = distances[i]
		var log_pos := global_position + fall_direction * d
		var ground_y := _sample_ground_height(log_pos.x, log_pos.z)
		log_pos.y = ground_y + 0.35

		var log_inst := RigidBody3D.new()
		log_inst.name = "CarryableLog_%d" % [Time.get_ticks_msec() + i]
		log_inst.set_script(log_script)
		log_inst.set("log_type", log_type_val)

		# Timber yields per log (total ~4 logs per spruce tree)
		if i == 0:
			log_inst.set("timber_logs_yield", 2)
		else:
			log_inst.set("timber_logs_yield", 1)

		parent.add_child(log_inst)
		log_inst.global_position = log_pos

		# Orient log horizontally perpendicular to fall direction
		var log_facing := fall_direction.rotated(Vector3.UP, deg_to_rad(90.0)).normalized()
		var log_up := Vector3.UP
		var log_right := log_facing.cross(log_up).normalized()
		log_inst.basis = Basis(log_right, log_up, -log_facing)

		# Natural slight physical scatter impulse
		var rand_x := randf_range(-0.4, 0.4)
		var rand_z := randf_range(-0.4, 0.4)
		log_inst.apply_impulse(Vector3(rand_x, 0.8, rand_z))

func _spawn_tree_stump() -> void:
	var parent := get_parent()
	if not parent:
		return

	if _shared_stump_mesh == null:
		_shared_stump_mesh = CylinderMesh.new()
		_shared_stump_mesh.top_radius = 0.24
		_shared_stump_mesh.bottom_radius = 0.28
		_shared_stump_mesh.height = 0.45
		_shared_stump_shape = CylinderShape3D.new()
		_shared_stump_shape.radius = 0.26
		_shared_stump_shape.height = 0.45
		_shared_stump_mat_spruce = StandardMaterial3D.new()
		_shared_stump_mat_spruce.albedo_color = Color(0.32, 0.22, 0.14)
		_shared_stump_mat_birch = StandardMaterial3D.new()
		_shared_stump_mat_birch.albedo_color = Color(0.88, 0.86, 0.82)

	var stump := StaticBody3D.new()
	stump.name = "TreeStump_%d" % Time.get_ticks_msec()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _shared_stump_mesh
	mesh_inst.position.y = 0.225
	mesh_inst.material_override = _shared_stump_mat_spruce if tree_type == TreeType.SPRUCE else _shared_stump_mat_birch
	stump.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.shape = _shared_stump_shape
	col.position.y = 0.225
	stump.add_child(col)

	parent.add_child(stump)
	stump.global_position = global_position
