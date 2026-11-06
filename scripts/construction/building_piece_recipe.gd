class_name BuildingPieceRecipe
extends Resource

## Recipe and blueprint specification for a piece-by-piece modular component.
## Covers traditional Norwegian farmhouse (Årestue), storehouse (Stabbur), and barn (Fjøs).

enum BuildingCategory {
	FARMHOUSE,  # Årestue (Longhouse with central hearth)
	STOREHOUSE, # Stabbur (Raised on stone pillars)
	BARN,       # Fjøs / Låve (Grindverk post-and-beam timber)
	ROOFING,    # Birch bark & turf sod
	DEFENSE     # Palisades & fences
}

@export var piece_id: String = "lafteverk_wall"
@export var piece_name: String = "Lafteverk Log Wall Course"
@export var category: BuildingCategory = BuildingCategory.FARMHOUSE
@export var resource_costs: Dictionary = { "timber_log": 2 }
@export var custom_scene: PackedScene = null

# Sockets provided on this piece for subsequent pieces to snap to
@export var snap_offset: Vector3 = Vector3(0, 1.2, 0)
@export var dimensions: Vector3 = Vector3(4.0, 1.2, 0.3)
@export var provides_shelter: bool = true
@export var is_hearth: bool = false
