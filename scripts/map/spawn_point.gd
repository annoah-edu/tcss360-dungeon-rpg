@tool
class_name SpawnPoint
extends Marker2D

## A declarative marker inside a Room saying "something of this category may spawn
## here". It holds no spawning logic itself — rooms register their spawn points
## with the [SpawnDirector] autoload, and future systems (enemies, loot, NPCs)
## query the director by category and instantiate the real content.

enum Category { PLAYER_START, ENEMY, NPC, LOOT, TREASURE, BOSS, PROP }

const CATEGORY_COLORS := {
	Category.PLAYER_START: Color(0.2, 0.9, 0.3),
	Category.ENEMY: Color(0.9, 0.2, 0.2),
	Category.NPC: Color(0.9, 0.8, 0.2),
	Category.LOOT: Color(0.9, 0.6, 0.1),
	Category.TREASURE: Color(0.8, 0.7, 0.2),
	Category.BOSS: Color(0.7, 0.1, 0.7),
	Category.PROP: Color(0.5, 0.5, 0.5),
}

@export var category: Category = Category.ENEMY:
	set(value):
		category = value
		queue_redraw()

## Free-form labels a spawn system can filter on (e.g. &"goblin", &"rare").
@export var tags: Array[StringName] = []

## Probability [0,1] that this point produces anything on a given generation.
@export_range(0.0, 1.0) var spawn_chance: float = 1.0

## Upper bound on how many entities this point may produce.
@export var max_count: int = 1

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col: Color = CATEGORY_COLORS.get(category, Color.WHITE)
	draw_circle(Vector2.ZERO, 3.0, col)
	draw_arc(Vector2.ZERO, 4.0, 0.0, TAU, 16, col, 1.0)
