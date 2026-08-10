class_name Connector
extends RefCounted

## A short corridor the generator inserts between two rooms so their walls never touch.
##
## Pure data, like Placement: MapGenerator produces these alongside the room placements,
## and MapAssembler paints them into tiles and registers their occlusion. A connector runs
## `length` tiles outward from a host room's doorway in `direction`, `width` tiles across
## (matching the door), with side walls down its two long edges and both ends left open —
## one opening feeds the host door, the far one feeds the room placed beyond it.
##
## Keeping rooms a corridor apart is what lets each room's occlusion end cleanly at its own
## doorway wall instead of bleeding into the neighbour, and gives the player's visibility a
## neutral zone to settle across while crossing.

## Host door's min-corner cell, in world tile coords — the corridor's mouth (s = 0 sits in
## the host wall; the floor runs s = 1..length outward from here).
var origin: Vector2i = Vector2i.ZERO
## Door.Direction the corridor runs, outward from the host room.
var direction: int = Door.Direction.NORTH
var length: int = 3
var width: int = 3

func _init(p_origin := Vector2i.ZERO, p_direction := Door.Direction.NORTH, p_length := 3, p_width := 3) -> void:
	origin = p_origin
	direction = p_direction
	length = maxi(p_length, 1)
	width = maxi(p_width, 1)

## Unit step outward along the corridor.
func step() -> Vector2i:
	return Door.direction_vector(direction)

## Unit step across the corridor. Matches Door.opening_cells: a vertical run (N/S) spreads
## along x, a horizontal run (E/W) spreads along y.
func across() -> Vector2i:
	var v := step()
	return Vector2i(1, 0) if v.x == 0 else Vector2i(0, 1)

## Floor cells (world) the corridor lays: the interior columns only, s = 1..length. The two
## outermost columns are side walls, so `width` counts the whole passage — wall · floor · wall
## — and the walkable floor is the `width - 2` cells between them.
func floor_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var d := step()
	var p := across()
	for s in range(1, length + 1):
		for i in range(1, width - 1):
			cells.append(origin + d * s + p * i)
	return cells

## Side-wall cells (world): the two long edges, ends left open for the doorways.
func wall_cells() -> Array[Vector2i]:
	return near_wall_cells() + far_wall_cells()

## Whether the corridor runs vertically (a NORTH/SOUTH run). Its side walls then face
## west and east; a horizontal run's face north and south. Callers use this to pick
## directional wall art and the matching under-wall filler.
func is_vertical() -> bool:
	return step().x == 0

## The near side-wall edge (across column 0): the west wall of a vertical run, the north
## wall of a horizontal one. Sits on the outermost door column, flush with the floor.
func near_wall_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var d := step()
	for s in range(1, length + 1):
		cells.append(origin + d * s)
	return cells

## The far side-wall edge (across column width - 1): the east wall of a vertical run, the
## south wall of a horizontal one.
func far_wall_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var d := step()
	var p := across()
	for s in range(1, length + 1):
		cells.append(origin + d * s + p * (width - 1))
	return cells

## Bounding rect over floor and walls, for the generator's overlap tests.
func footprint() -> Rect2i:
	var lo := Vector2i(2147483647, 2147483647)
	var hi := Vector2i(-2147483648, -2147483648)
	for c in floor_cells() + wall_cells():
		lo.x = mini(lo.x, c.x)
		lo.y = mini(lo.y, c.y)
		hi.x = maxi(hi.x, c.x)
		hi.y = maxi(hi.y, c.y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)
