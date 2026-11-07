class_name FarmCropInteractable
extends StaticBody3D

func on_interact(actor: Node) -> void:
	if actor and actor.has_node("InventoryManager"):
		var inv: InventoryManager = actor.get_node("InventoryManager")
		inv.add_resource("cabbage", 2)
		inv.add_resource("turnip", 2)
		inv.add_resource("barley", 4)
	if actor and actor.has_node("SurvivalStats"):
		var stats: SurvivalStats = actor.get_node("SurvivalStats")
		stats.eat_food(20.0, true)
