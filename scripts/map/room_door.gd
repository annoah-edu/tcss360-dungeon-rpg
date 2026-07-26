class_name RoomDoor
extends RefCounted

## Pure-data mirror of a Door node: no SceneTree dependency, so the generator
## and unit tests can work with it directly. Coordinates are room-local tiles.

var cell: Vector2i
var direction: Door.Direction
var width: int

func _init(p_cell: Vector2i = Vector2i.ZERO, p_direction: Door.Direction = Door.Direction.NORTH, p_width: int = 1) -> void:
	cell = p_cell
	direction = p_direction
	width = p_width

## Doors connect when they face opposite ways and share the same opening width.
func is_compatible(other: RoomDoor) -> bool:
	return width == other.width and Door.directions_compatible(direction, other.direction)
