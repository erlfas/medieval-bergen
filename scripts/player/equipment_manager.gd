class_name EquipmentManager
extends Node

## Equipment management system for Medieval Bergen 1360:
## - Manages hotbar selection across 5 functional survival slots:
##     [1] Woodcutter's Axe: Heavy melee chopping, fells trees, takes out predators
##     [2] Water Bottle / Horn: Hydration on the go from backpack reservoir, refillable at streams
##     [3] Hunting Knife: Fast agile slashes for wolf defense and harvesting venison/pelts
##     [4] Bow & Arrow: Aims/draws on hold Left Click, fires physics ArrowProjectile on release
##     [5] Pine-tar Torch: Equips warm light, deters hungry wolves, staves off hypothermia
## - Coordinates holding poses on BoxManModel and signals HUD Hotbar updates

signal slot_changed(new_slot: int, old_slot: int)
signal water_reservoir_updated(current: float, maximum: float)
signal arrow_count_updated(current: int)
signal bow_aim_state_changed(is_aiming: bool, draw_progress: float)
signal item_action_triggered(slot: int, action_name: String)

enum Slot {
	NONE = 0,
	AXE = 1,
	WATER_BOTTLE = 2,
	KNIFE = 3,
	BOW = 4,
	TORCH = 5
}

const SLOT_NAMES := {
	Slot.AXE: "Woodcutter's Axe",
	Slot.WATER_BOTTLE: "Drinking Horn / Flask",
	Slot.KNIFE: "Hunting Knife",
	Slot.BOW: "Recurve Bow & Arrow",
	Slot.TORCH: "Pine-tar Torch"
}

@export var current_slot: int = Slot.AXE
@export var water_reservoir: float = 100.0
@export var max_water_reservoir: float = 100.0
@export var water_per_drink: float = 25.0
@export var arrow_count: int = 24

# Cooldowns and Timing
var attack_cooldown: float = 0.0
var is_aiming_bow: bool = false
var bow_draw_time: float = 0.0
var max_bow_draw_time: float = 0.70 # Time in seconds to reach full bow tension

# Node references
var settler: CharacterBody3D
var box_man_model: BoxManModel
var survival_stats: SurvivalStats
var inventory: InventoryManager

func _ready() -> void:
	add_to_group("equipment_manager")
	settler = get_parent() as CharacterBody3D
	_bind_settler_references()
	call_deferred("_initial_sync")

func _bind_settler_references() -> void:
	if settler == null:
		settler = get_parent() as CharacterBody3D
	if settler:
		box_man_model = settler.get_node_or_null("BoxManModel") as BoxManModel
		survival_stats = settler.get_node_or_null("SurvivalStats") as SurvivalStats
		inventory = settler.get_node_or_null("InventoryManager") as InventoryManager

func _initial_sync() -> void:
	_bind_settler_references()
	select_slot(current_slot, true)
	water_reservoir_updated.emit(water_reservoir, max_water_reservoir)
	arrow_count_updated.emit(arrow_count)

func _process(delta: float) -> void:
	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)

	# Update bow draw charge while aiming
	if is_aiming_bow and current_slot == Slot.BOW:
		bow_draw_time = minf(max_bow_draw_time, bow_draw_time + delta)
		var progress := bow_draw_time / max_bow_draw_time
		bow_aim_state_changed.emit(true, progress)
		if box_man_model:
			box_man_model.set_bow_aim(true, progress)

## Selects an equipment slot by number (1 to 5)
func select_slot(slot_idx: int, force: bool = false) -> void:
	if box_man_model == null or settler == null:
		_bind_settler_references()

	if slot_idx < Slot.AXE or slot_idx > Slot.TORCH:
		return
	if current_slot == slot_idx and not force:
		return

	# If currently drawing bow, cancel draw cleanly before switching
	if is_aiming_bow:
		cancel_bow_aim()

	var old_slot := current_slot
	current_slot = slot_idx

	# Update Settler torch state
	if settler:
		var has_torch := (current_slot == Slot.TORCH)
		settler.set("is_holding_torch", has_torch)
		var light: Node = settler.get_node_or_null("Head/TorchLight")
		if light and light is Light3D:
			light.visible = has_torch

	# Update 3D Character Model visual item
	if box_man_model:
		box_man_model.set_equipped_item(current_slot)

	slot_changed.emit(current_slot, old_slot)

func cycle_slot(direction: int) -> void:
	var new_slot := current_slot + direction
	if new_slot > Slot.TORCH:
		new_slot = Slot.AXE
	elif new_slot < Slot.AXE:
		new_slot = Slot.TORCH
	select_slot(new_slot)

## Executes primary use of equipped item (Left Click)
func use_primary(raycast: RayCast3D, camera: Camera3D) -> void:
	if attack_cooldown > 0.0:
		return

	match current_slot:
		Slot.AXE:
			_use_axe(raycast)
		Slot.WATER_BOTTLE:
			drink_from_reservoir()
		Slot.KNIFE:
			_use_knife(raycast)
		Slot.BOW:
			# Bow uses hold & release flow: see start_bow_aim() and release_bow()
			pass
		Slot.TORCH:
			_use_torch(raycast)

## Slot 1: Woodcutter's Axe: Heavy melee swing (28 dmg), chops trees, costs 12 stamina
func _use_axe(raycast: RayCast3D) -> void:
	attack_cooldown = 0.50
	if box_man_model:
		box_man_model.trigger_chop()
	if survival_stats:
		survival_stats.consume_stamina(12.0)

	item_action_triggered.emit(Slot.AXE, "chop")

	if raycast and raycast.is_colliding():
		var target := raycast.get_collider()
		if target:
			if target.has_method("take_damage"):
				target.take_damage(28.0, settler)
			elif target.has_method("chop"):
				target.chop(settler)
			elif target.has_method("on_interact"):
				target.on_interact(settler)

## Slot 2: Drinking Horn / Water Bottle: Hydrates settler on the go from rucksack reservoir
func drink_from_reservoir() -> bool:
	if water_reservoir <= 0.0:
		return false

	var amount_to_drink := minf(water_per_drink, water_reservoir)
	water_reservoir = maxf(0.0, water_reservoir - amount_to_drink)
	attack_cooldown = 0.65

	if box_man_model:
		box_man_model.trigger_drink()

	if survival_stats:
		survival_stats.drink_water(true)

	water_reservoir_updated.emit(water_reservoir, max_water_reservoir)
	item_action_triggered.emit(Slot.WATER_BOTTLE, "drink")
	return true

## Refills backpack water reservoir (called when settler enters freshwater stream or lake)
func refill_reservoir(amount: float = 100.0) -> void:
	water_reservoir = minf(max_water_reservoir, water_reservoir + amount)
	water_reservoir_updated.emit(water_reservoir, max_water_reservoir)
	item_action_triggered.emit(Slot.WATER_BOTTLE, "refill")

## Slot 3: Hunting Knife: Fast agile slashes (22 dmg), 0.22s cooldown, harvesting fallen game
func _use_knife(raycast: RayCast3D) -> void:
	attack_cooldown = 0.22
	if box_man_model:
		box_man_model.trigger_knife_slash()
	if survival_stats:
		survival_stats.consume_stamina(4.5)

	item_action_triggered.emit(Slot.KNIFE, "slash")

	if raycast and raycast.is_colliding():
		var target := raycast.get_collider()
		if target:
			# Check for dead game animal harvesting
			if target.get("current_state") == 4: # DEAD state in WolfAI / DeerAI
				_harvest_animal_corpse(target)
				return

			if target.has_method("take_damage"):
				target.take_damage(22.0, settler)
			elif target.has_method("on_interact"):
				target.on_interact(settler)

func _harvest_animal_corpse(corpse: Node) -> void:
	if not inventory:
		return
	if corpse is WolfAI:
		inventory.add_resource("wolf_pelt", 1)
		corpse.queue_free()
	elif corpse is DeerAI:
		inventory.add_resource("raw_venison", 2)
		inventory.add_resource("deer_hide", 1)
		corpse.queue_free()

## Slot 4: Bow & Arrow Aiming & Firing
func start_bow_aim() -> void:
	if current_slot != Slot.BOW or arrow_count <= 0:
		return
	is_aiming_bow = true
	bow_draw_time = 0.0
	bow_aim_state_changed.emit(true, 0.0)
	if box_man_model:
		box_man_model.set_bow_aim(true, 0.0)

func release_bow(camera: Camera3D) -> void:
	if not is_aiming_bow or current_slot != Slot.BOW:
		return

	var draw_progress := clampf(bow_draw_time / max_bow_draw_time, 0.15, 1.0)
	is_aiming_bow = false
	bow_draw_time = 0.0
	bow_aim_state_changed.emit(false, 0.0)

	if box_man_model:
		box_man_model.set_bow_aim(false, 0.0)

	if arrow_count <= 0:
		return

	# Fire physical ArrowProjectile
	arrow_count -= 1
	arrow_count_updated.emit(arrow_count)
	attack_cooldown = 0.40

	if survival_stats:
		survival_stats.consume_stamina(8.0 * draw_progress)

	_spawn_arrow_projectile(camera, draw_progress)
	item_action_triggered.emit(Slot.BOW, "fire")

func cancel_bow_aim() -> void:
	is_aiming_bow = false
	bow_draw_time = 0.0
	bow_aim_state_changed.emit(false, 0.0)
	if box_man_model:
		box_man_model.set_bow_aim(false, 0.0)

func _spawn_arrow_projectile(camera: Camera3D, draw_progress: float) -> void:
	var arrow_script = load("res://scripts/items/arrow_projectile.gd")
	if not arrow_script:
		return

	var arrow: Node3D = arrow_script.new()
	arrow.add_to_group("projectiles")
	var scene_root: Node = settler.get_parent() if settler else null
	if not scene_root:
		scene_root = get_tree().current_scene if get_tree().current_scene else get_tree().root
	scene_root.add_child(arrow)

	# Calculate launch position and direction from camera / crosshair
	var cam_xform := camera.global_transform if camera else settler.global_transform
	var forward := -cam_xform.basis.z.normalized()
	var launch_speed := lerpf(22.0, 48.0, draw_progress)

	arrow.global_position = cam_xform.origin + forward * 0.85 + Vector3(0, -0.05, 0)
	arrow.set("velocity", forward * launch_speed)
	arrow.set("damage", lerpf(20.0, 50.0, draw_progress))
	arrow.set("shooter", settler)

## Slot 5: Pine-tar Torch: Warmth, illumination, and wolf deterrence
func _use_torch(raycast: RayCast3D) -> void:
	attack_cooldown = 0.35
	if box_man_model:
		box_man_model.trigger_chop()
	if survival_stats:
		survival_stats.consume_stamina(6.0)

	item_action_triggered.emit(Slot.TORCH, "swing")

	if raycast and raycast.is_colliding():
		var target := raycast.get_collider()
		if target and target.has_method("take_damage"):
			target.take_damage(14.0, settler)
