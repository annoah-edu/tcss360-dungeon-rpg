class_name RoomTemplate
extends RefCounted

## The pure-data description of a room the generator reasons about: its footprint
## and doors in tile space, plus catalog metadata. Extracted once from a room
## scene (see [method Room.to_template]) or built by hand in tests.

var id: StringName
var scene: PackedScene
## Full footprint (floor + walls) in room-local tile coordinates.
var bounds: Rect2i
var doors: Array[RoomDoor] = []
var tags: Array[StringName] = []
var weight: float = 1.0

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)

## Footprint translated to world tile coordinates for a given placement origin.
func footprint(origin: Vector2i) -> Rect2i:
	return Rect2i(origin + bounds.position, bounds.size)

## Interior only (footprint minus its 1-tile wall ring), used for overlap tests
## so neighbouring rooms are allowed to share a wall line.
func interior(origin: Vector2i) -> Rect2i:
	return footprint(origin).grow(-1)
