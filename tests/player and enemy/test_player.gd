extends GutTest

var player: Player
var _previous_invincibility: bool

const INPUT_ACTIONS := ["move left", "move right", "move up", "move down", "attack"]


func before_each() -> void:
	_previous_invincibility = GameState.invincibility_enabled
	GameState.invincibility_enabled = true
	player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)


func after_each() -> void:
	for action in INPUT_ACTIONS:
		Input.action_release(action)
	GameState.invincibility_enabled = _previous_invincibility


func test_ready_equips_rusty_sword_through_controller() -> void:
	assert_same(player.weapon_equipment.equipped_weapon, player.starting_weapon)
	assert_same(player.weapon_controller.equipped_weapon, player.starting_weapon)
	assert_true(player.weapon_controller.active_behavior is MeleeSwingAttack)
	assert_eq(player.weapon_controller.get_child_count(), 1)
	assert_true(player.pillar_inventory.is_empty())
	assert_not_null(player.get_node("CanvasLayer/PillarBar"))


func test_player_is_invincible_by_default() -> void:
	var starting_health := player.health

	player.take_damage(starting_health * 2)

	assert_eq(player.health, starting_health)
	assert_false(player._dead)


func test_player_copies_disabled_invincibility_setting_when_spawned() -> void:
	GameState.invincibility_enabled = false
	var vulnerable_player: Player = preload(
		"res://scenes/player/player.tscn"
	).instantiate()
	add_child_autofree(vulnerable_player)

	assert_false(vulnerable_player.invincible)


func test_distance_tracking_preserves_team_run_statistics() -> void:
	var previous_counts := Stats.pending_counts
	Stats.pending_counts = false
	Stats.begin_run()
	player.global_position = Vector2.ZERO
	player._track_distance()
	player.global_position = Vector2(32, 0)

	player._track_distance()
	var run_statistics := Stats.end_run()
	Stats.pending_counts = previous_counts

	assert_almost_eq(run_statistics["distance_feet"], 10.0, 0.0001)


func test_physics_process_forwards_aim_when_ready() -> void:
	player.weapon_controller.attack_cooldown_seconds = 0.0
	player.weapon_controller.active_behavior.rotation = 999.0
	player._physics_process(0.016)
	assert_ne(player.weapon_controller.active_behavior.rotation, 999.0)


func test_physics_process_forwards_aim_during_cooldown() -> void:
	player.weapon_controller.attack_cooldown_seconds = 1.0
	player.weapon_controller.active_behavior.rotation = 999.0
	player._physics_process(0.016)
	assert_ne(player.weapon_controller.active_behavior.rotation, 999.0)


func test_process_forwards_held_attack_when_inventory_is_closed() -> void:
	Input.action_press("attack")
	player.weapon_controller.attack_cooldown_seconds = 0.0
	player._process(0.016)
	assert_almost_eq(player.weapon_controller.attack_cooldown_seconds, 0.5, 0.0001)


func test_process_blocks_attack_while_inventory_is_open() -> void:
	player.inventory_ui.show_player(player.inventory)
	Input.action_press("attack")
	player.weapon_controller.attack_cooldown_seconds = 0.0
	player._process(0.016)
	assert_eq(player.weapon_controller.attack_cooldown_seconds, 0.0)


func test_equipment_change_replaces_controller_weapon() -> void:
	var texture: Texture2D = preload(
		"res://Dungeon Tileset v1.7/frames/weapon_regular_sword.png"
	)
	var weapon := WeaponData.new()
	weapon.id = &"test_sword"
	weapon.display_name = "Test Sword"
	weapon.icon = texture
	weapon.held_texture = texture
	weapon.base_damage = 12
	weapon.damage_variance = 0.1
	weapon.attack_interval_seconds = 0.25
	weapon.knockback_strength = 75
	weapon.grip_offset = Vector2(1, -8)
	weapon.attack_behavior_scene = preload("res://scenes/combat/melee_swing_attack.tscn")
	player._on_equipped_weapon_changed(player.starting_weapon, weapon)
	assert_same(player.weapon_controller.equipped_weapon, weapon)
	assert_eq(player.weapon_controller.get_child_count(), 1)


func test_stage_four_resources_work_through_player_equipment_scene_flow() -> void:
	var regular_sword: WeaponData = preload(
		"res://resources/items/weapons/regular_sword.tres"
	)
	var weapon_axe: WeaponData = preload(
		"res://resources/items/weapons/weapon_axe.tres"
	)
	player.inventory.add_item(regular_sword)
	player.inventory.add_item(weapon_axe)

	assert_true(player.weapon_equipment.swap_from_inventory(player.inventory, 0))
	assert_same(player.weapon_controller.equipped_weapon, regular_sword)
	assert_same(
		(player.weapon_controller.active_behavior as MeleeSwingAttack).weapon_sprite.texture,
		regular_sword.held_texture,
	)
	assert_true(player.weapon_controller.try_attack())

	assert_true(player.weapon_equipment.swap_from_inventory(player.inventory, 1))
	assert_same(player.weapon_controller.equipped_weapon, weapon_axe)
	assert_same(
		(player.weapon_controller.active_behavior as MeleeSwingAttack).weapon_sprite.texture,
		weapon_axe.held_texture,
	)
	assert_true(player.weapon_controller.try_attack())
	assert_same(player.inventory.item_at(0), player.starting_weapon)
	assert_same(player.inventory.item_at(1), regular_sword)


func test_bow_equips_and_attacks_through_the_player_scene_flow() -> void:
	var bow: WeaponData = preload("res://resources/items/weapons/bow.tres")
	player.inventory.add_item(bow)
	assert_true(player.weapon_equipment.swap_from_inventory(player.inventory, 0))
	assert_same(player.weapon_controller.equipped_weapon, bow)
	assert_true(player.weapon_controller.active_behavior is BowAttack)
	Input.action_press("attack")
	player.weapon_controller.attack_cooldown_seconds = 0.0
	player._process(0.016)
	assert_almost_eq(player.weapon_controller.attack_cooldown_seconds, 0.8, 0.0001)
	var behavior := player.weapon_controller.active_behavior as BowAttack
	assert_eq(behavior.animation_player.current_animation, &"fire")


func test_throwing_axe_is_consumed_after_release_and_allows_re_equipping() -> void:
	var throwing_axe: WeaponData = preload(
		"res://resources/items/weapons/throwing_axe.tres"
	)
	player.inventory.add_item(throwing_axe)
	assert_true(player.weapon_equipment.swap_from_inventory(player.inventory, 0))
	var behavior := player.weapon_controller.active_behavior as ThrowingAxeAttack
	var spawned_projectiles: Array[WeaponHitSource] = []
	behavior.hit_source_spawned.connect(
		func(projectile: WeaponHitSource) -> void: spawned_projectiles.append(projectile)
	)

	behavior._throw_projectile()
	await get_tree().process_frame

	assert_eq(spawned_projectiles.size(), 1)
	if not spawned_projectiles.is_empty():
		autofree(spawned_projectiles[0])
	assert_null(player.weapon_equipment.equipped_weapon)
	assert_null(player.weapon_controller.equipped_weapon)
	assert_null(player.weapon_controller.active_behavior)
	assert_eq(player.weapon_controller.get_child_count(), 0)
	assert_null(player.inventory_ui._equipment_slot._icon.texture)
	assert_eq(player.inventory_ui._equipment_slot.tooltip_text, "Empty equipment slot")

	assert_true(player.weapon_equipment.swap_from_inventory(player.inventory, 0))
	assert_same(player.weapon_equipment.equipped_weapon, player.starting_weapon)
	assert_same(player.weapon_controller.equipped_weapon, player.starting_weapon)
	assert_null(player.inventory.item_at(0))


func test_handle_movement_moving_right_sets_positive_x_and_unflips_sprite() -> void:
	Input.action_press("move right")
	player._handle_movement()
	assert_gt(player.x_direction, 0.0)
	assert_false(player.sprite.flip_h)


func test_handle_movement_moving_left_sets_negative_x_and_flips_sprite() -> void:
	Input.action_press("move left")
	player._handle_movement()
	assert_lt(player.x_direction, 0.0)
	assert_true(player.sprite.flip_h)


func test_handle_movement_moving_up_sets_negative_y() -> void:
	Input.action_press("move up")
	player._handle_movement()
	assert_lt(player.y_direction, 0.0)


func test_handle_movement_sets_normalized_velocity_at_full_speed() -> void:
	Input.action_press("move right")
	player._handle_movement()
	assert_almost_eq(player.velocity.length(), Player.SPEED, 0.01)


func test_handle_movement_zero_input_results_in_zero_velocity() -> void:
	player.velocity_vector = Vector2.ZERO
	player._handle_movement()
	assert_eq(player.velocity, Vector2.ZERO)


func test_handle_animations_plays_idle_when_no_input() -> void:
	player.x_direction = 0.0
	player.y_direction = 0.0
	player._handle_animations()
	assert_eq(player.sprite.animation, &"idle")


func test_handle_animations_plays_moving_when_input_present() -> void:
	player.x_direction = 1.0
	player.y_direction = 0.0
	player._handle_animations()
	assert_eq(player.sprite.animation, &"moving")
