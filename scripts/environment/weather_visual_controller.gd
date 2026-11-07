class_name WeatherVisualController
extends Node3D

## Visual & Atmospheric Weather Controller for Medieval Bergen 1360
## Handles:
## - Dynamic mountain mist (Fløyen fog density modulation)
## - Coastal rain & winter snowfall streaks
## - Sun intensity and sky horizon dimming during heavy rain
## Optimized for WebGL 2.0 (Draw call impact: max 1 mesh instance)

@export var season_manager: SeasonManager
@export var world_environment: WorldEnvironment
@export var sun_light: DirectionalLight3D

var precipitation_mesh: MeshInstance3D
var precip_material: StandardMaterial3D
var current_weather: int = 0
var target_fog_density: float = 0.0
var target_sun_energy: float = 1.2
var camera_ref: Camera3D

func _ready() -> void:
	if season_manager == null:
		season_manager = get_tree().get_first_node_in_group("season_manager") as SeasonManager
	if world_environment == null:
		world_environment = get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if sun_light == null:
		sun_light = get_tree().get_first_node_in_group("sun_light") as DirectionalLight3D

	if season_manager:
		if season_manager.has_signal("weather_state_changed"):
			season_manager.weather_state_changed.connect(_on_weather_state_changed)

	_create_precipitation_effect()

func _create_precipitation_effect() -> void:
	# Single compound mesh for rain/snow streaks that follows camera
	precipitation_mesh = MeshInstance3D.new()
	precipitation_mesh.name = "PrecipitationStreaks"
	precipitation_mesh.visible = false

	# Build a lightweight multi-streak particle box using SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1360

	# 48 falling streak lines in a 14m x 10m x 14m volume around camera
	for i in range(48):
		var px := rng.randf_range(-7.0, 7.0)
		var py := rng.randf_range(-2.0, 6.0)
		var pz := rng.randf_range(-7.0, 7.0)
		var len_y := rng.randf_range(0.6, 1.2)

		st.add_vertex(Vector3(px, py, pz))
		st.add_vertex(Vector3(px, py - len_y, pz))

	precipitation_mesh.mesh = st.commit()

	precip_material = StandardMaterial3D.new()
	precip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	precip_material.albedo_color = Color(0.75, 0.82, 0.90, 0.45) # Translucent rain blue/grey
	precip_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	precipitation_mesh.material_override = precip_material

	add_child(precipitation_mesh)

func _process(delta: float) -> void:
	# Follow active camera position
	if camera_ref == null or not is_instance_valid(camera_ref):
		camera_ref = get_viewport().get_camera_3d()

	if camera_ref:
		global_position = camera_ref.global_position

	# Smoothly animate precipitation fall
	if precipitation_mesh and precipitation_mesh.visible:
		var fall_speed := 16.0 if current_weather != 4 else 4.0 # Faster for rain, slower for snow
		var pos_y := fmod(Time.get_ticks_msec() * 0.001 * fall_speed, 8.0)
		precipitation_mesh.position.y = -pos_y

	# Smoothly interpolate fog in WorldEnvironment
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		if target_fog_density > 0.0001:
			env.fog_enabled = true
			env.fog_density = lerpf(env.fog_density, target_fog_density, delta * 1.5)
		else:
			env.fog_density = lerpf(env.fog_density, 0.0, delta * 2.0)
			if env.fog_density < 0.0001:
				env.fog_enabled = false

	# Smoothly adjust sun brightness
	if sun_light:
		sun_light.light_energy = lerpf(sun_light.light_energy, target_sun_energy, delta * 2.0)

func _on_weather_state_changed(state: int, _state_name: String) -> void:
	current_weather = state
	match state:
		0: # CLEAR
			target_fog_density = 0.0
			target_sun_energy = 1.2
			if precipitation_mesh:
				precipitation_mesh.visible = false
		1: # OVERCAST_MIST
			target_fog_density = 0.003
			target_sun_energy = 0.85
			if precipitation_mesh:
				precipitation_mesh.visible = false
		2: # DRIZZLE
			target_fog_density = 0.0015
			target_sun_energy = 0.8
			if precipitation_mesh:
				precipitation_mesh.visible = true
				precip_material.albedo_color = Color(0.72, 0.78, 0.85, 0.35)
		3: # HEAVY_RAIN
			target_fog_density = 0.0025
			target_sun_energy = 0.65
			if precipitation_mesh:
				precipitation_mesh.visible = true
				precip_material.albedo_color = Color(0.75, 0.85, 0.95, 0.60)
		4: # SNOW
			target_fog_density = 0.002
			target_sun_energy = 0.9
			if precipitation_mesh:
				precipitation_mesh.visible = true
				precip_material.albedo_color = Color(0.95, 0.96, 1.0, 0.75)
