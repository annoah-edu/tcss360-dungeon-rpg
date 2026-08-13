extends Node

## Spawns enemies onto a freshly assembled dungeon. Because this is an autoload its
## _ready() fires only once at engine startup (before any dungeon exists), so spawning is
## driven by MapAssembler calling populate_map() after each build instead — that also
## makes rebuilds respawn correctly.

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy.tscn")
@export var spawn_count: int = 25

## Fill the current map with enemies at its registered ENEMY spawn points. Deferred so the
## bodies enter a settled scene tree. Safe to call on every build; a no-op if the
## SpawnDirector holds no ENEMY points yet.
func populate_map() -> void:
	call_deferred("_spawn_multiple", spawn_count)

func _spawn_one() -> bool:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return false
	var sp: SpawnPoint = points[randi() % points.size()]
	var enemy: Enemy = enemy_scene.instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = sp.global_position
	return true

func _spawn_multiple(count: int) -> void:
	var spawned := 0
	for i in count:
		if _spawn_one():
			spawned += 1
	print("[EnemySpawner] spawned %d/%d enemies" % [spawned, count])
