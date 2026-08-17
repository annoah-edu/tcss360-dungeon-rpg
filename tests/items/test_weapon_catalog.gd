extends GutTest

const WEAPON_DIRECTORY := "res://resources/items/weapons"
const MELEE_BEHAVIOR_PATH := "res://scenes/combat/melee_swing_attack.tscn"
const BOW_BEHAVIOR_PATH := "res://scenes/combat/bow_attack.tscn"
const THROWING_AXE_BEHAVIOR_PATH := "res://scenes/combat/throwing_axe_attack.tscn"
const EXPECTED_TEXTURE_FILES := [
	"weapon_anime_sword.png",
	"weapon_axe.png",
	"weapon_baton_with_spikes.png",
	"weapon_big_hammer.png",
	"weapon_bow.png",
	"weapon_cleaver.png",
	"weapon_double_axe.png",
	"weapon_duel_sword.png",
	"weapon_golden_sword.png",
	"weapon_green_magic_staff.png",
	"weapon_hammer.png",
	"weapon_katana.png",
	"weapon_knife.png",
	"weapon_knight_sword.png",
	"weapon_lavish_sword.png",
	"weapon_mace.png",
	"weapon_machete.png",
	"weapon_red_gem_sword.png",
	"weapon_red_magic_staff.png",
	"weapon_regular_sword.png",
	"weapon_rusty_sword.png",
	"weapon_saw_sword.png",
	"weapon_spear.png",
	"weapon_throwing_axe.png",
	"weapon_waraxe.png",
]


func test_catalog_has_one_valid_definition_for_every_supported_texture() -> void:
	var weapons := _load_weapon_catalog()
	var found_texture_files: Array[String] = []
	var found_ids: Dictionary[StringName, bool] = {}

	assert_eq(weapons.size(), EXPECTED_TEXTURE_FILES.size())
	for weapon in weapons:
		assert_true(
			weapon.validation_errors().is_empty(),
			"%s must be a valid WeaponData resource" % weapon.resource_path,
		)
		assert_false(
			found_ids.has(weapon.id),
			"Weapon id '%s' must be unique" % weapon.id,
		)
		found_ids[weapon.id] = true
		assert_same(weapon.icon, weapon.held_texture)
		found_texture_files.append(weapon.held_texture.resource_path.get_file())

	found_texture_files.sort()
	var expected_texture_files: Array = EXPECTED_TEXTURE_FILES.duplicate()
	expected_texture_files.sort()
	assert_eq(found_texture_files, expected_texture_files)


func test_every_catalog_weapon_equips_with_its_authored_texture_and_behavior() -> void:
	var controller := WeaponController.new()
	add_child_autofree(controller)

	for weapon in _load_weapon_catalog():
		controller.equip_weapon(weapon)
		assert_same(controller.equipped_weapon, weapon)
		assert_eq(controller.get_child_count(), 1)
		if weapon.id == &"bow":
			assert_eq(weapon.attack_behavior_scene.resource_path, BOW_BEHAVIOR_PATH)
			assert_true(controller.active_behavior is BowAttack)
			var bow_attack := controller.active_behavior as BowAttack
			assert_same(bow_attack.rest_bow.texture, weapon.held_texture)
			assert_eq(bow_attack.rest_bow.offset, weapon.grip_offset)
		elif weapon.id == &"throwing_axe":
			assert_eq(
				weapon.attack_behavior_scene.resource_path,
				THROWING_AXE_BEHAVIOR_PATH,
			)
			assert_true(controller.active_behavior is ThrowingAxeAttack)
			var throwing_axe_attack := controller.active_behavior as ThrowingAxeAttack
			assert_same(throwing_axe_attack.weapon_sprite.texture, weapon.held_texture)
			assert_eq(throwing_axe_attack.weapon_sprite.offset, weapon.grip_offset)
		else:
			assert_eq(weapon.attack_behavior_scene.resource_path, MELEE_BEHAVIOR_PATH)
			assert_true(controller.active_behavior is MeleeSwingAttack)
			var melee_attack := controller.active_behavior as MeleeSwingAttack
			assert_same(melee_attack.weapon_sprite.texture, weapon.held_texture)
			assert_eq(melee_attack.weapon_sprite.offset, weapon.grip_offset)
		assert_true(controller.try_attack())
		assert_almost_eq(
			controller.attack_cooldown_seconds,
			weapon.attack_interval_seconds,
			0.0001,
		)


func _load_weapon_catalog() -> Array[WeaponData]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(WEAPON_DIRECTORY):
		if file_name.ends_with(".tres"):
			paths.append(WEAPON_DIRECTORY.path_join(file_name))
	paths.sort()

	var weapons: Array[WeaponData] = []
	for path in paths:
		var weapon := load(path) as WeaponData
		assert_not_null(weapon, "%s must load as WeaponData" % path)
		if weapon != null:
			weapons.append(weapon)
	return weapons
