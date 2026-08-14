extends GutTest

var player: Player

const INPUT_ACTIONS := ["move left", "move right", "move up", "move down", "attack"]


func before_each() -> void:
	var player_scene: PackedScene = preload("res://scenes/player/player.tscn")
	player = player_scene.instantiate()
	add_child_autofree(player)


func after_each() -> void:
	# Make sure no test leaks a held-down input action into the next one.
	for action in INPUT_ACTIONS:
		Input.action_release(action)


# ---------- _ready() ----------

func test_ready_hides_swing_effect() -> void:
	assert_false(player.swing.visible, "Swing sprite should be hidden after _ready()")


func test_ready_connects_hitbox_signals() -> void:
	assert_true(
		player.weapon_hitbox.body_entered.is_connected(player._enemy_entered),
		"body_entered should be connected to _enemy_entered"
	)
	assert_true(
		player.weapon_hitbox.body_exited.is_connected(player._enemy_exited),
		"body_exited should be connected to _enemy_exited"
	)


func test_rusty_sword_defaults_match_current_combat_contract() -> void:
	assert_eq(player.atk_dmg, 34)
	assert_almost_eq(player.atk_rate, 0.5, 0.0001)
	assert_eq(player.knockback_strength, 150)
	assert_eq(
		player.weapon_sprite.texture.resource_path,
		"res://Dungeon Tileset v1.7/frames/weapon_rusty_sword.png",
	)
	assert_eq(player.weapon_sprite.offset, Vector2(0, -10))
	assert_eq(player.weapon_hitbox.collision_mask, 4)


# ---------- _process() ----------

func test_process_decrements_attack_cooldown_by_delta() -> void:
	player.atk_cooldown = 1.0
	player._process(0.25)
	assert_almost_eq(player.atk_cooldown, 0.75, 0.0001)


# ---------- _physics_process() ----------

func test_physics_process_rotates_weapon_when_cooldown_is_ready() -> void:
	player.atk_cooldown = 0.0
	# Sentinel the real function can never produce: Vector2.angle() is bounded to [-PI, PI].
	player.weapon.rotation = 999.0
	player._physics_process(0.016)
	assert_ne(player.weapon.rotation, 999.0, "Weapon rotation should have been recalculated")


func test_physics_process_skips_weapon_rotation_while_on_cooldown() -> void:
	player.atk_cooldown = 1.0
	player.weapon.rotation = 999.0
	player._physics_process(0.016)
	assert_eq(player.weapon.rotation, 999.0, "Weapon rotation should be untouched while on cooldown")


# ---------- _handle_movement() ----------

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


func test_handle_movement_no_x_input_decays_velocity_toward_zero() -> void:
	player.velocity_vector.x = 50.0
	player._handle_movement()
	assert_eq(player.x_direction, 0.0)
	assert_eq(player.velocity_vector.x, 0.0)


func test_handle_movement_moving_down_sets_positive_y() -> void:
	Input.action_press("move down")
	player._handle_movement()
	assert_gt(player.y_direction, 0.0)


func test_handle_movement_moving_up_sets_negative_y() -> void:
	Input.action_press("move up")
	player._handle_movement()
	assert_lt(player.y_direction, 0.0)


func test_handle_movement_no_y_input_decays_velocity_toward_zero() -> void:
	player.velocity_vector.y = 50.0
	player._handle_movement()
	assert_eq(player.y_direction, 0.0)
	assert_eq(player.velocity_vector.y, 0.0)


func test_handle_movement_sets_normalized_velocity_at_full_speed() -> void:
	Input.action_press("move right")
	player._handle_movement()
	assert_almost_eq(player.velocity.length(), Player.SPEED, 0.01)


func test_handle_movement_zero_input_results_in_zero_velocity() -> void:
	player.velocity_vector = Vector2.ZERO
	player._handle_movement()
	assert_eq(player.velocity, Vector2.ZERO)


# ---------- _handle_animations() ----------

func test_handle_animations_plays_idle_when_no_input() -> void:
	player.x_direction = 0.0
	player.y_direction = 0.0
	player._handle_animations()
	assert_eq(player.sprite.animation, StringName("idle"))


func test_handle_animations_plays_moving_when_x_input_present() -> void:
	player.x_direction = 1.0
	player.y_direction = 0.0
	player._handle_animations()
	assert_eq(player.sprite.animation, StringName("moving"))


func test_handle_animations_plays_moving_when_y_input_present() -> void:
	player.x_direction = 0.0
	player.y_direction = 1.0
	player._handle_animations()
	assert_eq(player.sprite.animation, StringName("moving"))


# ---------- _apply_weapon_facing() -- requires the small refactor described above ----------

func test_apply_weapon_facing_flips_and_adds_180_degrees_when_facing_left() -> void:
	var direction := Vector2(-5, 0)
	player._apply_weapon_facing(direction)
	assert_eq(player.weapon.scale.x, -1.0)
	assert_almost_eq(player.weapon.rotation, direction.angle() + PI, 0.001)


func test_apply_weapon_facing_no_flip_when_facing_right() -> void:
	var direction := Vector2(5, 0)
	player._apply_weapon_facing(direction)
	assert_eq(player.weapon.scale.x, 1.0)
	assert_almost_eq(player.weapon.rotation, direction.angle(), 0.001)


func test_apply_weapon_facing_treats_zero_x_as_not_negative() -> void:
	# direction.x == 0 should take the "else" branch, not the flip branch.
	var direction := Vector2(0, 10)
	player._apply_weapon_facing(direction)
	assert_eq(player.weapon.scale.x, 1.0)
	assert_almost_eq(player.weapon.rotation, direction.angle(), 0.001)


func test_handle_weapon_rotation_delegates_without_error() -> void:
	player._handle_weapon_rotation()
	assert_true(player.weapon.scale.x == 1.0 or player.weapon.scale.x == -1.0)


# ---------- _handle_attacking() ----------

func test_handle_attacking_triggers_swing_when_pressed_and_off_cooldown() -> void:
	Input.action_press("attack")
	player.atk_cooldown = 0.0
	player.atk_rate = 0.5

	player._handle_attacking()

	assert_almost_eq(player.atk_cooldown, 0.5, 0.0001)
	assert_almost_eq(player.anim_player.speed_scale, 1.0, 0.0001)
	assert_eq(player.anim_player.current_animation, "swing")


func test_handle_attacking_blocked_while_on_cooldown() -> void:
	Input.action_press("attack")
	player.atk_cooldown = 1.0

	player._handle_attacking()

	assert_eq(player.atk_cooldown, 1.0, "Cooldown should be untouched while still active")


func test_handle_attacking_does_nothing_when_not_pressed() -> void:
	player.atk_cooldown = 0.0

	player._handle_attacking()

	assert_eq(player.atk_cooldown, 0.0, "Cooldown should stay at 0 when attack isn't pressed")


func test_swing_animation_has_one_damage_event_at_authored_hit_time() -> void:
	var swing_animation: Animation = player.anim_player.get_animation(&"swing")
	assert_not_null(swing_animation)
	if swing_animation == null:
		return

	var damage_key_times: Array[float] = []
	for track_index in swing_animation.get_track_count():
		if swing_animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in swing_animation.track_get_key_count(track_index):
			var key_value: Dictionary = swing_animation.track_get_key_value(
				track_index,
				key_index,
			)
			if key_value.get("method", &"") != &"_damage_enemies":
				continue
			assert_eq(swing_animation.track_get_path(track_index), NodePath("."))
			damage_key_times.append(
				swing_animation.track_get_key_time(track_index, key_index),
			)

	assert_eq(damage_key_times.size(), 1, "Swing should request damage exactly once")
	if damage_key_times.size() == 1:
		assert_almost_eq(damage_key_times[0], 1.0 / 6.0, 0.0001)


# ---------- _show_swing() / _hide_swing() ----------

func test_show_swing_positions_and_reveals_swing_sprite() -> void:
	player.weapon_sprite.position = Vector2(3, 4)
	player.weapon_sprite.rotation = 0.5

	player._show_swing()

	assert_true(player.swing.visible)
	assert_eq(player.swing.position, Vector2(3, 4))
	assert_almost_eq(player.swing.rotation, 0.5 + PI * 1.15, 0.0001)


func test_hide_swing_hides_swing_sprite() -> void:
	player.swing.visible = true
	player._hide_swing()
	assert_false(player.swing.visible)


# ---------- _enemy_entered() / _enemy_exited() ----------
# NOTE: assumes Enemy has `class_name Enemy` declared, matching the typed
# `Array[Enemy]` / `as Enemy` usage in player.gd.

func test_enemy_entered_adds_body_that_is_in_enemy_group() -> void:
	var enemy_double: Enemy = double(Enemy).new()
	var body := Node2D.new()
	autofree(body)
	enemy_double.add_child(body)
	body.add_to_group("enemy")

	player._enemy_entered(body)

	assert_eq(player.enemies_in_range.size(), 1)
	assert_same(player.enemies_in_range[0], enemy_double)


func test_enemy_entered_ignores_body_not_in_enemy_group() -> void:
	var body := Node2D.new()
	autofree(body)

	player._enemy_entered(body)

	assert_eq(player.enemies_in_range.size(), 0)


func test_enemy_exited_removes_body_that_is_in_enemy_group() -> void:
	var enemy_double: Enemy = double(Enemy).new()
	var body := Node2D.new()
	autofree(body)
	enemy_double.add_child(body)
	body.add_to_group("enemy")
	player.enemies_in_range.append(enemy_double)

	player._enemy_exited(body)

	assert_eq(player.enemies_in_range.size(), 0)


func test_enemy_exited_ignores_body_not_in_enemy_group() -> void:
	var enemy_double: Enemy = double(Enemy).new()
	player.enemies_in_range.append(enemy_double)
	var body := Node2D.new()
	autofree(body)

	player._enemy_exited(body)

	assert_eq(
		player.enemies_in_range.size(), 1,
		"Only bodies in the 'enemy' group should be removed"
	)


# ---------- _damage_enemies() ----------

func test_damage_enemies_does_nothing_when_range_is_empty() -> void:
	var unrelated_enemy: Enemy = double(Enemy).new()
	player.enemies_in_range = []

	player._damage_enemies()

	assert_eq(player.enemies_in_range.size(), 0)
	assert_called_count(unrelated_enemy.take_damage, 0)


func test_damage_enemies_hits_every_enemy_in_range_within_damage_bounds() -> void:
	var enemy_a: Enemy = double(Enemy).new()
	var enemy_b: Enemy = double(Enemy).new()
	player.enemies_in_range = [enemy_a, enemy_b]
	player.atk_dmg = 34
	player.knockback_strength = 150

	player._damage_enemies()

	assert_called_count(enemy_a.take_damage, 1)
	assert_called_count(enemy_b.take_damage, 1)

	var params: Array = get_call_parameters(enemy_a, "take_damage", 0)
	var min_damage: int = roundi(34 * 0.80)
	var max_damage: int = roundi(34 * 1.20)

	assert_true(
		params[0] >= min_damage and params[0] <= max_damage,
		"Damage %s should fall within the +/-20%% deviation range [%s, %s]" % [params[0], min_damage, max_damage]
	)
	assert_eq(params[1], player.weapon_hitbox.global_position)
	assert_eq(params[2], 150)
