class_name BuildingAssembler
extends Node3D

## Deterministic procedural assembler for medieval Bergen buildings.
## Assembles buildings piece-by-piece from modular 3D components following
## historical Norwegian vernacular timber framing (lafteverk & grindverk).

@export var lot_seed: int = 1360
@export var lot_width_meters: float = 8.0   ## Typical narrow Bergen tenement width
@export var lot_depth_meters: float = 24.0  ## Deep tenement strip stretching back from quay
@export var stories: int = 3
@export var has_waterfront_crane: bool = true
@export var has_rear_stone_cellar: bool = true

var _rng: RandomNumberGenerator

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = lot_seed

## Generates a building hierarchy given a parcel location and orientation
func assemble_tenement(lot_transform: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Tenement_%d" % lot_seed
	root.transform = lot_transform

	# 1. Foundation pass (piles over water/mud, stone sill on land)
	_assemble_foundations(root)

	# 2. Structural framing pass (post-and-beam grindverk bays)
	_assemble_framing(root)

	# 3. Wall infill & openings (timber walls, doors to alleys, shuttered openings)
	_assemble_walls(root)

	# 4. Svalgang / Exterior galleries (hallmarks of Bryggen architecture)
	_assemble_galleries(root)

	# 5. Roof assembly & cargo hoist gables
	_assemble_roofs(root)

	return root

func _assemble_foundations(parent: Node3D) -> void:
	# Pieces will be instantiated and snapped to foundation sockets here
	pass

func _assemble_framing(parent: Node3D) -> void:
	# Interlocking timber corners and structural posts
	pass

func _assemble_walls(parent: Node3D) -> void:
	# Solid planks, log wall segments, alley doors
	pass

func _assemble_galleries(parent: Node3D) -> void:
	# Overhanging wooden catwalks connecting upper stories
	pass

func _assemble_roofs(parent: Node3D) -> void:
	# Pitched sod/shingle roofs and waterfront hoist beam
	pass
