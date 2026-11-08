class_name SurvivalStats
extends Node

## Manages core survival vitals for the 1360 Bergen settler:
## - Health, Hunger, Thirst, Warmth, Wetness, Stamina

signal health_depleted
signal vitals_updated(stats: Dictionary)

@export_group("Current Vitals")
@export var health: float = 100.0
@export var max_health: float = 100.0

@export var hunger: float = 100.0       ## 100 = full, 0 = starving
@export var thirst: float = 100.0       ## 100 = hydrated, 0 = dehydrated

@export var warmth: float = 100.0       ## 100 = comfortable, 0 = severe hypothermia
@export var wetness: float = 0.0        ## 0 = dry, 100 = soaking wet (from Bergen rain/streams)

@export var stamina: float = 100.0
@export var max_stamina: float = 100.0

@export_group("Decay Rates per Second")
@export var hunger_decay_rate: float = 0.06
@export var thirst_decay_rate: float = 0.10
@export var stamina_regen_rate: float = 15.0

# Environmental state
var is_near_fire: bool = false
var is_holding_torch: bool = false
var is_sheltered: bool = false
var is_in_rain: bool = false
var ambient_temperature_celsius: float = 6.0 # Typical Bergen autumn

var _vitals_emit_timer: float = 0.0
var _is_dead_emitted: bool = false

func _process(delta: float) -> void:
	_update_vitals(delta)

func _update_vitals(delta: float) -> void:
	# 1. Hunger & Thirst Decay
	hunger = maxf(0.0, hunger - hunger_decay_rate * delta)
	thirst = maxf(0.0, thirst - thirst_decay_rate * delta)

	# 2. Wetness Dynamics (Bergen rain vs fire/shelter drying)
	if is_in_rain and not is_sheltered:
		wetness = minf(100.0, wetness + 4.0 * delta)
	elif is_near_fire:
		wetness = maxf(0.0, wetness - 12.0 * delta)
	elif is_holding_torch:
		wetness = maxf(0.0, wetness - 4.0 * delta)
	elif is_sheltered:
		wetness = maxf(0.0, wetness - 2.5 * delta)

	# 3. Warmth / Temperature Dynamics
	if is_near_fire:
		# Fire warms and restores body heat
		warmth = minf(100.0, warmth + 8.0 * delta)
	elif is_holding_torch:
		# Pine-tar torch radiates warmth to prevent hypothermia
		warmth = minf(100.0, warmth + 4.0 * delta)
	else:
		# Cold environment + wet clothes = hypothermia
		var cold_factor := (18.0 - ambient_temperature_celsius) * 0.15
		var wet_penalty := (wetness / 100.0) * 1.5
		var shelter_mitigation := 0.5 if is_sheltered else 1.0

		var chill_rate := (cold_factor + wet_penalty) * shelter_mitigation * 1.2
		warmth = maxf(0.0, warmth - chill_rate * delta)

	# 4. Health Penalties for Starvation / Dehydration / Freezing
	var damage_taken := 0.0
	if hunger <= 0.0:
		damage_taken += 1.5 * delta
	if thirst <= 0.0:
		damage_taken += 2.5 * delta
	if warmth <= 15.0:
		damage_taken += 3.0 * delta # Hypothermia damage

	# Passive regeneration if well-fed, hydrated and warm
	if hunger > 75.0 and thirst > 75.0 and warmth > 70.0 and damage_taken == 0.0:
		health = minf(max_health, health + 0.8 * delta)
	else:
		health = maxf(0.0, health - damage_taken)

	if health <= 0.0:
		if not _is_dead_emitted:
			_is_dead_emitted = true
			health_depleted.emit()
	else:
		_is_dead_emitted = false

	# 5. Stamina regeneration
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + stamina_regen_rate * delta)

	_vitals_emit_timer -= delta
	if _vitals_emit_timer <= 0.0:
		_vitals_emit_timer = 0.20
		vitals_updated.emit(get_vitals_dict())

func drink_water(is_freshwater: bool) -> bool:
	if not is_freshwater:
		# Saltwater penalty
		thirst = maxf(0.0, thirst - 15.0)
		health = maxf(0.0, health - 5.0)
		vitals_updated.emit(get_vitals_dict())
		return false
	
	thirst = minf(100.0, thirst + 45.0)
	vitals_updated.emit(get_vitals_dict())
	return true

func eat_food(nutrition: float, is_cooked: bool = true) -> void:
	if is_cooked:
		hunger = minf(100.0, hunger + nutrition)
		health = minf(max_health, health + nutrition * 0.1)
	else:
		# Raw meat food poisoning risk
		hunger = minf(100.0, hunger + nutrition * 0.6)
		health = maxf(0.0, health - 10.0)
	vitals_updated.emit(get_vitals_dict())

func consume_stamina(amount: float) -> bool:
	if stamina >= amount:
		stamina -= amount
		return true
	return false

func get_vitals_dict() -> Dictionary:
	return {
		"health": health,
		"hunger": hunger,
		"thirst": thirst,
		"warmth": warmth,
		"wetness": wetness,
		"stamina": stamina,
		"near_fire": is_near_fire,
		"sheltered": is_sheltered
	}
