extends GutTest

const WEAPON_LOOT_POOL: WeaponLootPool = preload(
	"res://resources/items/weapon_loot_pool.tres"
)


func test_authored_pool_contains_25_unique_valid_weapons() -> void:
	assert_eq(WEAPON_LOOT_POOL.weapons.size(), 25)
	assert_true(WEAPON_LOOT_POOL.validation_errors().is_empty())


func test_random_weapon_is_reproducible_for_equal_seeds() -> void:
	var first_random_number_generator := RandomNumberGenerator.new()
	var second_random_number_generator := RandomNumberGenerator.new()
	first_random_number_generator.seed = 13579
	second_random_number_generator.seed = 13579

	for _selection_index in 20:
		assert_same(
			WEAPON_LOOT_POOL.random_weapon(first_random_number_generator),
			WEAPON_LOOT_POOL.random_weapon(second_random_number_generator),
		)


func test_random_weapon_returns_null_for_missing_rng_or_empty_pool() -> void:
	var empty_pool := WeaponLootPool.new()
	var random_number_generator := RandomNumberGenerator.new()

	assert_null(WEAPON_LOOT_POOL.random_weapon(null))
	assert_null(empty_pool.random_weapon(random_number_generator))
	assert_eq(empty_pool.validation_errors(), PackedStringArray(["weapons must not be empty"]))
