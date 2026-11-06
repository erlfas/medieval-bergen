class_name SeasonManager
extends Node

## Season & Weather Manager for Bergen 1360.
## Connects seasonal progression to ambient temperatures, snow cover,
## Bergen rain patterns, and feeds environmental data to the settler's survival stats.

signal weather_changed(is_raining: bool, is_snowing: bool, temperature: float)
signal snow_coverage_changed(coverage: float)

@export var time_manager: TimeManager
@export var player_survival_stats: SurvivalStats

# Environmental values
var current_temperature_celsius: float = 3.0
var snow_coverage: float = 0.2 ## 0.0 = no snow (summer), 1.0 = deep snow (winter)
var is_precipitating: bool = false
var is_snowing: bool = false
var is_raining: bool = false

func _ready() -> void:
	if time_manager == null:
		time_manager = get_tree().get_first_node_in_group("time_manager") as TimeManager

	if time_manager:
		time_manager.time_tick.connect(_on_time_tick)
		time_manager.season_changed.connect(_on_season_changed)

	_update_environment()

func _on_time_tick(_hour: int, _minute: int) -> void:
	_update_environment()

func _on_season_changed(_season: TimeManager.Season, _name: String) -> void:
	_update_environment()

func _update_environment() -> void:
	if not time_manager:
		return

	var season := time_manager.current_season
	var progress := time_manager.get_season_progress()
	var day_progress := time_manager.day_progress

	# 1. Base Seasonal Temperature Profile (°C for coastal western Norway)
	var min_temp: float
	var max_temp: float
	var target_snow: float

	match season:
		TimeManager.Season.WINTER: # Dec, Jan, Feb
			min_temp = -7.0
			max_temp = 1.0
			target_snow = 0.95
		TimeManager.Season.SPRING: # Mar (starts Mar 1), Apr, May
			# March 1st starts cold with melting snow, warming by May
			min_temp = lerpf(-2.0, 5.0, progress)
			max_temp = lerpf(3.0, 13.0, progress)
			target_snow = lerpf(0.65, 0.0, progress)
		TimeManager.Season.SUMMER: # Jun, Jul, Aug
			min_temp = 11.0
			max_temp = 20.0
			target_snow = 0.0
		TimeManager.Season.AUTUMN: # Sep, Oct, Nov
			min_temp = lerpf(9.0, 1.0, progress)
			max_temp = lerpf(16.0, 6.0, progress)
			target_snow = lerpf(0.0, 0.4, progress)

	# 2. Diurnal Temperature Curve (coldest at ~05:00 dawn, warmest at ~14:00)
	# Peak at progress ~ 0.58 (14:00), trough at progress ~ 0.21 (05:00)
	var diurnal_factor := (sin((day_progress - 0.35) * 2.0 * PI) + 1.0) * 0.5
	current_temperature_celsius = lerpf(min_temp, max_temp, diurnal_factor)
	snow_coverage = target_snow

	# 3. Bergen Precipitation (frequent rain in autumn/spring, snow in winter)
	# Precipitation check: snow if freezing, rain otherwise
	is_snowing = (current_temperature_celsius <= 0.5) and is_precipitating
	is_raining = (current_temperature_celsius > 0.5) and is_precipitating

	# 4. Feed ambient state to Player SurvivalStats
	if player_survival_stats:
		player_survival_stats.ambient_temperature_celsius = current_temperature_celsius
		player_survival_stats.is_in_rain = is_raining

	weather_changed.emit(is_raining, is_snowing, current_temperature_celsius)
	snow_coverage_changed.emit(snow_coverage)
