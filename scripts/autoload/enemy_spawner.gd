extends Node

## Spawns enemies onto a freshly assembled dungeon. Because this is an autoload its
## _ready() fires only once at engine startup (before any dungeon exists), so spawning is
## driven by MapAssembler calling populate_map() after each build instead — that also
## makes rebuilds respawn correctly.

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy.tscn")
@export var spawn_count: int = 25

var enemy_datas: Dictionary[String, EnemyData]

func _ready() -> void:
	_load_enemy_data("res://scripts/enemies/enemy_types/")

## Fill the current map with enemies at its registered ENEMY spawn points. Deferred so the
## bodies enter a settled scene tree. Safe to call on every build; a no-op if the
## SpawnDirector holds no ENEMY points yet.
func populate_map() -> void:
	call_deferred("_spawn_multiple", "Goblin", roundi(spawn_count * 0.5))
	call_deferred("_spawn_multiple", "Imp", roundi(spawn_count * 0.5))
	call_deferred("_spawn_multiple", "Masked Orc", 2)

func _spawn_one(enemy_name: String) -> bool:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return false
	var sp: SpawnPoint = points[randi() % points.size()]
	var enemy: Enemy = enemy_scene.instantiate()
	enemy.data = enemy_datas[enemy_name]
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = sp.global_position
	return true

func _spawn_multiple(enemy_name: String, count: int) -> void:
	for i in count:
		if _spawn_one(enemy_name):
			pass

## Loads enemies by searching a folder.
func _load_enemy_data(folder: String) -> void:
	var file_names := ResourceLoader.list_directory(folder)
	
	for file_name in file_names:
		if file_name.ends_with(".tres"):
			var full_path := folder.path_join(file_name)
			var data := load(full_path) as EnemyData
			if data:
				enemy_datas.set(data.name, data)
			else:
				push_warning("Failed to load data: " + full_path)
