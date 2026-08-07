class_name GameDatabaseService
extends Node

## Owns the project's SQLite connection and converts database rows into typed
## game data. No other gameplay system should issue SQL directly.

const DEFAULT_DATABASE_PATH := "user://dungeon.db"
const CURRENT_SCHEMA_VERSION := 1

const CREATE_ENEMY_ARCHETYPES := """
CREATE TABLE enemy_archetypes (
	id TEXT PRIMARY KEY,
	scene_path TEXT NOT NULL,
	max_health INTEGER NOT NULL CHECK (max_health > 0),
	movement_speed REAL NOT NULL CHECK (movement_speed >= 0),
	sight_radius INTEGER NOT NULL CHECK (sight_radius >= 0),
	knockback_recovery_speed INTEGER NOT NULL CHECK (knockback_recovery_speed >= 0),
	wander_radius REAL NOT NULL CHECK (wander_radius >= 0),
	minimum_wait REAL NOT NULL CHECK (minimum_wait >= 0),
	maximum_wait REAL NOT NULL CHECK (maximum_wait >= minimum_wait),
	enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1))
);
"""

const INSERT_GOBLIN := """
INSERT INTO enemy_archetypes (
	id, scene_path, max_health, movement_speed, sight_radius,
	knockback_recovery_speed, wander_radius, minimum_wait, maximum_wait, enabled
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
"""

const SELECT_ENEMY := """
SELECT id, scene_path, max_health, movement_speed, sight_radius,
	knockback_recovery_speed, wander_radius, minimum_wait, maximum_wait
FROM enemy_archetypes
WHERE id = ? AND enabled = 1
LIMIT 1;
"""

var _database: SQLite
var _available := false
var _last_error := ""

func _ready() -> void:
	initialize()

## Open a database and apply any missing schema migrations. Tests may supply an
## isolated user:// path instead of touching the normal player database.
func initialize(database_path: String = DEFAULT_DATABASE_PATH) -> bool:
	close()
	_database = SQLite.new()
	_database.path = database_path
	_database.foreign_keys = true
	if not _database.open_db():
		return _fail("Could not open %s: %s" % [database_path, _database.error_message])
	if not _migrate():
		close()
		return false
	_available = true
	_last_error = ""
	return true

func close() -> void:
	if _database != null:
		_database.close_db()
	_database = null
	_available = false

func is_available() -> bool:
	return _available

func get_last_error() -> String:
	return _last_error

## Return an enabled enemy definition, or null when the id is absent, disabled,
## invalid, or the database is unavailable.
func get_enemy_definition(id: StringName) -> EnemyDefinition:
	if not _available:
		push_error("GameDatabase: query attempted while the database is unavailable")
		return null
	if not _database.query_with_bindings(SELECT_ENEMY, [String(id)]):
		_fail("Enemy query failed: %s" % _database.error_message)
		return null
	if _database.query_result.is_empty():
		return null
	return _definition_from_row(_database.query_result[0])

func _migrate() -> bool:
	var version := _schema_version()
	if version < 0:
		return false
	if version > CURRENT_SCHEMA_VERSION:
		return _fail(
			"Database schema %d is newer than supported schema %d"
			% [version, CURRENT_SCHEMA_VERSION]
		)
	if version == 0:
		return _migrate_to_version_one()
	return true

func _schema_version() -> int:
	if not _database.query("PRAGMA user_version;"):
		_fail("Could not read schema version: %s" % _database.error_message)
		return -1
	if _database.query_result.is_empty():
		_fail("SQLite returned no schema version")
		return -1
	return int(_database.query_result[0].get("user_version", -1))

func _migrate_to_version_one() -> bool:
	if not _database.query("BEGIN TRANSACTION;"):
		return _fail("Could not begin database migration: %s" % _database.error_message)
	if not _database.query(CREATE_ENEMY_ARCHETYPES):
		return _rollback("Could not create enemy_archetypes: %s" % _database.error_message)
	var goblin_values := [
		"goblin",
		"res://scenes/enemies/enemy.tscn",
		100,
		40.0,
		75,
		500,
		100.0,
		2.0,
		3.0,
		1,
	]
	if not _database.query_with_bindings(INSERT_GOBLIN, goblin_values):
		return _rollback("Could not seed goblin data: %s" % _database.error_message)
	if not _database.query("PRAGMA user_version = 1;"):
		return _rollback("Could not update schema version: %s" % _database.error_message)
	if not _database.query("COMMIT;"):
		return _rollback("Could not commit database migration: %s" % _database.error_message)
	return true

func _definition_from_row(row: Dictionary) -> EnemyDefinition:
	var scene_path := str(row.get("scene_path", ""))
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_fail("Enemy scene does not exist: %s" % scene_path)
		return null
	var definition := EnemyDefinition.new()
	definition.id = StringName(row.get("id", ""))
	definition.scene = load(scene_path) as PackedScene
	definition.max_health = int(row.get("max_health", 0))
	definition.movement_speed = float(row.get("movement_speed", -1.0))
	definition.sight_radius = int(row.get("sight_radius", -1))
	definition.knockback_recovery_speed = int(row.get("knockback_recovery_speed", -1))
	definition.wander_radius = float(row.get("wander_radius", -1.0))
	definition.minimum_wait = float(row.get("minimum_wait", -1.0))
	definition.maximum_wait = float(row.get("maximum_wait", -1.0))
	if not definition.is_valid():
		_fail("Enemy archetype '%s' contains invalid data" % definition.id)
		return null
	return definition

func _rollback(message: String) -> bool:
	_database.query("ROLLBACK;")
	return _fail(message)

func _fail(message: String) -> bool:
	_last_error = message
	push_error("GameDatabase: %s" % message)
	return false

func _exit_tree() -> void:
	close()
