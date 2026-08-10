extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy.tscn")

func _ready() -> void:
	call_deferred("_spawn_multiple", 25)

func _spawn_one() -> void:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return
	var sp: SpawnPoint = points[randi() % points.size()]
	var enemy: Enemy = enemy_scene.instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = sp.global_position

func _spawn_multiple(count: int) -> void:
	for i in count:
		_spawn_one()
