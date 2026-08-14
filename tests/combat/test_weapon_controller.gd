extends GutTest

const RUSTY_SWORD: WeaponData = preload(
	"res://resources/items/weapons/rusty_sword.tres"
)

var controller: WeaponController


func before_each() -> void:
	controller = WeaponController.new()
	add_child_autofree(controller)
	controller.equip_weapon(RUSTY_SWORD)


func test_equip_owns_data_and_exactly_one_configured_behavior() -> void:
	assert_same(controller.equipped_weapon, RUSTY_SWORD)
	assert_true(controller.active_behavior is MeleeSwingAttack)
	assert_eq(controller.get_child_count(), 1)
	var behavior := controller.active_behavior as MeleeSwingAttack
	assert_same(behavior.weapon_sprite.texture, RUSTY_SWORD.held_texture)


func test_repeated_equip_replaces_behavior_without_duplicate_children() -> void:
	var previous := controller.active_behavior
	controller.equip_weapon(RUSTY_SWORD)
	assert_eq(controller.get_child_count(), 1)
	assert_ne(controller.active_behavior, previous)
	assert_false(is_instance_valid(previous))


func test_invalid_equip_leaves_current_weapon_unchanged() -> void:
	var invalid := WeaponData.new()
	controller.equip_weapon(invalid)
	assert_same(controller.equipped_weapon, RUSTY_SWORD)
	assert_eq(controller.get_child_count(), 1)


func test_wrong_behavior_type_leaves_current_weapon_unchanged() -> void:
	var malformed := RUSTY_SWORD.duplicate() as WeaponData
	var ordinary_scene := PackedScene.new()
	var ordinary_root := Node2D.new()
	ordinary_scene.pack(ordinary_root)
	ordinary_root.free()
	malformed.attack_behavior_scene = ordinary_scene
	var previous_behavior := controller.active_behavior
	controller.equip_weapon(malformed)
	assert_same(controller.equipped_weapon, RUSTY_SWORD)
	assert_same(controller.active_behavior, previous_behavior)
	assert_eq(controller.get_child_count(), 1)


func test_try_attack_sets_cooldown_and_repeats_when_ready() -> void:
	assert_true(controller.try_attack())
	assert_almost_eq(controller.attack_cooldown_seconds, 0.5, 0.0001)
	assert_false(controller.try_attack())
	controller._process(0.5)
	assert_true(controller.try_attack())


func test_aim_updates_only_when_cooldown_is_ready() -> void:
	controller.attack_cooldown_seconds = 1.0
	controller.active_behavior.rotation = 999.0
	controller.aim_at(controller.active_behavior.global_position + Vector2.RIGHT)
	assert_eq(controller.active_behavior.rotation, 999.0)
	controller.attack_cooldown_seconds = 0.0
	controller.aim_at(controller.active_behavior.global_position + Vector2.RIGHT)
	assert_almost_eq(controller.active_behavior.rotation, 0.0, 0.001)


func test_hit_request_damages_every_target_with_weapon_knockback() -> void:
	var enemy_a: Enemy = double(Enemy).new()
	var enemy_b: Enemy = double(Enemy).new()
	controller.damage_rng.seed = 12345
	var source := Vector2(4, 8)
	controller._on_hit_requested([enemy_a, enemy_b], source)
	assert_called_count(enemy_a.take_damage, 1)
	assert_called_count(enemy_b.take_damage, 1)
	var parameters: Array = get_call_parameters(enemy_a, "take_damage", 0)
	assert_between(parameters[0], roundi(34 * 0.8), roundi(34 * 1.2))
	assert_eq(parameters[1], source)
	assert_eq(parameters[2], 150)
