class_name DayNightCycle
extends Node3D

## Day/Night Cycle for Bergen 1360 (~60.4° North Latitude).
## Dynamically rotates sun and adjusts celestial lighting, shadows, colors,
## and Bergen seasonal day lengths (long summer twilight, short dark winter days).

@export var time_manager: TimeManager
@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D
@export var world_environment: WorldEnvironment

@export_group("Latitude & Solar Declination")
@export var bergen_latitude_deg: float = 60.4

@export_group("Sun Colors")
@export var sun_color_day: Color = Color(1.0, 0.96, 0.90)
@export var sun_color_sunset: Color = Color(1.0, 0.58, 0.28)
@export var sun_color_twilight: Color = Color(0.40, 0.45, 0.65)
@export var moon_color: Color = Color(0.65, 0.75, 0.90)

func _ready() -> void:
	if time_manager == null:
		time_manager = get_tree().get_first_node_in_group("time_manager") as TimeManager

func _process(_delta: float) -> void:
	if time_manager:
		_update_celestial_bodies(time_manager.day_progress, time_manager.current_month, time_manager.current_day)

func _update_celestial_bodies(progress: float, month: int, day: int) -> void:
	# Calculate approximate solar declination angle based on day of year
	# Vernal equinox (March 21) declination ~ 0°
	# Summer solstice (June 21) declination ~ +23.4°
	# Autumnal equinox (Sept 21) declination ~ 0°
	# Winter solstice (Dec 21) declination ~ -23.4°
	var day_of_year := _calculate_day_of_year(month, day)
	var declination_rad := deg_to_rad(23.44) * sin(2.0 * PI * (float(day_of_year) - 80.0) / 365.25)

	# Hour angle: progress 0.5 is solar noon (hour_angle = 0), progress 0.0 is midnight (-PI), progress 1.0 is next midnight (+PI)
	var hour_angle_rad := (progress - 0.5) * 2.0 * PI

	# Solar elevation (altitude) and azimuth at Bergen latitude (phi)
	var phi := deg_to_rad(bergen_latitude_deg)
	var sin_altitude := sin(phi) * sin(declination_rad) + cos(phi) * cos(declination_rad) * cos(hour_angle_rad)
	var altitude_rad := asin(clampf(sin_altitude, -1.0, 1.0))
	var altitude_deg := rad_to_deg(altitude_rad)

	# Solar azimuth calculation
	var cos_azimuth := (sin(declination_rad) - sin(phi) * sin_altitude) / (cos(phi) * cos(altitude_rad))
	var azimuth_rad := acos(clampf(cos_azimuth, -1.0, 1.0))
	if sin(hour_angle_rad) > 0.0:
		azimuth_rad = 2.0 * PI - azimuth_rad

	# Rotate Sun Light
	if sun_light:
		sun_light.rotation = Vector3(-altitude_rad, azimuth_rad, 0.0)

		# Adjust Sun energy & color based on solar altitude
		if altitude_deg > 5.0:
			# Full day
			sun_light.visible = true
			sun_light.light_energy = clampf(sin(altitude_rad) * 1.5, 0.2, 1.3)
			sun_light.light_color = sun_color_day
			sun_light.shadow_enabled = true
		elif altitude_deg > -4.0:
			# Sunset / Dawn golden hour & twilight
			sun_light.visible = true
			var t := (altitude_deg - (-4.0)) / 9.0
			sun_light.light_energy = lerpf(0.05, 0.8, t)
			sun_light.light_color = sun_color_sunset.lerp(sun_color_day, t)
			sun_light.shadow_enabled = t > 0.4
		else:
			# Night time
			sun_light.visible = false
			sun_light.light_energy = 0.0

	# Rotate Moon Light (opposite the sun)
	if moon_light:
		moon_light.rotation = Vector3(altitude_rad, azimuth_rad + PI, 0.0)
		if altitude_deg < -2.0:
			moon_light.visible = true
			moon_light.light_energy = 0.15
			moon_light.light_color = moon_color
		else:
			moon_light.visible = false

	# Adjust environment ambient & sky lighting
	_update_environment_lighting(altitude_deg)

func _update_environment_lighting(solar_altitude_deg: float) -> void:
	if not world_environment or not world_environment.environment:
		return

	var env := world_environment.environment
	if solar_altitude_deg > 0.0:
		var day_factor := clampf(solar_altitude_deg / 20.0, 0.0, 1.0)
		env.ambient_light_energy = lerpf(0.6, 1.25, day_factor)
		env.ambient_light_color = Color(0.55, 0.62, 0.72).lerp(Color(0.88, 0.90, 0.95), day_factor)
	else:
		var night_factor := clampf((-solar_altitude_deg) / 12.0, 0.0, 1.0)
		env.ambient_light_energy = lerpf(0.6, 0.25, night_factor)
		env.ambient_light_color = Color(0.22, 0.28, 0.38)

func _calculate_day_of_year(month: int, day: int) -> int:
	var total := 0
	for m in range(1, month):
		total += TimeManager.DAYS_IN_MONTH[m - 1]
	return total + day
