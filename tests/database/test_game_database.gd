extends GutTest

## Integration coverage for the SQLite schema and its typed catalog boundaries.

var _database_path: String
var _service: GameDatabaseService


func before_each() -> void:
	_database_path = "user://gut_dungeon_%d.db" % Time.get_ticks_usec()
	_remove_database()
	_service = GameDatabaseService.new()


func after_each() -> void:
	_service.close()
	_service.free()
	_remove_database()


func test_new_database_seeds_statistic_definitions_and_totals() -> void:
	assert_true(_service.initialize(_database_path))
	var definitions := _service.get_statistic_definitions()
	var totals := _service.get_lifetime_statistics()

	assert_eq(definitions.size(), 6)
	assert_eq(definitions[0]["key"], "distance_feet")
	assert_eq(totals.size(), 6)
	assert_eq(totals["enemies_killed"], 0.0)


func test_lifetime_statistics_persist_across_connections() -> void:
	assert_true(_service.initialize(_database_path))
	var totals := _service.get_lifetime_statistics()
	totals["enemies_killed"] = 12.0
	totals["damage_done"] = 345.0
	assert_true(_service.save_lifetime_statistics(totals))

	assert_true(_service.initialize(_database_path))
	var reloaded := _service.get_lifetime_statistics()
	assert_eq(reloaded["enemies_killed"], 12.0)
	assert_eq(reloaded["damage_done"], 345.0)


func test_enemy_catalog_contains_every_current_archetype() -> void:
	assert_true(_service.initialize(_database_path))
	var catalog := _service.get_enabled_enemy_data()

	assert_eq(catalog.size(), 6)
	for enemy_id in [
		&"goblin",
		&"imp",
		&"masked_orc",
		&"zombie",
		&"skeleton",
		&"necromancer",
	]:
		assert_true(catalog.has(enemy_id))
		assert_true((catalog[enemy_id] as EnemyData).is_valid())
	assert_eq((catalog[&"necromancer"] as EnemyData).max_health, 225)
	assert_eq((catalog[&"masked_orc"] as EnemyData).atk_rate, 0.5)


func test_spawn_rules_preserve_current_roster_size() -> void:
	assert_true(_service.initialize(_database_path))
	var total := 0
	var rules := _service.get_enemy_spawn_rules()
	for rule in rules:
		total += (
			roundi(15 * float(rule["spawn_fraction"]))
			+ int(rule["fixed_count"])
		)

	assert_eq(rules.size(), 5)
	assert_eq(total, 21)


func test_default_weapon_pool_contains_every_weapon_resource() -> void:
	assert_true(_service.initialize(_database_path))
	var entries := _service.get_weapon_loot_pool_entries(&"default")
	var ids := {}
	for entry in entries:
		var weapon := entry["weapon"] as WeaponData
		ids[weapon.id] = true
		assert_gt(float(entry["weight"]), 0.0)

	assert_eq(entries.size(), 25)
	assert_eq(ids.size(), 25)


func test_version_one_database_upgrades_to_current_catalogs() -> void:
	var writer := SQLite.new()
	writer.path = _database_path
	assert_true(writer.open_db())
	assert_true(writer.query("CREATE TABLE enemy_archetypes (id TEXT PRIMARY KEY);"))
	assert_true(writer.query("INSERT INTO enemy_archetypes VALUES ('legacy');"))
	assert_true(writer.query("PRAGMA user_version = 1;"))
	writer.close_db()

	assert_true(_service.initialize(_database_path))
	assert_eq(_service.get_enabled_enemy_data().size(), 6)
	assert_eq(_service.get_statistic_definitions().size(), 6)


func _remove_database() -> void:
	var absolute_path := ProjectSettings.globalize_path(_database_path)
	for suffix in ["", "-shm", "-wal"]:
		var candidate: String = absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
