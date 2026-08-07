extends Node

@export var enemy_archetype_id: StringName = &"goblin"

func _ready() -> void:
	call_deferred("_spawn_multiple", 25)

func _spawn_one(definition: EnemyDefinition) -> void:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return
	var sp: SpawnPoint = points[randi() % points.size()]
	var instance := definition.scene.instantiate()
	if not instance is Enemy:
		push_error("Enemy archetype '%s' did not instantiate an Enemy" % definition.id)
		instance.free()
		return
	var enemy := instance as Enemy
	enemy.apply_definition(definition)
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = sp.global_position

func _spawn_multiple(count: int) -> void:
	if not GameDatabase.is_available():
		push_error("EnemySpawner: SQLite database is unavailable; no enemies were spawned")
		return
	var definition := GameDatabase.get_enemy_definition(enemy_archetype_id)
	if definition == null:
		push_error("EnemySpawner: enabled archetype '%s' was not found" % enemy_archetype_id)
		return
	for _i in count:
		_spawn_one(definition)
