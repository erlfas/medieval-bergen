class_name HUDClockCalendar
extends Control

## Corner HUD widget displaying:
## - Current Time of Day (20-min cycle clock)
## - Calendar (Date, Month, Year, Season)
## - Settler Age (Starts 30 on March 1, 1360)
## - Ambient Temperature & Season indicator

@export var time_manager: TimeManager
@export var season_manager: SeasonManager

@onready var label_time: Label = $PanelContainer/VBoxContainer/HeaderHBox/LabelTime
@onready var label_period: Label = $PanelContainer/VBoxContainer/HeaderHBox/LabelPeriod
@onready var label_date: Label = $PanelContainer/VBoxContainer/LabelDate
@onready var label_season: Label = $PanelContainer/VBoxContainer/MetaHBox/LabelSeason
@onready var label_temp: Label = $PanelContainer/VBoxContainer/MetaHBox/LabelTemp
@onready var label_age: Label = $PanelContainer/VBoxContainer/FooterHBox/LabelAge
@onready var label_day_counter: Label = $PanelContainer/VBoxContainer/FooterHBox/LabelDayCounter
@onready var sun_moon_icon: TextureRect = $PanelContainer/VBoxContainer/HeaderHBox/SunMoonIcon

func _ready() -> void:
	if time_manager == null:
		time_manager = get_tree().get_first_node_in_group("time_manager") as TimeManager
	if season_manager == null:
		season_manager = get_tree().get_first_node_in_group("season_manager") as SeasonManager

	if time_manager:
		time_manager.time_tick.connect(_on_time_tick)
		time_manager.day_advanced.connect(_on_day_advanced)
		time_manager.settler_birthday.connect(_on_birthday)
		time_manager.season_changed.connect(_on_season_changed)

	if season_manager:
		season_manager.weather_changed.connect(_on_weather_changed)

	_refresh_display()

func _process(_delta: float) -> void:
	# Continuously refresh time display
	if time_manager:
		_update_time_label()

func _refresh_display() -> void:
	if not time_manager:
		return

	_update_time_label()
	label_date.text = time_manager.get_formatted_date()
	label_season.text = time_manager.get_season_name()
	label_age.text = "Alder: %d år" % time_manager.settler_age
	label_day_counter.text = "Dag %d" % (time_manager.total_days_survived + 1)

	if season_manager:
		label_temp.text = "%+.1f°C" % season_manager.current_temperature_celsius

func _update_time_label() -> void:
	label_time.text = time_manager.get_formatted_time()

	# Display Day/Dawn/Dusk/Night period indicator
	var hour := time_manager.current_hour
	if hour >= 5 and hour < 8:
		label_period.text = "Morgen (Dawn)"
	elif hour >= 8 and hour < 18:
		label_period.text = "Dag (Day)"
	elif hour >= 18 and hour < 22:
		label_period.text = "Kveld (Dusk)"
	else:
		label_period.text = "Natt (Night)"

func _on_time_tick(_h: int, _m: int) -> void:
	_update_time_label()

func _on_day_advanced(_d: int, _m: int, _y: int) -> void:
	_refresh_display()

func _on_birthday(new_age: int) -> void:
	label_age.text = "Alder: %d år (Bursdag!)" % new_age

func _on_season_changed(_season: TimeManager.Season, season_name: String) -> void:
	label_season.text = season_name

func _on_weather_changed(_rain: bool, _snow: bool, temp: float) -> void:
	label_temp.text = "%+.1f°C" % temp
