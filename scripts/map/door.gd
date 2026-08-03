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
const OCCLUDER_NAME := "_DoorOccluder"

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
	var style := _resolve_style()
	return style != null and style.blocks

# --- Presentation --------------------------------------------------------------

func _library() -> DoorStateLibrary:
	if state_library != null:
		return state_library
	return _fallback_library()

static func _fallback_library() -> DoorStateLibrary:
	if _default_library == null:
		_default_library = DoorStateLibrary.create_default()
	return _default_library

## Resolve the current states to a style, falling back to the built-in library when a
## custom one has nothing to say about them. An override is meant to *specialize* a few
## states, not to redefine every one; without this fallback a library that omits
## `sealed` silently leaves unconnected doorways standing open, because a null style
## makes _refresh_presentation() bail before it can stamp a wall.
func _resolve_style() -> DoorStateStyle:
	var style := _library().resolve(states)
	if style == null:
		style = _fallback_library().resolve(states)
	return style

## Rebuild the door's presentation from its resolved state. Connected doorways are
## left exactly as the author drew them (opening + floor); the engine only overrides
## tiles to seal a door that ended up unconnected. Interactive states own nodes.
func _refresh_presentation() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	_clear_owned_nodes()
	var style := _resolve_style()
	if style == null:
		return
	# A hand-authored seal occluder (a LightOccluder2D child) blocks sight only while the
	# door is sealed, so switch it on for a WALL_TILE seal and off otherwise. The author
	# sees it in the editor; the door decides when it is live.
	var sealed := style.presentation == DoorStateStyle.Presentation.WALL_TILE
	_set_authored_occluders_active(sealed)
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
	for child_name in [BARRIER_NAME, VISUAL_NAME, OCCLUDER_NAME]:
		var n := get_node_or_null(NodePath(child_name))
		if n != null:
			remove_child(n)
			n.free()

## Seal an unconnected doorway by overriding whatever the author drew for an opening:
## fix up the floor under the gap (see method _seal_floor()) and stamp a wall across it
## (chosen from the door's orientation — see method _stamp_wall()).
func _seal(style: DoorStateStyle) -> void:
	_seal_floor(style)
	_stamp_wall(style)
	# The author may have drawn the seal occluder by hand (now switched on above); only
	# compute one when they have not, so hand-authored geometry is never doubled up.
	if _authored_occluders().is_empty():
		_stamp_occluder()

## LightOccluder2D children the author placed to mark where this door blocks sight once
## sealed — everything except the one the door stamps for itself (OCCLUDER_NAME).
func _authored_occluders() -> Array[LightOccluder2D]:
	var result: Array[LightOccluder2D] = []
	for child in get_children():
		if child is LightOccluder2D and child.name != OCCLUDER_NAME:
			result.append(child as LightOccluder2D)
	return result

## Show or hide the authored seal occluders. Hidden ones are ignored by
## Room.get_occluder_polygons, so an open door contributes no occlusion even though its
## occluder still sits in the scene for the author to see and edit.
func _set_authored_occluders_active(active: bool) -> void:
	for occ in _authored_occluders():
		occ.visible = active

## Block sight across a sealed doorway. The rooms author occluders only over the walls
## they actually drew, so the opening they left for this door is a hole in the sight
## barrier; when the door seals it with a wall tile, it must plug that hole in the
## occluder field too, or the fog would still pour through the closed doorway.
##
## Used only when the author has not drawn their own seal occluder. The occluder is a
## LightOccluder2D child covering the opening footprint, which Room.get_occluder_polygons
## picks up alongside the authored ones. Points are in door-local space (matching the
## editor preview in _draw); the door's own transform carries them back to room-local when
## the field is built.
func _stamp_occluder() -> void:
	var top_left := Vector2(get_threshold_cell() * TILE_SIZE) - position
	var size := _opening_size()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		top_left,
		top_left + Vector2(size.x, 0.0),
		top_left + size,
		top_left + Vector2(0.0, size.y),
	])
	var occ := LightOccluder2D.new()
	occ.name = OCCLUDER_NAME
	occ.occluder = poly
	add_child(occ)

## Stamp a wall tile across the doorway. Which tile to use is decided by the door's
## orientation — a NORTH/SOUTH door sits on a horizontal wall, an EAST/WEST door on a
## vertical one — rather than by sampling a neighbouring cell. That keeps sealing
## correct in tight rooms and beside corners, where a neighbour is often a corner or
## another door's gap and would supply the wrong tile.
func _stamp_wall(style: DoorStateStyle) -> void:
	var walls := _find_walls_layer()
	if walls == null:
		return
	var horizontal := direction == Direction.NORTH or direction == Direction.SOUTH
	var source_id := style.wall_h_source_id if horizontal else style.wall_v_source_id
	var atlas := style.wall_h_atlas_coords if horizontal else style.wall_v_atlas_coords
	for cell in _door_cells():
		walls.set_cell(cell, source_id, atlas, 0)

## Fix up the floor under a sealed doorway, by direction:
##   NORTH – the tall wall hides the floor, so wipe the door cells.
##   SOUTH – leave the authored door-cell floor as-is, but clear the row one tile
##           further south so no floor pokes out past the sealed wall.
##   EAST/WEST – the floor beside the wall stays visible, so lay the style's floor tile
##           (flipped horizontally for a west wall, which mirrors an east one).
func _seal_floor(style: DoorStateStyle) -> void:
	var floor_layer := _find_floor_layer()
	if floor_layer == null:
		return
	match direction:
		Direction.NORTH:
			for cell in _door_cells():
				floor_layer.erase_cell(cell)
		Direction.SOUTH:
			var outward := direction_vector(Direction.SOUTH)
			for cell in _door_cells():
				floor_layer.erase_cell(cell + outward)
		_:
			var alt := TileSetAtlasSource.TRANSFORM_FLIP_H if direction == Direction.WEST else 0
			for cell in _door_cells():
				floor_layer.set_cell(cell, style.floor_source_id, style.floor_atlas_coords, alt)

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
