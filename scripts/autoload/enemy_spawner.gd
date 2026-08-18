extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy.tscn")
@export var spawn_count: int = 15

const WALL_COLLISION_MASK: int = 1  # Layer 1, per your Walls setup

var enemy_datas: Dictionary[String, EnemyData]

func _ready() -> void:
	_load_enemy_data("res://scripts/enemies/enemy_types/")

## Fill the current map with enemies at its registered ENEMY spawn points.
func populate_map() -> void:
	call_deferred("_spawn_multiple", "Goblin", roundi(spawn_count * 0.5))
	call_deferred("_spawn_multiple", "Imp", roundi(spawn_count * 0.5))
	call_deferred("_spawn_multiple", "Masked Orc", 2)
	call_deferred("_spawn_multiple", "Zombie", 2)
	call_deferred("_spawn_multiple", "Necromancer", 1)

## Spawns a single enemy near a world position instead of a registered ENEMY spawn point
func spawn_at_position(enemy_name: String, origin: Vector2, spawn_radius: float = 0.0) -> Enemy:
	var enemy := _create_enemy(enemy_name)
	if enemy == null:
		return null
	
	var spawn_position := origin
	if spawn_radius > 0.0:
		spawn_position = _resolve_offset_position(origin, spawn_radius)
	
	enemy.global_position = spawn_position
	get_tree().current_scene.add_child(enemy)
	enemy.found_player = true
	
	return enemy

func _spawn_one(enemy_name: String) -> bool:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return false
	var sp: SpawnPoint = points[randi() % points.size()]
	
	var enemy := _create_enemy(enemy_name)
	if enemy == null:
		return false
	
	enemy.global_position = sp.global_position
	get_tree().current_scene.add_child(enemy)
	return true

func _spawn_multiple(enemy_name: String, count: int) -> void:
	for i in count:
		if _spawn_one(enemy_name):
			pass

## Instantiates and configures an enemy by name, without placing or parenting it yet.
## Shared by every spawn path so there's one place that knows how to build an enemy.
func _create_enemy(enemy_name: String) -> Enemy:
	if not enemy_datas.has(enemy_name):
		push_warning("Unknown enemy type: " + enemy_name)
		return null
	var enemy: Enemy = enemy_scene.instantiate()
	enemy.set_script(enemy_datas[enemy_name].enemy_behavior)
	enemy.data = enemy_datas[enemy_name]
	enemy.spawner = self
	return enemy


## Picks a random point within spawn_radius of origin, then raycasts from origin toward
## it against the Walls layer. If the ray hits a wall first, the point is pulled back to
## just short of the wall surface instead of the full random offset.
func _resolve_offset_position(origin: Vector2, spawn_radius: float) -> Vector2:
	var angle := randf_range(0.0, TAU)
	var distance := randf_range(0.0, spawn_radius)
	var target := origin + Vector2.from_angle(angle) * distance
	
	var space_state: PhysicsDirectSpaceState2D = get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(origin, target)
	query.collision_mask = WALL_COLLISION_MASK
	var result := space_state.intersect_ray(query)
	
	if result:
		return result.position + result.normal * 4.0  # small pull-back so it doesn't spawn embedded in the wall
	return target

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
