extends GutTest

var player: Player

const INPUT_ACTIONS := ["move left", "move right", "move up", "move down", "attack"]


func before_each() -> void:
	player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)


func after_each() -> void:
	for action in INPUT_ACTIONS:
		Input.action_release(action)


func test_ready_equips_rusty_sword_through_controller() -> void:
	assert_same(player.weapon_equipment.equipped_weapon, player.starting_weapon)
	assert_same(player.weapon_controller.equipped_weapon, player.starting_weapon)
	assert_true(player.weapon_controller.active_behavior is MeleeSwingAttack)
	assert_eq(player.weapon_controller.get_child_count(), 1)


func test_physics_process_forwards_aim_when_ready() -> void:
	player.weapon_controller.attack_cooldown_seconds = 0.0
	player.weapon_controller.active_behavior.rotation = 999.0
	player._physics_process(0.016)
	assert_ne(player.weapon_controller.active_behavior.rotation, 999.0)


func test_physics_process_does_not_aim_during_cooldown() -> void:
	player.weapon_controller.attack_cooldown_seconds = 1.0
	player.weapon_controller.active_behavior.rotation = 999.0
	player._physics_process(0.016)
	assert_eq(player.weapon_controller.active_behavior.rotation, 999.0)


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
