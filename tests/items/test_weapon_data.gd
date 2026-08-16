extends GutTest

const RUSTY_SWORD: WeaponData = preload(
	"res://resources/items/weapons/rusty_sword.tres"
)
const REGULAR_SWORD: WeaponData = preload(
	"res://resources/items/weapons/regular_sword.tres"
)
const WEAPON_AXE: WeaponData = preload(
	"res://resources/items/weapons/weapon_axe.tres"
)
const BOW: WeaponData = preload(
	"res://resources/items/weapons/bow.tres"
)
const MELEE_BEHAVIOR_PATH := "res://scenes/combat/melee_swing_attack.tscn"


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


func test_regular_sword_is_a_valid_faster_melee_definition() -> void:
	assert_eq(REGULAR_SWORD.id, &"regular_sword")
	assert_eq(REGULAR_SWORD.display_name, "Regular Sword")
	assert_eq(REGULAR_SWORD.base_damage, 40)
	assert_almost_eq(REGULAR_SWORD.damage_variance, 0.15, 0.0001)
	assert_almost_eq(REGULAR_SWORD.attack_interval_seconds, 0.4, 0.0001)
	assert_eq(REGULAR_SWORD.knockback_strength, 125)
	assert_eq(REGULAR_SWORD.grip_offset, Vector2(0, -10))
	assert_eq(REGULAR_SWORD.icon.resource_path, REGULAR_SWORD.held_texture.resource_path)
	assert_eq(REGULAR_SWORD.attack_behavior_scene.resource_path, MELEE_BEHAVIOR_PATH)
	assert_true(REGULAR_SWORD.validation_errors().is_empty())


func test_weapon_axe_is_a_valid_heavy_melee_definition() -> void:
	assert_eq(WEAPON_AXE.id, &"weapon_axe")
	assert_eq(WEAPON_AXE.display_name, "Axe")
	assert_eq(WEAPON_AXE.base_damage, 50)
	assert_almost_eq(WEAPON_AXE.damage_variance, 0.25, 0.0001)
	assert_almost_eq(WEAPON_AXE.attack_interval_seconds, 0.7, 0.0001)
	assert_eq(WEAPON_AXE.knockback_strength, 225)
	assert_eq(WEAPON_AXE.grip_offset, Vector2(0, -10))
	assert_eq(WEAPON_AXE.icon.resource_path, WEAPON_AXE.held_texture.resource_path)
	assert_eq(WEAPON_AXE.attack_behavior_scene.resource_path, MELEE_BEHAVIOR_PATH)
	assert_true(WEAPON_AXE.validation_errors().is_empty())


func test_bow_is_a_valid_projectile_weapon_definition() -> void:
	assert_eq(BOW.id, &"bow")
	assert_eq(BOW.display_name, "Bow")
	assert_eq(BOW.base_damage, 30)
	assert_almost_eq(BOW.damage_variance, 0.15, 0.0001)
	assert_almost_eq(BOW.attack_interval_seconds, 0.8, 0.0001)
	assert_eq(BOW.knockback_strength, 100)
	assert_eq(BOW.grip_offset, Vector2.ZERO)
	assert_eq(
		BOW.held_texture.resource_path,
		"res://Dungeon Tileset v1.7/frames/weapon_bow.png",
	)
	assert_eq(BOW.attack_behavior_scene.resource_path, "res://scenes/combat/bow_attack.tscn")
	assert_true(BOW.validation_errors().is_empty())


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
