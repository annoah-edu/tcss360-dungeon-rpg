extends GutTest

const RUSTY_SWORD: WeaponData = preload(
	"res://resources/items/weapons/rusty_sword.tres"
)


func test_rusty_sword_matches_current_weapon_definition() -> void:
	assert_true(RUSTY_SWORD is ItemData)
	assert_eq(RUSTY_SWORD.id, &"rusty_sword")
	assert_eq(RUSTY_SWORD.display_name, "Rusty Sword")
	assert_eq(
		RUSTY_SWORD.held_texture.resource_path,
		"res://Dungeon Tileset v1.7/frames/weapon_rusty_sword.png",
	)
	assert_same(RUSTY_SWORD.icon, RUSTY_SWORD.held_texture)
	assert_eq(RUSTY_SWORD.base_damage, 34)
	assert_almost_eq(RUSTY_SWORD.damage_variance, 0.20, 0.0001)
	assert_almost_eq(RUSTY_SWORD.attack_interval_seconds, 0.5, 0.0001)
	assert_eq(RUSTY_SWORD.knockback_strength, 150)
	assert_eq(RUSTY_SWORD.grip_offset, Vector2(0, -10))
	assert_eq(
		RUSTY_SWORD.attack_behavior_scene.resource_path,
		"res://scenes/combat/melee_swing_attack.tscn",
	)


func test_stage_three_weapon_definition_is_fully_valid() -> void:
	assert_true(RUSTY_SWORD.validation_errors().is_empty())


func test_validation_reports_every_invalid_weapon_field() -> void:
	var weapon := WeaponData.new()
	weapon.damage_variance = -0.01
	weapon.knockback_strength = -1

	var errors := weapon.validation_errors()

	assert_eq(errors.size(), 9)
	assert_true(errors.has("id must not be empty"))
	assert_true(errors.has("display_name must not be empty"))
	assert_true(errors.has("icon must not be null"))
	assert_true(errors.has("held_texture must not be null"))
	assert_true(errors.has("base_damage must be greater than zero"))
	assert_true(errors.has("damage_variance must be between zero and one"))
	assert_true(errors.has("attack_interval_seconds must be greater than zero"))
	assert_true(errors.has("knockback_strength must not be negative"))
	assert_true(errors.has("attack_behavior_scene must not be null"))
