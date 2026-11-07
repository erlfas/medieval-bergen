class_name SeasonManager
extends Node

## Season & Weather Manager for Bergen 1360.
## Connects seasonal progression to ambient temperatures, snow cover,
## Bergen rain patterns, and feeds environmental data to the settler's survival stats.

enum WeatherState {
	CLEAR,          ## ☀️ Klart kystvær
	OVERCAST_MIST,  ## 🌫️ Fløyen-tåke (Mountain mist)
	DRIZZLE,        ## 🌦️ Kystyr (Coastal drizzle)
	HEAVY_RAIN,     ## 🌧️ Bergensregn (Heavy coastal rain)
	SNOW            ## ❄️ Snøbyger (Winter snow)
}

signal weather_changed(is_raining: bool, is_snowing: bool, temperature: float)
signal weather_state_changed(state: WeatherState, state_name: String)
signal snow_coverage_changed(coverage: float)

@export var time_manager: TimeManager
@export var player_survival_stats: SurvivalStats

# Environmental values
var current_temperature_celsius: float = 3.0
var snow_coverage: float = 0.2 ## 0.0 = no snow (summer), 1.0 = deep snow (winter)
var current_weather: WeatherState = WeatherState.CLEAR
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
	var diurnal_factor := (sin((day_progress - 0.35) * 2.0 * PI) + 1.0) * 0.5
	current_temperature_celsius = lerpf(min_temp, max_temp, diurnal_factor)
	snow_coverage = target_snow

	# 3. Dynamic Bergen Coastal Weather Simulation
	# Bergen weather blocks shift naturally every 3-4 in-game hours
	var weather_seed := int(time_manager.total_days_survived * 8 + time_manager.current_hour / 3)
	var weather_rand := fposmod(sin(float(weather_seed) * 12.9898 + 78.233) * 43758.5453, 1.0)

	var prev_weather := current_weather
	match season:
		TimeManager.Season.WINTER:
			if weather_rand < 0.28:
				current_weather = WeatherState.CLEAR
			elif weather_rand < 0.50:
				current_weather = WeatherState.OVERCAST_MIST
			elif weather_rand < 0.85:
				current_weather = WeatherState.SNOW
			else:
				current_weather = WeatherState.HEAVY_RAIN if current_temperature_celsius > 0.5 else WeatherState.SNOW
		TimeManager.Season.SPRING:
			if weather_rand < 0.35:
				current_weather = WeatherState.CLEAR
			elif weather_rand < 0.55:
				current_weather = WeatherState.OVERCAST_MIST
			elif weather_rand < 0.82:
				current_weather = WeatherState.DRIZZLE
			else:
				current_weather = WeatherState.HEAVY_RAIN
		TimeManager.Season.SUMMER:
			if weather_rand < 0.50:
				current_weather = WeatherState.CLEAR
			elif weather_rand < 0.72:
				current_weather = WeatherState.OVERCAST_MIST
			elif weather_rand < 0.90:
				current_weather = WeatherState.DRIZZLE
			else:
				current_weather = WeatherState.HEAVY_RAIN
		TimeManager.Season.AUTUMN:
			if weather_rand < 0.22:
				current_weather = WeatherState.CLEAR
			elif weather_rand < 0.45:
				current_weather = WeatherState.OVERCAST_MIST
			elif weather_rand < 0.75:
				current_weather = WeatherState.DRIZZLE
			else:
				current_weather = WeatherState.HEAVY_RAIN

	is_precipitating = (current_weather == WeatherState.DRIZZLE or current_weather == WeatherState.HEAVY_RAIN or current_weather == WeatherState.SNOW)
	is_snowing = (current_weather == WeatherState.SNOW)
	is_raining = (current_weather == WeatherState.DRIZZLE or current_weather == WeatherState.HEAVY_RAIN)

	# 4. Feed ambient state to Player SurvivalStats
	if player_survival_stats:
		player_survival_stats.ambient_temperature_celsius = current_temperature_celsius
		player_survival_stats.is_in_rain = is_raining

	weather_changed.emit(is_raining, is_snowing, current_temperature_celsius)
	if current_weather != prev_weather:
		weather_state_changed.emit(current_weather, get_weather_display_name())
	snow_coverage_changed.emit(snow_coverage)

func get_weather_display_name() -> String:
	match current_weather:
		WeatherState.CLEAR:
			return "Klart kystvær"
		WeatherState.OVERCAST_MIST:
			return "Fløyen-tåke"
		WeatherState.DRIZZLE:
			return "Kystyr"
		WeatherState.HEAVY_RAIN:
			return "Bergensregn"
		WeatherState.SNOW:
			return "Snøbyger"
	return "Klart"

func get_weather_icon() -> String:
	match current_weather:
		WeatherState.CLEAR:
			return "[Sol]"
		WeatherState.OVERCAST_MIST:
			return "[Tåke]"
		WeatherState.DRIZZLE:
			return "[Yr]"
		WeatherState.HEAVY_RAIN:
			return "[Regn]"
		WeatherState.SNOW:
			return "[Snø]"
	return "[Sol]"
