extends GdUnitTestSuite

## Tests the boundary between database data and the Enemy scene.

func test_definition_rejects_invalid_ranges() -> void:
	var definition := _definition()
	definition.maximum_wait = definition.minimum_wait - 1.0
	assert_bool(definition.is_valid()).is_false()

func test_enemy_copies_database_definition_before_entering_tree() -> void:
	var definition := _definition()
	var enemy := definition.scene.instantiate() as Enemy
	enemy.apply_definition(definition)
	assert_int(enemy.max_health).is_equal(175)
	assert_float(enemy.speed).is_equal(52.0)
	assert_int(enemy.los_radius).is_equal(90)
	assert_int(enemy.knockback_recovery_spd).is_equal(650)
	assert_float(enemy.wander_radius).is_equal(125.0)
	assert_float(enemy.min_wait).is_equal(1.5)
	assert_float(enemy.max_wait).is_equal(2.5)
	enemy.free()

func _definition() -> EnemyDefinition:
	var definition := EnemyDefinition.new()
	definition.id = &"test_enemy"
	definition.scene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	definition.max_health = 175
	definition.movement_speed = 52.0
	definition.sight_radius = 90
	definition.knockback_recovery_speed = 650
	definition.wander_radius = 125.0
	definition.minimum_wait = 1.5
	definition.maximum_wait = 2.5
	return definition
