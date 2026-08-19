class_name GameDatabaseService
extends Node

## SQLite boundary for persistent statistics and data-driven gameplay catalogs.
## Gameplay systems consume typed resources and dictionaries; only this service
## knows the schema or issues SQL.

const DEFAULT_DATABASE_PATH := "user://dungeon.db"
const CURRENT_SCHEMA_VERSION := 2

const STATISTIC_DEFINITIONS := [
	["distance_feet", "Distance traveled", "distance", 0],
	["rooms_explored", "Rooms explored", "count", 1],
	["chests_opened", "Chests opened", "count", 2],
	["enemies_killed", "Enemies killed", "count", 3],
	["damage_done", "Damage done", "count", 4],
	["time_seconds", "Time in game", "time", 5],
]

const ENEMY_ARCHETYPES := [
	["goblin", "Goblin", "res://scripts/enemies/enemy_types/goblin.tres", 100, 40.0, 35, 1.0, 75, 500, 300.0, 2.0, 3.0],
	["imp", "Imp", "res://scripts/enemies/enemy_types/imp.tres", 150, 75.0, 35, 1.0, 95, 550, 300.0, 2.0, 3.0],
	["masked_orc", "Masked Orc", "res://scripts/enemies/enemy_types/masked_orc.tres", 250, 50.0, 25, 0.5, 75, 500, 300.0, 2.0, 3.0],
	["zombie", "Zombie", "res://scripts/enemies/enemy_types/zombie.tres", 200, 45.0, 34, 1.0, 75, 500, 300.0, 2.0, 3.0],
	["skeleton", "Skeleton", "res://scripts/enemies/enemy_types/skeleton.tres", 125, 50.0, 35, 1.0, 75, 500, 300.0, 2.0, 3.0],
	["necromancer", "Necromancer", "res://scripts/enemies/enemy_types/necromancer.tres", 225, 20.0, 25, 1.0, 90, 400, 300.0, 2.0, 3.0],
]

const ENEMY_SPAWN_RULES := [
	["goblin", 0.5, 0, 0],
	["imp", 0.5, 0, 1],
	["masked_orc", 0.0, 2, 2],
	["zombie", 0.0, 2, 3],
	["necromancer", 0.0, 1, 4],
]

const DEFAULT_WEAPON_POOL := [
	["anime_sword", "res://resources/items/weapons/anime_sword.tres"],
	["baton_with_spikes", "res://resources/items/weapons/baton_with_spikes.tres"],
	["big_hammer", "res://resources/items/weapons/big_hammer.tres"],
	["bow", "res://resources/items/weapons/bow.tres"],
	["cleaver", "res://resources/items/weapons/cleaver.tres"],
	["double_axe", "res://resources/items/weapons/double_axe.tres"],
	["duel_sword", "res://resources/items/weapons/duel_sword.tres"],
	["golden_sword", "res://resources/items/weapons/golden_sword.tres"],
	["green_magic_staff", "res://resources/items/weapons/green_magic_staff.tres"],
	["hammer", "res://resources/items/weapons/hammer.tres"],
	["katana", "res://resources/items/weapons/katana.tres"],
	["knife", "res://resources/items/weapons/knife.tres"],
	["knight_sword", "res://resources/items/weapons/knight_sword.tres"],
	["lavish_sword", "res://resources/items/weapons/lavish_sword.tres"],
	["mace", "res://resources/items/weapons/mace.tres"],
	["machete", "res://resources/items/weapons/machete.tres"],
	["red_gem_sword", "res://resources/items/weapons/red_gem_sword.tres"],
	["red_magic_staff", "res://resources/items/weapons/red_magic_staff.tres"],
	["regular_sword", "res://resources/items/weapons/regular_sword.tres"],
	["rusty_sword", "res://resources/items/weapons/rusty_sword.tres"],
	["saw_sword", "res://resources/items/weapons/saw_sword.tres"],
	["spear", "res://resources/items/weapons/spear.tres"],
	["throwing_axe", "res://resources/items/weapons/throwing_axe.tres"],
	["waraxe", "res://resources/items/weapons/waraxe.tres"],
	["weapon_axe", "res://resources/items/weapons/weapon_axe.tres"],
]

const CREATE_SCHEMA := [
	"""CREATE TABLE statistic_definitions (
		stat_key TEXT PRIMARY KEY,
		label TEXT NOT NULL,
		format_kind TEXT NOT NULL CHECK (format_kind IN ('count', 'distance', 'time')),
		display_order INTEGER NOT NULL UNIQUE,
		enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1))
	);""",
	"""CREATE TABLE lifetime_statistics (
		stat_key TEXT PRIMARY KEY REFERENCES statistic_definitions(stat_key),
		value REAL NOT NULL DEFAULT 0 CHECK (value >= 0)
	);""",
	"""CREATE TABLE enemy_archetypes (
		id TEXT PRIMARY KEY,
		display_name TEXT NOT NULL,
		resource_path TEXT NOT NULL UNIQUE,
		max_health INTEGER NOT NULL CHECK (max_health > 0),
		movement_speed REAL NOT NULL CHECK (movement_speed >= 0),
		attack_damage INTEGER NOT NULL CHECK (attack_damage >= 0),
		attack_interval REAL NOT NULL CHECK (attack_interval > 0),
		sight_radius INTEGER NOT NULL CHECK (sight_radius >= 0),
		knockback_recovery_speed INTEGER NOT NULL CHECK (knockback_recovery_speed >= 0),
		wander_radius REAL NOT NULL CHECK (wander_radius >= 0),
		minimum_wait REAL NOT NULL CHECK (minimum_wait >= 0),
		maximum_wait REAL NOT NULL CHECK (maximum_wait >= minimum_wait),
		enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1))
	);""",
	"""CREATE TABLE enemy_spawn_rules (
		enemy_id TEXT PRIMARY KEY REFERENCES enemy_archetypes(id),
		spawn_fraction REAL NOT NULL DEFAULT 0 CHECK (spawn_fraction >= 0),
		fixed_count INTEGER NOT NULL DEFAULT 0 CHECK (fixed_count >= 0),
		display_order INTEGER NOT NULL UNIQUE,
		enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1))
	);""",
	"""CREATE TABLE weapon_loot_pool_entries (
		pool_id TEXT NOT NULL,
		weapon_id TEXT NOT NULL,
		resource_path TEXT NOT NULL,
		weight REAL NOT NULL DEFAULT 1 CHECK (weight > 0),
		display_order INTEGER NOT NULL,
		enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
		PRIMARY KEY (pool_id, weapon_id),
		UNIQUE (pool_id, display_order)
	);""",
	"""CREATE TABLE database_metadata (
		setting_key TEXT PRIMARY KEY,
		setting_value TEXT NOT NULL
	);""",
]

var _database: SQLite
var _available := false
var _last_error := ""


func _ready() -> void:
	initialize()


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


func get_statistic_definitions() -> Array[Dictionary]:
	if not _query("""SELECT stat_key, label, format_kind, display_order
		FROM statistic_definitions WHERE enabled = 1 ORDER BY display_order;"""):
		return []
	var definitions: Array[Dictionary] = []
	for row in _database.query_result:
		definitions.append({
			"key": str(row["stat_key"]),
			"label": str(row["label"]),
			"kind": str(row["format_kind"]),
		})
	return definitions


func get_lifetime_statistics() -> Dictionary:
	if not _query("SELECT stat_key, value FROM lifetime_statistics;"):
		return {}
	var totals := {}
	for row in _database.query_result:
		totals[str(row["stat_key"])] = float(row["value"])
	return totals


func save_lifetime_statistics(totals: Dictionary) -> bool:
	if not _begin_transaction():
		return false
	for stat_key in totals:
		if not _database.query_with_bindings(
			"""INSERT INTO lifetime_statistics (stat_key, value) VALUES (?, ?)
			ON CONFLICT(stat_key) DO UPDATE SET value = excluded.value;""",
			[str(stat_key), float(totals[stat_key])],
		):
			return _rollback("Could not save statistic '%s'" % stat_key)
	return _commit_transaction()


func metadata_value(key: String, default_value: String = "") -> String:
	if not _query_with_bindings(
		"SELECT setting_value FROM database_metadata WHERE setting_key = ? LIMIT 1;",
		[key],
	):
		return default_value
	if _database.query_result.is_empty():
		return default_value
	return str(_database.query_result[0]["setting_value"])


func set_metadata_value(key: String, value: String) -> bool:
	return _query_with_bindings(
		"""INSERT INTO database_metadata (setting_key, setting_value) VALUES (?, ?)
		ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;""",
		[key, value],
	)


func get_enabled_enemy_data() -> Dictionary:
	if not _query("SELECT * FROM enemy_archetypes WHERE enabled = 1 ORDER BY id;"):
		return {}
	var catalog := {}
	for row in _database.query_result:
		var data := _enemy_data_from_row(row)
		if data != null:
			catalog[data.id] = data
	return catalog


func get_enemy_spawn_rules() -> Array[Dictionary]:
	if not _query("""SELECT enemy_id, spawn_fraction, fixed_count
		FROM enemy_spawn_rules WHERE enabled = 1 ORDER BY display_order;"""):
		return []
	var rules: Array[Dictionary] = []
	for row in _database.query_result:
		rules.append({
			"enemy_id": StringName(row["enemy_id"]),
			"spawn_fraction": float(row["spawn_fraction"]),
			"fixed_count": int(row["fixed_count"]),
		})
	return rules


func get_weapon_loot_pool_entries(pool_id: StringName) -> Array[Dictionary]:
	if not _query_with_bindings(
		"""SELECT weapon_id, resource_path, weight FROM weapon_loot_pool_entries
		WHERE pool_id = ? AND enabled = 1 ORDER BY display_order;""",
		[String(pool_id)],
	):
		return []
	var entries: Array[Dictionary] = []
	for row in _database.query_result:
		var resource_path := str(row["resource_path"])
		var weapon := load(resource_path) as WeaponData
		if weapon == null or not weapon.validation_errors().is_empty():
			_fail("Invalid weapon resource for '%s': %s" % [row["weapon_id"], resource_path])
			continue
		entries.append({"weapon": weapon, "weight": float(row["weight"])})
	return entries


func _enemy_data_from_row(row: Dictionary) -> EnemyData:
	var resource_path := str(row["resource_path"])
	var template := load(resource_path) as EnemyData
	if template == null:
		_fail("Invalid enemy resource: %s" % resource_path)
		return null
	var data := template.duplicate(true) as EnemyData
	data.id = StringName(row["id"])
	data.name = str(row["display_name"])
	data.max_health = int(row["max_health"])
	data.speed = float(row["movement_speed"])
	data.atk_dmg = int(row["attack_damage"])
	data.atk_rate = float(row["attack_interval"])
	data.los_radius = int(row["sight_radius"])
	data.knockback_recovery_spd = int(row["knockback_recovery_speed"])
	data.wander_radius = float(row["wander_radius"])
	data.min_wait = float(row["minimum_wait"])
	data.max_wait = float(row["maximum_wait"])
	if not data.is_valid():
		_fail("Enemy archetype '%s' contains invalid data" % data.id)
		return null
	return data


func _migrate() -> bool:
	var version := _schema_version()
	if version < 0:
		return false
	if version > CURRENT_SCHEMA_VERSION:
		return _fail(
			"Database schema %d is newer than supported schema %d"
			% [version, CURRENT_SCHEMA_VERSION]
		)
	if version < CURRENT_SCHEMA_VERSION:
		return _migrate_to_version_two()
	return true


func _schema_version() -> int:
	if not _database.query("PRAGMA user_version;"):
		_fail("Could not read schema version: %s" % _database.error_message)
		return -1
	if _database.query_result.is_empty():
		_fail("SQLite returned no schema version")
		return -1
	return int(_database.query_result[0].get("user_version", -1))


func _migrate_to_version_two() -> bool:
	if not _begin_transaction():
		return false
	for table_name in [
		"enemy_spawn_rules",
		"enemy_archetypes",
		"weapon_loot_pool_entries",
		"lifetime_statistics",
		"statistic_definitions",
		"database_metadata",
	]:
		if not _database.query("DROP TABLE IF EXISTS %s;" % table_name):
			return _rollback("Could not replace legacy table '%s'" % table_name)
	for statement in CREATE_SCHEMA:
		if not _database.query(statement):
			return _rollback("Could not create schema: %s" % _database.error_message)
	if not _seed_catalogs():
		return _rollback("Could not seed database catalogs")
	if not _database.query("PRAGMA user_version = %d;" % CURRENT_SCHEMA_VERSION):
		return _rollback("Could not update schema version")
	return _commit_transaction()


func _seed_catalogs() -> bool:
	for definition in STATISTIC_DEFINITIONS:
		if not _database.query_with_bindings(
			"INSERT INTO statistic_definitions VALUES (?, ?, ?, ?, 1);",
			definition,
		):
			return false
		if not _database.query_with_bindings(
			"INSERT INTO lifetime_statistics (stat_key, value) VALUES (?, 0);",
			[definition[0]],
		):
			return false
	for archetype in ENEMY_ARCHETYPES:
		if not _database.query_with_bindings(
			"""INSERT INTO enemy_archetypes VALUES
			(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1);""",
			archetype,
		):
			return false
	for rule in ENEMY_SPAWN_RULES:
		if not _database.query_with_bindings(
			"INSERT INTO enemy_spawn_rules VALUES (?, ?, ?, ?, 1);",
			rule,
		):
			return false
	for index in DEFAULT_WEAPON_POOL.size():
		var weapon: Array = DEFAULT_WEAPON_POOL[index]
		if not _database.query_with_bindings(
			"INSERT INTO weapon_loot_pool_entries VALUES ('default', ?, ?, 1, ?, 1);",
			[weapon[0], weapon[1], index],
		):
			return false
	return true


func _query(statement: String) -> bool:
	if not _available and _database == null:
		return _fail("Query attempted while the database is unavailable")
	if not _database.query(statement):
		return _fail(_database.error_message)
	return true


func _query_with_bindings(statement: String, bindings: Array) -> bool:
	if not _available and _database == null:
		return _fail("Query attempted while the database is unavailable")
	if not _database.query_with_bindings(statement, bindings):
		return _fail(_database.error_message)
	return true


func _begin_transaction() -> bool:
	if not _database.query("BEGIN TRANSACTION;"):
		return _fail("Could not begin transaction: %s" % _database.error_message)
	return true


func _commit_transaction() -> bool:
	if not _database.query("COMMIT;"):
		return _rollback("Could not commit transaction")
	return true


func _rollback(message: String) -> bool:
	_database.query("ROLLBACK;")
	return _fail("%s: %s" % [message, _database.error_message])


func _fail(message: String) -> bool:
	_last_error = message
	push_error("GameDatabase: %s" % message)
	return false


func _exit_tree() -> void:
	close()
