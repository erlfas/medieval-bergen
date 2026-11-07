class_name FarmWellInteractable
extends StaticBody3D

func on_interact(actor: Node) -> void:
	if actor and actor.has_node("SurvivalStats"):
		var stats: SurvivalStats = actor.get_node("SurvivalStats")
		stats.drink_water(true)
	if actor and actor.has_node("InventoryManager"):
		var inv: InventoryManager = actor.get_node("InventoryManager")
		inv.add_resource("freshwater_bucket", 1)
