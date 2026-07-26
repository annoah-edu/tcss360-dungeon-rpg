class_name DoorStateLibrary
extends Resource

## Data-driven registry mapping a state key (StringName) to a DoorStateStyle.
## Extensible by data alone — add a `boss` / `secret` / `locked_gold` entry and no
## code changes. A Door resolves its presentation by taking the highest-priority
## style among the states it currently holds.

@export var styles: Dictionary = {}

func get_style(key: StringName) -> DoorStateStyle:
	return styles.get(key)

## Highest-priority style among `states`, or null (treated as open / no-op).
func resolve(states: Array[StringName]) -> DoorStateStyle:
	var best: DoorStateStyle = null
	for s in states:
		var style: DoorStateStyle = styles.get(s)
		if style != null and (best == null or style.priority > best.priority):
			best = style
	return best

## Built-in defaults so doors work with zero setup. Assign a custom library on a
## Door (or save one as a .tres) to override.
##
## Static states (open / sealed) are tile-based so they blend with the walls;
## interactive states (closed / locked / boss) are node entities.
static func create_default() -> DoorStateLibrary:
	var lib := DoorStateLibrary.new()
	lib.styles = {
		&"open": _open(0),
		&"sealed": _wall(10),
		&"closed": _entity(30, Color(0.5, 0.35, 0.2)),
		&"locked": _entity(40, Color(0.66, 0.52, 0.2)),
		&"boss": _entity(50, Color(0.6, 0.12, 0.6)),
	}
	return lib

static func _open(priority: int) -> DoorStateStyle:
	var s := DoorStateStyle.new()
	s.presentation = DoorStateStyle.Presentation.OPEN
	s.priority = priority
	s.blocks = false
	return s

static func _wall(priority: int) -> DoorStateStyle:
	var s := DoorStateStyle.new()
	s.presentation = DoorStateStyle.Presentation.WALL_TILE
	s.priority = priority
	s.blocks = true
	return s

static func _entity(priority: int, color: Color) -> DoorStateStyle:
	var s := DoorStateStyle.new()
	s.presentation = DoorStateStyle.Presentation.ENTITY
	s.priority = priority
	s.blocks = true
	s.color = color
	return s
