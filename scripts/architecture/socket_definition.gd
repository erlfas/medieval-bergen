class_name SocketDefinition
extends Resource

## Represents a deterministic snap connection point on a modular architectural component.

enum SocketType {
	FOUNDATION_PIER,      # Water/gravel stone sleeper or wooden stilt
	CORNER_POST,          # Vertical timber post (Grindverk) or interlocking log corner (Lafteverk)
	WALL_BOTTOM,          # Lower timber plate
	WALL_TOP,             # Upper wall plate / joist support
	WALL_SIDE,            # Horizontal wall span connector (e.g. 2m, 4m, 6m)
	FLOOR_BEAM,           # Horizontal floor/ceiling joist
	BALCONY_CANTILEVER,   # Overhanging bracket for Svalgang (exterior gallery)
	ROOF_RIDGE,           # Roof peak / purlin
	ROOF_EAVES,           # Gutter / lower roof edge
	ROOF_GABLE,           # Gabled facade beam (with hoist arm support for docks)
	DOORWAY,              # Opening for door frame
	WINDOW_FRAME          # Opening for wooden shutter / small leaded glass
}

@export var socket_name: String = "Socket"
@export var socket_type: SocketType = SocketType.WALL_TOP
@export var relative_transform: Transform3D = Transform3D.IDENTITY
@export var is_occupied: bool = false
@export var allowed_tags: Array[String] = []
