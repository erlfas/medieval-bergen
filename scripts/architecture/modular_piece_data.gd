class_name ModularPieceData
extends Resource

## Metadata describing a single reusable 3D component (log, plank wall, rafter, door, etc.)

enum BuildingLayer {
	FOUNDATION,   # Stones, piles, mudsills
	STRUCTURE,    # Lafteverk corners, posts, beams
	ENCLOSURE,    # Walls, windows, doors
	FLOORING,     # Decking, joists, svalgang galleries
	ROOFING,      # Rafters, sod, birch bark, shingles
	DECORATION    # Hoist arms, drying racks, ladders, lanterns
}

@export var piece_id: String = ""
@export var piece_name: String = ""
@export var layer: BuildingLayer = BuildingLayer.ENCLOSURE
@export var mesh_scene: PackedScene
@export var bounding_box: AABB = AABB(Vector3(-1, 0, -0.2), Vector3(2, 2.5, 0.4))
@export var sockets: Array[SocketDefinition] = []

# Historical / simulation properties
@export var is_combustible: bool = true
@export var fire_resistance_seconds: float = 60.0
@export var structural_load_capacity: float = 100.0 # How much weight can rest above this
@export var wood_decay_rate: float = 0.05           # Rate of weathering from Bergen rain
