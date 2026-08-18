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
const THROWING_AXE: WeaponData = preload(
	"res://resources/items/weapons/throwing_axe.tres"
)

var controller: WeaponController
var spawned_projectile: WeaponHitSource


func before_each() -> void:
	spawned_projectile = null
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


func test_aim_updates_during_attack_cooldown() -> void:
	controller.attack_cooldown_seconds = 1.0
	controller.active_behavior.rotation = 999.0
	controller.aim_at(controller.active_behavior.global_position + Vector2.RIGHT)
	assert_almost_eq(controller.active_behavior.rotation, 0.0, 0.001)


func test_hit_request_damages_every_target_with_weapon_knockback() -> void:
	var enemy_a: Enemy = double(Enemy).new()
	var enemy_b: Enemy = double(Enemy).new()
	controller.damage_rng.seed = 12345
	var source := Vector2(4, 8)
	controller._on_hit_requested([enemy_a, enemy_b], source, RUSTY_SWORD)
	assert_called_count(enemy_a.take_damage, 1)
	assert_called_count(enemy_b.take_damage, 1)
	var parameters: Array = get_call_parameters(enemy_a, "take_damage", 0)
	assert_between(parameters[0], roundi(34 * 0.8), roundi(34 * 1.2))
	assert_eq(parameters[1], source)
	assert_eq(parameters[2], 150)


func test_hit_request_records_damage_in_team_run_statistics() -> void:
	var previous_counts := Stats.pending_counts
	Stats.pending_counts = false
	Stats.begin_run()
	var enemy: Enemy = double(Enemy).new()
	controller.damage_rng.seed = 86420

	controller._on_hit_requested([enemy], Vector2.ZERO, RUSTY_SWORD)
	var parameters: Array = get_call_parameters(enemy, "take_damage", 0)
	var run_statistics := Stats.end_run()
	Stats.pending_counts = previous_counts

	assert_eq(run_statistics["damage_done"], float(parameters[0]))


func test_regular_sword_equips_renders_and_attacks_with_its_data() -> void:
	controller.equip_weapon(REGULAR_SWORD)
	var behavior := controller.active_behavior as MeleeSwingAttack
	assert_same(controller.equipped_weapon, REGULAR_SWORD)
	assert_same(behavior.weapon_sprite.texture, REGULAR_SWORD.held_texture)
	assert_eq(behavior.weapon_sprite.offset, REGULAR_SWORD.grip_offset)
	assert_true(controller.try_attack())
	assert_almost_eq(controller.attack_cooldown_seconds, 0.4, 0.0001)
	assert_almost_eq(behavior.animation_player.speed_scale, 1.25, 0.0001)
	_assert_damage_uses_equipped_weapon(REGULAR_SWORD)


func test_weapon_axe_equips_renders_and_attacks_with_its_data() -> void:
	controller.equip_weapon(WEAPON_AXE)
	var behavior := controller.active_behavior as MeleeSwingAttack
	assert_same(controller.equipped_weapon, WEAPON_AXE)
	assert_same(behavior.weapon_sprite.texture, WEAPON_AXE.held_texture)
	assert_eq(behavior.weapon_sprite.offset, WEAPON_AXE.grip_offset)
	assert_true(controller.try_attack())
	assert_almost_eq(controller.attack_cooldown_seconds, 0.7, 0.0001)
	assert_almost_eq(behavior.animation_player.speed_scale, 0.5 / 0.7, 0.0001)
	_assert_damage_uses_equipped_weapon(WEAPON_AXE)


func test_bow_equips_and_starts_its_distinct_attack_behavior() -> void:
	controller.equip_weapon(BOW)
	var behavior := controller.active_behavior as BowAttack
	assert_same(controller.equipped_weapon, BOW)
	assert_not_null(behavior)
	assert_same(behavior.rest_bow.texture, BOW.held_texture)
	assert_true(controller.try_attack())
	assert_almost_eq(controller.attack_cooldown_seconds, 0.8, 0.0001)
	assert_eq(behavior.animation_player.current_animation, &"fire")


func test_in_flight_arrow_keeps_bow_damage_after_an_equipment_change() -> void:
	controller.equip_weapon(BOW)
	var behavior := controller.active_behavior as BowAttack
	behavior.hit_source_spawned.connect(_capture_projectile)
	behavior._fire_projectile()
	assert_not_null(spawned_projectile)
	if spawned_projectile == null:
		return
	autofree(spawned_projectile)
	controller.equip_weapon(WEAPON_AXE)
	var enemy: Enemy = double(Enemy).new()
	controller.damage_rng.seed = 97531
	(spawned_projectile as ArrowProjectile)._on_body_entered(enemy)
	assert_called_count(enemy.take_damage, 1)
	var parameters: Array = get_call_parameters(enemy, "take_damage", 0)
	assert_between(parameters[0], roundi(30 * 0.85), roundi(30 * 1.15))
	assert_eq(parameters[2], 100)


func test_throwing_axe_commit_requests_single_use_consumption() -> void:
	controller.equip_weapon(THROWING_AXE)
	var behavior := controller.active_behavior as ThrowingAxeAttack
	behavior.hit_source_spawned.connect(_capture_projectile)
	watch_signals(controller)

	behavior._throw_projectile()
	await get_tree().process_frame

	assert_not_null(spawned_projectile)
	if spawned_projectile != null:
		autofree(spawned_projectile)
	assert_signal_emitted_with_parameters(
		controller,
		&"weapon_consumed",
		[THROWING_AXE],
	)


func test_clear_weapon_removes_only_the_expected_equipped_definition() -> void:
	controller.clear_weapon(BOW)
	assert_same(controller.equipped_weapon, RUSTY_SWORD)
	assert_not_null(controller.active_behavior)

	controller.clear_weapon(RUSTY_SWORD)
	assert_null(controller.equipped_weapon)
	assert_null(controller.active_behavior)
	assert_eq(controller.get_child_count(), 0)


func _capture_projectile(projectile: WeaponHitSource) -> void:
	spawned_projectile = projectile


func _assert_damage_uses_equipped_weapon(weapon: WeaponData) -> void:
	var enemy: Enemy = double(Enemy).new()
	controller.damage_rng.seed = 2468
	controller._on_hit_requested([enemy], Vector2.ZERO, weapon)
	assert_called_count(enemy.take_damage, 1)
	var parameters: Array = get_call_parameters(enemy, "take_damage", 0)
	var minimum_damage := roundi(weapon.base_damage * (1.0 - weapon.damage_variance))
	var maximum_damage := roundi(weapon.base_damage * (1.0 + weapon.damage_variance))
	assert_between(parameters[0], minimum_damage, maximum_damage)
	assert_eq(parameters[2], weapon.knockback_strength)
