class_name RayDebugOverlay
extends Node2D

## Draws the rays a RayProbe marched, so a shadow that looks wrong can be traced back
## to the geometry that caused it.
##
## For each blocked ray: the segment actually travelled, the segment it would have
## covered unobstructed, the origin, the first solid pixel, the cell that pixel belongs
## to, and the hit distance as text.
##
## This is a diagnostic, not part of the game — it sits in world space above the rooms
## and is off unless `enabled` is set.

## Colours chosen to stay legible over the dungeon's browns and the purple backdrop.
const CLEAR_COLOR := Color(0.35, 0.95, 0.45, 0.55)
const BLOCKED_COLOR := Color(1.0, 0.35, 0.25, 0.9)
const SHADOWED_COLOR := Color(1.0, 0.35, 0.25, 0.22)
const ORIGIN_COLOR := Color(0.4, 0.85, 1.0)
const CELL_COLOR := Color(1.0, 0.85, 0.2, 0.85)

@export var enabled: bool = false:
	set(value):
		enabled = value
		visible = value
		queue_redraw()
## Draw rays that reached their target as well as those that were stopped.
@export var show_clear_rays: bool = false:
	set(value):
		show_clear_rays = value
		queue_redraw()
## Print the hit distance and cell beside each hit.
@export var show_labels: bool = true:
	set(value):
		show_labels = value
		queue_redraw()
## Tile size, for outlining the cell a ray struck.
@export var tile_size: int = 16

var _hits: Array = []
var _font: Font

func _ready() -> void:
	# Above the rooms so the rays are not buried under tiles, and unaffected by the fog
	# (which is on its own CanvasLayer).
	z_index = 200
	y_sort_enabled = false
	visible = enabled
	_font = ThemeDB.fallback_font

## Replace the drawn set with these RayProbe.Hit results.
func show_hits(hits: Array) -> void:
	_hits = hits
	queue_redraw()

func clear_hits() -> void:
	_hits.clear()
	queue_redraw()

func _draw() -> void:
	if not enabled or _hits.is_empty():
		return
	for hit in _hits:
		if hit.blocked:
			_draw_blocked(hit)
		elif show_clear_rays and not hit.out_of_range:
			# Rays that merely ran out of radius are not findings, so they stay hidden
			# even when clear rays are shown — otherwise the rim drowns out the
			# occlusions worth looking at.
			_draw_clear(hit)

func _draw_clear(hit) -> void:
	draw_line(hit.origin, hit.target, CLEAR_COLOR, 1.0)
	draw_circle(hit.target, 1.5, CLEAR_COLOR)

func _draw_blocked(hit) -> void:
	# The part of the ray that actually travelled, then the shadowed remainder it never
	# reached — seeing both makes it obvious whether the ray stopped early.
	draw_line(hit.origin, hit.hit_position, BLOCKED_COLOR, 1.0)
	draw_line(hit.hit_position, hit.target, SHADOWED_COLOR, 1.0)

	# The cell that stopped it, outlined, plus the exact pixel.
	var cell_pos := Vector2(hit.hit_cell * tile_size)
	draw_rect(Rect2(cell_pos, Vector2(tile_size, tile_size)), CELL_COLOR, false, 1.0)
	draw_rect(Rect2(hit.hit_position.floor(), Vector2.ONE), BLOCKED_COLOR, true)
	draw_circle(hit.hit_position, 2.0, BLOCKED_COLOR)

	# Origin marker, drawn last so it stays on top of the rays leaving it.
	draw_circle(hit.origin, 2.5, ORIGIN_COLOR)

	if show_labels and _font != null:
		var label := "%.1f px  %s+%s" % [hit.hit_distance, hit.hit_cell, hit.hit_local]
		# Nudge the text off the hit so it does not sit under the marker.
		draw_string(_font, hit.hit_position + Vector2(4, -3), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 5, CELL_COLOR)
