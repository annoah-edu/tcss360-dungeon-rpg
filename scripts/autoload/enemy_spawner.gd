extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy.tscn")
@export var spawn_count: int = 15

const WALL_COLLISION_MASK: int = 1  # Layer 1, per your Walls setup

var enemy_datas: Dictionary

func _ready() -> void:
	if not GameDatabase.is_available():
		push_error("EnemySpawner: SQLite database is unavailable")
		return
	enemy_datas = GameDatabase.get_enabled_enemy_data()

## Fill the current map with enemies at its registered ENEMY spawn points.
func populate_map() -> void:
	for rule in GameDatabase.get_enemy_spawn_rules():
		var count := (
			roundi(spawn_count * float(rule["spawn_fraction"]))
			+ int(rule["fixed_count"])
		)
		call_deferred("_spawn_multiple", rule["enemy_id"], count)

## Spawns a single enemy near a world position instead of a registered ENEMY spawn point
func spawn_at_position(enemy_id: StringName, origin: Vector2, spawn_radius: float = 0.0) -> Enemy:
	var enemy := _create_enemy(enemy_id)
	if enemy == null:
		return null
	
	var spawn_position := origin
	if spawn_radius > 0.0:
		spawn_position = _resolve_offset_position(origin, spawn_radius)
	
	enemy.global_position = spawn_position
	get_tree().current_scene.add_child(enemy)
	enemy.found_player = true
	
	return enemy

## Re-create a saved enemy at an exact position with its saved health and aggro state.
## Used by MapAssembler when restoring a save instead of the random populate_map() pass.
func spawn_saved(enemy_name: String, pos: Vector2, health: int, found_player: bool) -> Enemy:
	var enemy := _create_enemy(enemy_name)
	if enemy == null:
		return null
	enemy.global_position = pos
	enemy.found_player = found_player
	get_tree().current_scene.add_child(enemy)
	# _ready() sets health to max after _create_enemy; apply the saved value once the node
	# is in the tree so its healthbar (an @onready child) exists to update.
	enemy.health = health
	if enemy.healthbar != null and health < enemy.max_health:
		enemy.healthbar.visible = true
		enemy.healthbar.max_value = enemy.max_health
		enemy.healthbar.value = health
	return enemy


func _spawn_one(enemy_id: StringName) -> bool:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return false
	var sp: SpawnPoint = points[randi() % points.size()]
	
	var enemy := _create_enemy(enemy_id)
	if enemy == null:
		return false
	
	enemy.global_position = sp.global_position
	get_tree().current_scene.add_child(enemy)
	return true

func _spawn_multiple(enemy_id: StringName, count: int) -> void:
	for i in count:
		if _spawn_one(enemy_id):
			pass

## Instantiates and configures an enemy by name, without placing or parenting it yet.
## Shared by every spawn path so there's one place that knows how to build an enemy.
func _create_enemy(enemy_id: StringName) -> Enemy:
	if not enemy_datas.has(enemy_id):
		push_warning("Unknown enemy type: %s" % enemy_id)
		return null
	var enemy: Enemy = enemy_scene.instantiate()
	var data := enemy_datas[enemy_id] as EnemyData
	enemy.set_script(data.enemy_behavior)
	enemy.data = data
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
