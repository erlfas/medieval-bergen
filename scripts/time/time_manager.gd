class_name TimeManager
extends Node

## Manages the 20-minute day cycle, calendar, seasons, and settler age for Medieval Bergen 1360.
## 20 real minutes = 1 in-game day (1200 real seconds = 24 in-game hours = 1440 in-game minutes).
## 1 real second = 1.2 in-game minutes = 72 in-game seconds.

signal time_tick(hour: int, minute: int)
signal day_advanced(day: int, month: int, year: int)
signal season_changed(season: Season, season_name: String)
signal settler_birthday(new_age: int)

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const MONTH_NAMES := [
	"Januarius", "Februarius", "Martius", "Aprilis", "Maius", "Junius",
	"Julius", "Augustus", "September", "October", "November", "December"
]

const MONTH_NAMES_NORWEGIAN := [
	"Januar", "Februar", "Mars", "April", "Mai", "Juni",
	"Juli", "August", "September", "Oktober", "November", "Desember"
]

const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

@export_group("Time Configuration")
@export var day_length_seconds: float = 1200.0 ## 20 minutes in real seconds
@export var time_scale: float = 1.0            ## Speed multiplier (for testing/debug)

@export_group("Starting Date & Character")
@export var start_year: int = 1360
@export var start_month: int = 3               ## 1-based (March = 3)
@export var start_day: int = 1                 ## 1st of March
@export var start_hour: int = 7                ## 07:00 morning
@export var start_minute: int = 0
@export var settler_start_age: int = 30
@export var settler_birth_month: int = 3
@export var settler_birth_day: int = 1

# Runtime state
var current_year: int = 1360
var current_month: int = 3
var current_day: int = 1
var current_hour: int = 7
var current_minute: int = 0
var current_second_float: float = 0.0

var total_days_survived: int = 0
var settler_age: int = 30
var current_season: Season = Season.SPRING

# Progress through the current day (0.0 at midnight 00:00, 0.5 at noon 12:00, 1.0 at next midnight)
var day_progress: float = 0.0

func _ready() -> void:
	current_year = start_year
	current_month = start_month
	current_day = start_day
	current_hour = start_hour
	current_minute = start_minute
	settler_age = settler_start_age

	_update_season(false)
	_calculate_day_progress()

func _process(delta: float) -> void:
	# Convert delta real seconds to in-game time
	# 1440 in-game minutes per day_length_seconds
	var minutes_per_real_second := 1440.0 / day_length_seconds
	var in_game_minutes_elapsed := delta * minutes_per_real_second * time_scale

	current_second_float += in_game_minutes_elapsed * 60.0

	var minutes_to_add := int(current_second_float / 60.0)
	if minutes_to_add > 0:
		current_second_float = fmod(current_second_float, 60.0)
		_advance_minutes(minutes_to_add)

	_calculate_day_progress()

func _advance_minutes(minutes: int) -> void:
	var prev_minute := current_minute
	current_minute += minutes

	while current_minute >= 60:
		current_minute -= 60
		_advance_hour()

	if current_minute != prev_minute:
		time_tick.emit(current_hour, current_minute)

func _advance_hour() -> void:
	current_hour += 1
	if current_hour >= 24:
		current_hour = 0
		_advance_day()

func _advance_day() -> void:
	current_day += 1
	total_days_survived += 1

	var max_days := DAYS_IN_MONTH[current_month - 1]
	if current_day > max_days:
		current_day = 1
		current_month += 1
		if current_month > 12:
			current_month = 1
			current_year += 1

	# Check settler birthday
	if current_month == settler_birth_month and current_day == settler_birth_day:
		settler_age += 1
		settler_birthday.emit(settler_age)

	_update_season(true)
	day_advanced.emit(current_day, current_month, current_year)

func _update_season(emit_signal: bool) -> void:
	var prev_season := current_season

	# Bergen seasons:
	# Spring: March (3), April (4), May (5)
	# Summer: June (6), July (7), August (8)
	# Autumn: September (9), October (10), November (11)
	# Winter: December (12), January (1), February (2)
	match current_month:
		3, 4, 5:
			current_season = Season.SPRING
		6, 7, 8:
			current_season = Season.SUMMER
		9, 10, 11:
			current_season = Season.AUTUMN
		12, 1, 2:
			current_season = Season.WINTER

	if emit_signal and prev_season != current_season:
		season_changed.emit(current_season, get_season_name())

func _calculate_day_progress() -> void:
	var total_minutes := float(current_hour * 60 + current_minute) + (current_second_float / 60.0)
	day_progress = total_minutes / 1440.0

func get_season_name() -> String:
	match current_season:
		Season.SPRING: return "Vår (Spring)"
		Season.SUMMER: return "Sommer (Summer)"
		Season.AUTUMN: return "Høst (Autumn)"
		Season.WINTER: return "Vinter (Winter)"
	return "Vår"

func get_formatted_time() -> String:
	return "%02d:%02d" % [current_hour, current_minute]

func get_formatted_date() -> String:
	var month_str := MONTH_NAMES_NORWEGIAN[current_month - 1]
	return "%d. %s %d" % [current_day, month_str, current_year]

func get_season_progress() -> float:
	# Return 0.0 to 1.0 progress through current 3-month season
	var month_in_season := (current_month - 1) % 3
	var day_ratio := float(current_day) / float(DAYS_IN_MONTH[current_month - 1])
	return (float(month_in_season) + day_ratio) / 3.0
