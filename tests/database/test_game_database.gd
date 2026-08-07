extends GdUnitTestSuite

## Integration tests for schema initialization and typed enemy queries against
## an isolated SQLite database.

var _database_path: String
var _service: GameDatabaseService

func before_test() -> void:
	_database_path = "user://gdunit_dungeon_%d.db" % Time.get_ticks_msec()
	_remove_test_database()
	_service = GameDatabaseService.new()

func after_test() -> void:
	_service.close()
	_service.free()
	_remove_test_database()

func test_new_database_creates_seeded_schema() -> void:
	assert_bool(_service.initialize(_database_path)).is_true()
	assert_bool(FileAccess.file_exists(_database_path)).is_true()
	var definition := _service.get_enemy_definition(&"goblin")
	assert_that(definition).is_not_null()

func test_goblin_definition_matches_current_gameplay_values() -> void:
	assert_bool(_service.initialize(_database_path)).is_true()
	var definition := _service.get_enemy_definition(&"goblin")
	assert_str(definition.scene.resource_path).is_equal("res://scenes/enemies/enemy.tscn")
	assert_int(definition.max_health).is_equal(100)
	assert_float(definition.movement_speed).is_equal(40.0)
	assert_int(definition.sight_radius).is_equal(75)
	assert_int(definition.knockback_recovery_speed).is_equal(500)
	assert_float(definition.wander_radius).is_equal(100.0)
	assert_float(definition.minimum_wait).is_equal(2.0)
	assert_float(definition.maximum_wait).is_equal(3.0)

func test_initialization_is_idempotent() -> void:
	assert_bool(_service.initialize(_database_path)).is_true()
	assert_bool(_service.initialize(_database_path)).is_true()
	assert_that(_service.get_enemy_definition(&"goblin")).is_not_null()

func test_unknown_archetype_returns_null() -> void:
	assert_bool(_service.initialize(_database_path)).is_true()
	assert_that(_service.get_enemy_definition(&"missing")).is_null()

func test_disabled_archetype_is_not_returned() -> void:
	assert_bool(_service.initialize(_database_path)).is_true()
	var writer := SQLite.new()
	writer.path = _database_path
	assert_bool(writer.open_db()).is_true()
	assert_bool(
		writer.query_with_bindings(
			"UPDATE enemy_archetypes SET enabled = 0 WHERE id = ?;",
			["goblin"]
		)
	).is_true()
	writer.close_db()
	assert_that(_service.get_enemy_definition(&"goblin")).is_null()

func _remove_test_database() -> void:
	var absolute_path := ProjectSettings.globalize_path(_database_path)
	for suffix: String in ["", "-shm", "-wal"]:
		var candidate: String = absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
