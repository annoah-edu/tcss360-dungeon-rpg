class_name VisibilityMap
extends RefCounted

## Pure, deterministic field-of-view state. Given a set of sight-blocking cells and
## the player's tile, it answers what is visible right now and what has ever been
## seen. Touches no scene nodes, which keeps it fully unit-testable (same contract as
## MapGenerator).
##
## Three states drive rendering:
##   VISIBLE    — in line of sight this instant, drawn at full brightness
##   REMEMBERED — seen at some point, currently out of sight, drawn dimmed
##   UNSEEN     — never seen, drawn as solid black
##
## Visibility uses recursive shadowcasting over eight octants, followed by a symmetry
## pass. The cast alone is fast and gives clean room-shaped shadows but is not
## symmetric in the general case — along a wedge cast through a doorway it lights some
## cells whose own view back is blocked. Symmetry matters in play, since an enemy that
## can see the player from a tile the player cannot see back is read as a bug, so
## method _drop_asymmetric prunes those cells (see enforce_symmetry).

enum State { UNSEEN, REMEMBERED, VISIBLE }

## Prune lit cells that cannot see the origin back. On by default; turning it off is
## slightly faster and useful for isolating the raw cast in tests.
var enforce_symmetry: bool = true

## Cells that stop sight, as a Dictionary used as a set (Vector2i -> true). Walls and
## sealed doors register here; open doorways deliberately do not.
var _blockers: Dictionary = {}
## Cells lit this instant. Rebuilt from scratch by every update_from call.
var _visible: Dictionary = {}
## Cells lit at any point so far. Only ever grows during a run.
var _seen: Dictionary = {}
## Cells that passed the symmetry check at least once. Guards the remembered set so a
## later frame's pruning cannot erase a tile the player legitimately saw earlier.
var _confirmed_seen: Dictionary = {}

# --- Blockers ------------------------------------------------------------------

## Mark (or unmark) a cell as sight-blocking. Idempotent, so rooms that share a wall
## line can both register the shared cells without any coordination.
func set_blocker(cell: Vector2i, blocking: bool = true) -> void:
	if blocking:
		_blockers[cell] = true
	else:
		_blockers.erase(cell)

func is_blocker(cell: Vector2i) -> bool:
	return _blockers.has(cell)

func blocker_count() -> int:
	return _blockers.size()

## Drop all blockers. Seen/visible history is left alone; call reset() for that.
func clear_blockers() -> void:
	_blockers.clear()

## Wipe everything, for a full dungeon rebuild.
func reset() -> void:
	_blockers.clear()
	_visible.clear()
	_seen.clear()
	_confirmed_seen.clear()

# --- Queries -------------------------------------------------------------------

func is_visible_cell(cell: Vector2i) -> bool:
	return _visible.has(cell)

func is_seen(cell: Vector2i) -> bool:
	return _seen.has(cell)

## Single call the renderer uses per cell, so it never has to combine two lookups.
func state_of(cell: Vector2i) -> State:
	if _visible.has(cell):
		return State.VISIBLE
	if _seen.has(cell):
		return State.REMEMBERED
	return State.UNSEEN

func visible_cells() -> Array:
	return _visible.keys()

func seen_cells() -> Array:
	return _seen.keys()

func visible_count() -> int:
	return _visible.size()

func seen_count() -> int:
	return _seen.size()

# --- Field of view ---------------------------------------------------------------

## Recompute what is visible from `origin` within `radius` tiles, and fold the result
## into the remembered set. A radius below 1 lights only the origin, which keeps the
## degenerate case well-defined rather than empty.
func update_from(origin: Vector2i, radius: int) -> void:
	_visible.clear()
	# The player's own tile is always lit, so standing in a doorway or inside a wall
	# never blacks out the screen.
	_mark(origin)
	if radius < 1:
		return
	for octant in 8:
		_cast_octant(origin, radius, octant, 1, 1.0, 0.0)
	if enforce_symmetry:
		_drop_asymmetric(origin)

## Discard lit cells that cannot see `origin` back.
##
## Recursive shadowcasting is fast and gives clean room-shaped shadows, but it is not
## symmetric in the general case: along the edge of a wedge cast through a doorway it
## will light cells whose own view back is blocked. Left alone that reads in game as
## enemies attacking from tiles the player cannot be seen from.
##
## Rather than switch to a fundamentally more expensive permissive-FOV algorithm, we
## keep the fast cast and drop the handful of offenders with a direct line check. Only
## non-blocking cells are tested — a wall is lit on contact by design, and sight *from*
## inside a wall is not meaningful.
func _drop_asymmetric(origin: Vector2i) -> void:
	var doomed: Array = []
	for cell: Vector2i in _visible:
		if cell == origin or _blockers.has(cell):
			continue
		if not _mutual_line_of_sight(cell, origin):
			doomed.append(cell)
	for cell: Vector2i in doomed:
		_visible.erase(cell)
		# The cell was never really visible, so it must not linger as remembered
		# either — unless an earlier, legitimate sighting already recorded it.
		if not _confirmed_seen.has(cell):
			_seen.erase(cell)
	# Everything surviving this pass is genuinely seen; remember that so a later
	# frame's rejection cannot erase it.
	for cell: Vector2i in _visible:
		_confirmed_seen[cell] = true

## Direction-independent line of sight.
##
## Bresenham picks a different cell chain depending on which end it starts from, so a
## one-way check would still leave A and B disagreeing. Requiring both directions to
## be clear makes the relation provably commutative, which is what actually pins the
## symmetry guarantee down.
func _mutual_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	return _line_of_sight(a, b) and _line_of_sight(b, a)

## Unobstructed straight line between two cells? Blockers strictly between the
## endpoints occlude; the endpoints themselves never do. Bresenham, so it agrees with
## how players read a straight sightline.
func _line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx - dy
	var cur := from
	while cur != to:
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			cur.x += sx
		if e2 < dx:
			err += dx
			cur.y += sy
		if cur == to:
			return true
		if _blockers.has(cur):
			return false
	return true

func _mark(cell: Vector2i) -> void:
	_visible[cell] = true
	_seen[cell] = true

## Recursive shadowcast across one octant, one row per call.
##
## `row` is the distance out from the origin. Within a row, columns are scanned from
## the steep slope toward the shallow one; `top`/`bottom` bound the wedge still in
## view. A run of blockers splits that wedge: the span above the run recurses into the
## next row with a tightened `bottom`, and scanning resumes past the run with a raised
## `top`. Those splits are what carve shadows behind walls.
##
## Columns are clamped to `row` so a scan never reaches past the octant's diagonal
## edge. Without that clamp, light escapes along the exact diagonals — a sealed box
## leaks at its four corners, because the corner cell belongs to a neighbouring octant
## that a wall in *this* octant was never asked about.
func _cast_octant(origin: Vector2i, radius: int, octant: int, row: int, top: float, bottom: float) -> void:
	if row > radius or top < bottom:
		return
	# Measure to each cell's far edge rather than its centre. A strict centre test
	# (row*row + col*col <= r*r) notches the cardinal extremes — at r=3 the diagonal
	# (2,2) passes at 8 but (3,1) fails at 10 — leaving a lumpy cross instead of a
	# disc. The half-tile allowance rounds the boundary out.
	var radius_sq := (radius + 0.5) * (radius + 0.5)

	# Steepest column still under `top`, capped at the diagonal, and the shallowest
	# still above `bottom`. Both slopes are measured against cell *centres*, and every
	# comparison below uses the same convention — mixing centre and edge denominators
	# makes the wedge depend on scan direction, which shows up as A seeing B while B
	# cannot see A.
	var start := mini(int(floor(row * top)), row)
	var end := maxi(int(ceil(row * bottom)), 0)

	var was_blocked := false
	var next_bottom := bottom
	for col in range(start, end - 1, -1):
		var cell := origin + _octant_offset(octant, row, col)
		var solid := _blockers.has(cell)
		# Slopes spanned by this cell, again centre-relative.
		var cell_top := (col + 0.5) / float(row)
		var cell_bottom := (col - 0.5) / float(row)

		# Light it when the cell's span overlaps the open wedge at all. Blockers are
		# lit on contact, so you always see the walls of the room you stand in.
		if cell_bottom <= top and cell_top >= bottom:
			# Round pool: Euclidean, so the lit area reads as a circle. (Deliberately
			# not the Chebyshev metric MapGenerator uses for layout spread.)
			if row * row + col * col <= radius_sq:
				_mark(cell)

		if solid:
			if not was_blocked:
				was_blocked = true
				# Hand the span above this blocker to the next row before closing it.
				_cast_octant(origin, radius, octant, row + 1, top, cell_top)
			next_bottom = cell_bottom
		elif was_blocked:
			# Run of blockers ended: reopen the wedge below it and carry on.
			was_blocked = false
			top = next_bottom

	# An unobstructed tail carries the remaining wedge into the next row.
	if not was_blocked:
		_cast_octant(origin, radius, octant, row + 1, top, bottom)

## Map (row, column) in octant space to a world offset. The eight cases are the eight
## reflections/transpositions that tile the full circle from one scan routine.
static func _octant_offset(octant: int, row: int, col: int) -> Vector2i:
	match octant:
		0: return Vector2i(col, -row)
		1: return Vector2i(row, -col)
		2: return Vector2i(row, col)
		3: return Vector2i(col, row)
		4: return Vector2i(-col, row)
		5: return Vector2i(-row, col)
		6: return Vector2i(-row, -col)
		_: return Vector2i(-col, -row)
