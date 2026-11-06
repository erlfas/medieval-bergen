class_name HarvestableTree
extends StaticBody3D

## Harvestable tree (Birch or Spruce) for Medieval Bergen:
## - Birch yields: Birch Bark (for roof waterproofing) + Firewood
## - Spruce yields: Structural Timber Logs (for Lafteverk walls) + Resin

enum TreeType { BIRCH, SPRUCE }

@export var tree_type: TreeType = TreeType.SPRUCE
@export var chop_hits_required: int = 5
@export var timber_logs_yield: int = 4
@export var birch_bark_yield: int = 6
@export var firewood_yield: int = 3

var current_hits: int = 0
var is_felled: bool = false

func on_interact(actor: Node) -> void:
	if is_felled:
		return

	# Actor swings axe / chops tree
	current_hits += 1
	if actor.has_node("SurvivalStats"):
		var stats: SurvivalStats = actor.get_node("SurvivalStats")
		stats.consume_stamina(8.0)

	if current_hits >= chop_hits_required:
		fell_tree(actor)

func fell_tree(harvester: Node) -> void:
	is_felled = true

	# Transfer resources to harvester inventory
	if harvester and harvester.has_node("InventoryManager"):
		var inv: InventoryManager = harvester.get_node("InventoryManager")
		if tree_type == TreeType.SPRUCE:
			inv.add_resource("timber_log", timber_logs_yield)
			inv.add_resource("firewood", firewood_yield)
		elif tree_type == TreeType.BIRCH:
			inv.add_resource("birch_bark", birch_bark_yield)
			inv.add_resource("timber_log", int(timber_logs_yield * 0.5))
			inv.add_resource("firewood", firewood_yield * 2)

	queue_free()

