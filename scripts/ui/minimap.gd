class_name Minimap
extends CanvasLayer

## A small square minimap in the bottom-right corner. It draws the dungeon as thin
## purple outlines and chests as yellow boxes, but only for rooms the player has
## entered — walking into a room reveals that room and the corridors that touch it.
##
## The view is not centred on the player: it holds still on the *current room's*
## centre, and slides smoothly to the next room's centre when the player crosses into
## it. Geometry is drawn at a fixed downscale (see `world_scale`) so a whole room fits.
##
## To match the game's pixel density, the map is not drawn straight to the screen.
## It renders into a low-resolution SubViewport (one texel per minimap "pixel"), then a
## TextureRect blows that up by the integer `pixel_size` with nearest-neighbour
## filtering. Every line, box and the border therefore land on one coarse pixel grid the
## same size as an in-game pixel, rather than as hairline 1px vectors.
##
## Everything is fed in once by MapAssembler after a build: rooms and connectors carry
## pre-traced outline segments (world pixels), and the assembler resolves which rooms
## each connector joins so a revealed room can light up its neighbours' corridors.

const TILE_SIZE := Room.TILE_SIZE

const WALL_COLOR := Color("a857f2ff")
const CHEST_COLOR := Color(1.0, 0.84, 0.12)
const BG_COLOR := Color(0.04, 0.04, 0.07, 0.72)
const BORDER_COLOR := Color(0.66, 0.34, 0.95, 0.6)

## Screen pixels per minimap pixel. Set to the game camera's zoom (5) so the minimap's
## pixels are the same size as the game's, giving one shared pixel density.
var pixel_size: int = 5
## Target square side in screen pixels. Rounded to a whole number of minimap pixels, so
## the actual on-screen side is `_logical * pixel_size`.
var view_size: float = 200.0
## Gap from the screen's bottom-right corner, in screen pixels.
var margin: float = 12.0
## Minimap pixels per world pixel. Below 1 so a whole room shrinks to fit; kept fixed
## (rather than fit-to-room) so the density never jumps between rooms of different size.
var world_scale: float = 0.05
## How quickly the view slides to a newly entered room's centre, per second.
var pan_speed: float = 6.0

## One entry per placed room: its world-tile footprint, its centre in world pixels, and
## the outline segments (world pixels, endpoint pairs) tracing its floor.
var _rooms: Array[Dictionary] = []
## One entry per corridor: outline segments (world pixels) plus the indices of the rooms
## it connects, so entering either room reveals it.
var _connectors: Array[Dictionary] = []
## Chest world positions, revealed with the room they sit in.
var _chests: Array[Dictionary] = []

var _player: Node2D
## Low-res render target; its texels are the minimap's pixels before upscaling.
var _viewport: SubViewport
## Drawing surface inside the viewport, sized in minimap pixels.
var _canvas: Control
## Screen-space display that upscales the viewport by `pixel_size` with nearest filtering.
var _display: TextureRect
## Side of the render target, in minimap pixels.
var _logical: int = 40

var _revealed_rooms := {}
var _revealed_connectors := {}
var _current_room: int = -1
## Smoothly-tracked view centre in world pixels; held until the first room reveals.
var _display_center := Vector2.ZERO
var _target_center := Vector2.ZERO
var _has_center := false

func _ready() -> void:
	# Above the world and the fog (fog is layer 1), so it always reads on top.
	layer = 3
	_logical = maxi(1, int(round(view_size / float(maxi(pixel_size, 1)))))

	_viewport = SubViewport.new()
	_viewport.name = "MinimapViewport"
	_viewport.size = Vector2i(_logical, _logical)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_canvas = Control.new()
	_canvas.name = "MinimapCanvas"
	_canvas.size = Vector2(_logical, _logical)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_canvas_draw)
	_viewport.add_child(_canvas)

	_display = TextureRect.new()
	_display.name = "MinimapDisplay"
	_display.texture = _viewport.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	# Nearest-neighbour upscale keeps the fat pixels crisp instead of blurring them.
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)

	_layout()
	get_viewport().size_changed.connect(_layout)

## Feed the minimap a freshly built dungeon. `rooms` and `connectors` are the feature
## dictionaries assembled by MapAssembler; `chests` are world positions; `player` is the
## node whose position selects the current room.
func setup(rooms: Array[Dictionary], connectors: Array[Dictionary], chests: Array[Dictionary], player: Node2D) -> void:
	_rooms = rooms
	_connectors = connectors
	_chests = chests
	_player = player
	_revealed_rooms.clear()
	_revealed_connectors.clear()
	_current_room = -1
	_has_center = false
	if _canvas != null:
		_canvas.queue_redraw()

func _layout() -> void:
	if _display == null:
		return
	var side := float(_logical * pixel_size)
	_display.size = Vector2(side, side)
	var vp := get_viewport().get_visible_rect().size
	_display.position = vp - Vector2(side + margin, side + margin)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_update_current_room()
	if _has_center:
		# Exponential ease toward the target centre; framerate-independent.
		var t: float = 1.0 - pow(0.001, delta * pan_speed / 6.0)
		_display_center = _display_center.lerp(_target_center, clampf(t, 0.0, 1.0))
	if _canvas != null:
		_canvas.queue_redraw()

## Pick the room the player currently stands in and, on a change, reveal it plus the
## corridors that touch it and any chests inside it. Standing in a corridor (no room
## contains the player) keeps the last room current, so the view does not drift away.
func _update_current_room() -> void:
	var tile := Vector2i(floori(_player.global_position.x / TILE_SIZE), floori(_player.global_position.y / TILE_SIZE))
	var found := -1
	for i in _rooms.size():
		var bounds: Rect2i = _rooms[i]["bounds"]
		if bounds.has_point(tile):
			found = i
			break
	if found == -1 or found == _current_room:
		return
	_current_room = found
	_reveal_room(found)

func _reveal_room(index: int) -> void:
	_revealed_rooms[index] = true
	for ci in _connectors.size():
		var adj: Array = _connectors[ci]["rooms"]
		if index in adj:
			_revealed_connectors[ci] = true
	for chest_i in _chests.size():
		var bounds: Rect2i = _rooms[index]["bounds"]
		if bounds.has_point(_chests[chest_i]["tile"]):
			_chests[chest_i]["revealed"] = true

	_target_center = _rooms[index]["center"]
	if not _has_center:
		_display_center = _target_center
		_has_center = true

## Draw the minimap in low-res minimap pixels; the display TextureRect blows this up by
## `pixel_size` so it lands on the game's pixel grid.
func _on_canvas_draw() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), BG_COLOR)
	if _has_center:
		for ci in _connectors.size():
			if _revealed_connectors.has(ci):
				_draw_segments(_connectors[ci]["edges"])
		for ri in _rooms.size():
			if _revealed_rooms.has(ri):
				_draw_segments(_rooms[ri]["edges"])
		for chest in _chests:
			if chest.get("revealed", false):
				_draw_chest(chest["pos"])
	# Border last, on top of everything, so clipped geometry ends at a clean frame. Drawn
	# as four filled 1px bars rather than an unfilled rect: an unfilled rect centres its
	# stroke on the edge, so the top and left halves fall outside the viewport and vanish.
	var s := _canvas.size
	_canvas.draw_rect(Rect2(0.0, 0.0, s.x, 1.0), BORDER_COLOR)
	_canvas.draw_rect(Rect2(0.0, s.y - 1.0, s.x, 1.0), BORDER_COLOR)
	_canvas.draw_rect(Rect2(0.0, 0.0, 1.0, s.y), BORDER_COLOR)
	_canvas.draw_rect(Rect2(s.x - 1.0, 0.0, 1.0, s.y), BORDER_COLOR)

## Draw a run of world-space line segments (endpoint pairs) into the minimap. Lines are
## one minimap pixel wide; the upscale turns that into a `pixel_size`-thick game pixel.
func _draw_segments(edges: PackedVector2Array) -> void:
	var count := edges.size()
	var i := 0
	while i + 1 < count:
		_canvas.draw_line(_to_view(edges[i]), _to_view(edges[i + 1]), WALL_COLOR, 1.0, false)
		i += 2

func _draw_chest(world_pos: Vector2) -> void:
	var box := 1.0
	var c := _to_view(world_pos)
	_canvas.draw_rect(Rect2(c - Vector2(box, box), Vector2(box, box) * 2.0), CHEST_COLOR)

## World pixels -> minimap-pixel coordinates, about the smoothly-tracked centre.
func _to_view(world_pos: Vector2) -> Vector2:
	return (world_pos - _display_center) * world_scale + _canvas.size * 0.5

## Trace the outline of a set of world-tile cells into world-pixel line segments: every
## cell edge whose neighbour is outside the set becomes one segment. On a room's floor
## cells this yields the room's silhouette; on a corridor's floor cells, a thin passage.
static func trace_outline(cells: Array[Vector2i]) -> PackedVector2Array:
	var present := {}
	for c in cells:
		present[c] = true
	var segments := PackedVector2Array()
	var f := float(TILE_SIZE)
	for c in cells:
		var x := float(c.x) * f
		var y := float(c.y) * f
		if not present.has(c + Vector2i(0, -1)):
			segments.append(Vector2(x, y)); segments.append(Vector2(x + f, y))
		if not present.has(c + Vector2i(0, 1)):
			segments.append(Vector2(x, y + f)); segments.append(Vector2(x + f, y + f))
		if not present.has(c + Vector2i(-1, 0)):
			segments.append(Vector2(x, y)); segments.append(Vector2(x, y + f))
		if not present.has(c + Vector2i(1, 0)):
			segments.append(Vector2(x + f, y)); segments.append(Vector2(x + f, y + f))
	return segments
