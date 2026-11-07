class_name InventoryManager
extends Node

## Manages settler inventory for harvested resources:
## - Timber Logs (from Spruce/Pine)
## - Birch Bark (from Birch trees for roof waterproofing)
## - Firewood (for campfires & hearths)
## - Stones (for foundations & fireplaces)
## - Turf / Sod (cut from meadow for roofs)

signal inventory_changed(items: Dictionary)
signal resource_added(resource_type: String, amount: int)

@export var max_weight: float = 120.0 # Settler carry weight capacity

var items: Dictionary = {
	"timber_log": 8,     # Starting with a few logs to test building right away
	"birch_bark": 12,
	"firewood": 10,
	"stone": 16,
	"turf": 10,
	"climbing_rope": 2,
	"fresh_cod": 0,
	"fresh_herring": 0,
	"stockfish": 2
}

func add_resource(resource_id: String, amount: int) -> bool:
	if not items.has(resource_id):
		items[resource_id] = 0
	items[resource_id] += amount
	resource_added.emit(resource_id, amount)
	inventory_changed.emit(items)
	return true

func has_resources(costs: Dictionary) -> bool:
	for res_id: String in costs:
		var current_count: int = items.get(res_id, 0)
		if current_count < costs[res_id]:
			return false
	return true

func consume_resources(costs: Dictionary) -> bool:
	if not has_resources(costs):
		return false

	for res_id: String in costs:
		items[res_id] -= costs[res_id]

	inventory_changed.emit(items)
	return true

func get_count(resource_id: String) -> int:
	return items.get(resource_id, 0)
