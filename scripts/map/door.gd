@tool
class_name Door
extends Marker2D

## An attachment point on a Room. The map generator matches an open door on one
## room against a compatible door on another to connect them (it only ever reads
## the lightweight RoomDoor mirror, never the node).
##
## A door also carries a set of semantic states (extensible, queried with
## the method `has_state`) — open, sealed, boss, locked, etc… 
## A DoorStateLibrary resolves the highest-priority state
## into the door's appearance and whether it blocks. The door owns that
## presentation as its own children, so it can be flipped at runtime.

enum Direction { NORTH, SOUTH, EAST, WEST }

const TILE_SIZE := 16
const BARRIER_NAME := "_DoorBarrier"
const VISUAL_NAME := "_DoorVisual"

## Outward-facing side of the room this door sits on.
@export var direction: Direction = Direction.NORTH:
	set(value):
		direction = value
		queue_redraw()

## Width of the opening in tiles (an authored count, not a Marker2D property). Two
## doors only connect when widths match. For width > 1 the marker is the opening's
## min-corner — the left cell on a horizontal (N/S) wall, the top cell on a
## vertical (E/W) wall — and the opening spreads toward +x / +y from there. Anchoring
## both mates the same way is what lets facing doors line up (see method opening_cells).
@export var width: int = 1:
	set(value):
		width = maxi(value, 1)
		queue_redraw()

## Semantic state tags (order-independent set).
@export var states: Array[StringName] = []:
	set(value):
		states = value
		_refresh_presentation()

## Optional per-door override; falls back to a shared built-in default library.
@export var state_library: DoorStateLibrary

static var _default_library: DoorStateLibrary

static func direction_vector(dir: Direction) -> Vector2i:
	match dir:
		Direction.NORTH: return Vector2i(0, -1)
		Direction.SOUTH: return Vector2i(0, 1)
		Direction.EAST: return Vector2i(1, 0)
		Direction.WEST: return Vector2i(-1, 0)
	return Vector2i.ZERO

static func opposite(dir: Direction) -> Direction:
	match dir:
		Direction.NORTH: return Direction.SOUTH
		Direction.SOUTH: return Direction.NORTH
		Direction.EAST: return Direction.WEST
		Direction.WEST: return Direction.EAST
	return dir

## Two directions can join only when they face each other.
static func directions_compatible(a: Direction, b: Direction) -> bool:
	return opposite(a) == b

## The wall-gap cell this door guards, in room-local tile coordinates.
func get_threshold_cell() -> Vector2i:
	return Vector2i(floori(position.x / float(TILE_SIZE)), floori(position.y / float(TILE_SIZE)))

## Lightweight, SceneTree-free representation used by the generator and tests.
func to_room_door() -> RoomDoor:
	return RoomDoor.new(get_threshold_cell(), direction, width)

# --- State API -----------------------------------------------------------------

func has_state(state: StringName) -> bool:
	return states.has(state)

func add_state(state: StringName) -> void:
	if not states.has(state):
		states.append(state)
		_refresh_presentation()

func remove_state(state: StringName) -> void:
	if states.has(state):
		states.erase(state)
		_refresh_presentation()

func set_states(new_states: Array[StringName]) -> void:
	states = new_states  # setter refreshes presentation

func is_blocking() -> bool:
	var style := _library().resolve(states)
	return style != null and style.blocks

# --- Presentation --------------------------------------------------------------

func _library() -> DoorStateLibrary:
	if state_library != null:
		return state_library
	if _default_library == null:
		_default_library = DoorStateLibrary.create_default()
	return _default_library

## Rebuild the door's presentation from its resolved state. Connected doorways are
## left exactly as the author drew them (opening + floor); the engine only overrides
## tiles to seal a door that ended up unconnected. Interactive states own nodes.
func _refresh_presentation() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	_clear_owned_nodes()
	var style := _library().resolve(states)
	if style == null:
		return
	match style.presentation:
		DoorStateStyle.Presentation.OPEN:
			pass  # Connected doorway's trust tile's default state (i.e. create rooms with all their doors open)
		DoorStateStyle.Presentation.WALL_TILE:
			_seal(style)
		DoorStateStyle.Presentation.ENTITY:
			if style.blocks:
				_build_barrier()
			_build_visual(style)

## Remove any presentation nodes a previous state left behind. Tiles are left alone
## here — only sealing overrides them (see _seal).
func _clear_owned_nodes() -> void:
	for child_name in [BARRIER_NAME, VISUAL_NAME]:
		var n := get_node_or_null(NodePath(child_name))
		if n != null:
			remove_child(n)
			n.free()

## Seal an unconnected doorway by overriding whatever the author drew for an opening:
## stamp wall across the gap and floor beneath it, both sampled from the room's own
## tiles so the patch blends in.
func _seal(style: DoorStateStyle) -> void:
	_carve_floor()
	_stamp_wall(style)

func _stamp_wall(style: DoorStateStyle) -> void:
	var walls := _find_walls_layer()
	if walls == null:
		return
	var v := direction_vector(direction)
	var perp := Vector2i(v.y, -v.x)
	for cell in _door_cells():
		# Match the room's own wall art by sampling a neighbour along the wall line;
		# fall back to the style's configured tile if there is nothing to sample.
		if not _copy_cell(walls, cell, [cell + perp, cell - perp]):
			walls.set_cell(cell, style.tile_source_id, style.tile_atlas_coords, 0)

## Lay floor across the doorway, sampling the tile from the cell just inside the
## threshold so it matches this room's floor whatever tileset the room uses.
func _carve_floor() -> void:
	var floor_layer := _find_floor_layer()
	if floor_layer == null:
		return
	var inward := -direction_vector(direction)
	for cell in _door_cells():
		_copy_cell(floor_layer, cell, [cell + inward])

## Copy the first non-empty cell in `sources` into `target` on `layer` (source id,
## atlas coords and alternative preserved). Returns true if anything was copied.
func _copy_cell(layer: TileMapLayer, target: Vector2i, sources: Array) -> bool:
	for src_cell in sources:
		var sid := layer.get_cell_source_id(src_cell)
		if sid != -1:
			layer.set_cell(target, sid, layer.get_cell_atlas_coords(src_cell), layer.get_cell_alternative_tile(src_cell))
			return true
	return false

## The cell(s) an opening of `w` tiles covers, anchored at `base` and spread along a
## fixed axis — +x on a horizontal (N/S) wall, +y on a vertical (E/W) wall —
## regardless of which way the door faces. Because both mates use the same axis, two
## doors that face each other cover the same columns/rows once aligned, instead of
## spreading apart.
static func opening_cells(base: Vector2i, dir: Direction, w: int) -> Array[Vector2i]:
	var v := direction_vector(dir)
	var perp := Vector2i(1, 0) if v.x == 0 else Vector2i(0, 1)
	var cells: Array[Vector2i] = []
	for i in maxi(w, 1):
		cells.append(base + perp * i)
	return cells

## The wall cell(s) this door occupies, in room-local tile coordinates (the Walls
## layer's space).
func _door_cells() -> Array[Vector2i]:
	return opening_cells(get_threshold_cell(), direction, width)

func _find_room() -> Room:
	var n := get_parent()
	while n != null:
		if n is Room:
			return n as Room
		n = n.get_parent()
	return null

func _find_walls_layer() -> TileMapLayer:
	var room := _find_room()
	return room.get_walls_layer() if room != null else null

func _find_floor_layer() -> TileMapLayer:
	var room := _find_room()
	return room.get_floor_layer() if room != null else null

func _build_barrier() -> void:
	var body := StaticBody2D.new()
	body.name = BARRIER_NAME
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = _opening_size()
	col.shape = shape
	col.position = _opening_offset()
	body.add_child(col)
	add_child(body)

func _build_visual(style: DoorStateStyle) -> void:
	if style.scene != null:
		var vis := style.scene.instantiate()
		vis.name = VISUAL_NAME
		add_child(vis)
	elif style.color.a > 0.0:
		var s := _opening_size()
		var o := _opening_offset()
		var poly := Polygon2D.new()
		poly.name = VISUAL_NAME
		poly.polygon = PackedVector2Array([
			o + Vector2(-s.x / 2.0, -s.y / 2.0),
			o + Vector2(s.x / 2.0, -s.y / 2.0),
			o + Vector2(s.x / 2.0, s.y / 2.0),
			o + Vector2(-s.x / 2.0, s.y / 2.0),
		])
		poly.color = style.color
		add_child(poly)

## Size of the opening this door covers (spans `width` tiles across its facing).
func _opening_size() -> Vector2:
	var span := float(maxi(width, 1) * TILE_SIZE)
	if direction == Direction.NORTH or direction == Direction.SOUTH:
		return Vector2(span, TILE_SIZE)
	return Vector2(TILE_SIZE, span)

## Centre of a multi-tile opening relative to the marker (zero for width 1).
func _opening_offset() -> Vector2:
	var extra := float((maxi(width, 1) - 1) * TILE_SIZE) / 2.0
	if direction == Direction.NORTH or direction == Direction.SOUTH:
		return Vector2(extra, 0)
	return Vector2(0, extra)

func _ready() -> void:
	# Local-transform notifications are what fire when this node is dragged in the
	# editor; the global one alone doesn't reliably catch a drag.
	set_notify_local_transform(true)
	set_notify_transform(true)
	queue_redraw()
	_refresh_presentation()

func _notification(what: int) -> void:
	# Re-snap the editor preview to the grid as the marker is dragged.
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED or what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := Color(0.3, 0.8, 1.0)
	# Opening footprint: the exact cells this door carves, so `width` is visible and
	# updates live as you edit it. Snapped to the tile the marker falls in (matching
	# get_threshold_cell), so an off-grid marker shows where it will really land.
	var size := _opening_size()
	var top_left := Vector2(get_threshold_cell() * TILE_SIZE) - position
	var rect := Rect2(top_left, size)
	draw_rect(rect, Color(col, 0.15), true)
	draw_rect(rect, col, false, 1.0)
	# Facing arrow.
	var v := direction_vector(direction)
	var tip := Vector2(v.x, v.y) * (TILE_SIZE * 0.9)
	draw_line(Vector2.ZERO, tip, col, 1.5)
	draw_circle(tip, 2.0, col)
	draw_circle(Vector2.ZERO, 1.5, col)
