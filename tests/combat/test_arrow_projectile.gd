extends GutTest

var arrow: ArrowProjectile


func before_each() -> void:
	arrow = preload("res://scenes/combat/arrow_projectile.tscn").instantiate()
	add_child_autofree(arrow)


func test_scene_uses_world_and_enemy_collision_layers() -> void:
	assert_almost_eq(arrow.speed_pixels_per_second, 240.0, 0.0001)
	assert_almost_eq(arrow.lifetime_seconds, 2.0, 0.0001)
	assert_eq(arrow.hit_detection.collision_layer, 0)
	assert_eq(arrow.hit_detection.collision_mask, 5)
	var shape := arrow.hit_detection.get_node("CollisionShape2D") as CollisionShape2D
	assert_eq((shape.shape as RectangleShape2D).size, Vector2(10, 3))


func test_launch_normalizes_direction_and_moves_in_world_space() -> void:
	arrow.global_position = Vector2(10, 20)
	arrow.launch(Vector2(3, 4))
	arrow._physics_process(0.25)
	assert_eq(arrow.direction, Vector2(0.6, 0.8))
	assert_almost_eq(arrow.global_position.x, 46.0, 0.001)
	assert_almost_eq(arrow.global_position.y, 68.0, 0.001)
	assert_almost_eq(arrow.rotation, Vector2(3, 4).angle(), 0.001)


func test_zero_direction_falls_back_to_right() -> void:
	arrow.launch(Vector2.ZERO)
	assert_eq(arrow.direction, Vector2.RIGHT)


func test_lifetime_expiry_queues_arrow_for_deletion() -> void:
	arrow._remaining_lifetime_seconds = 0.1
	arrow.launch(Vector2.RIGHT)
	arrow._physics_process(0.1)
	assert_true(arrow.is_queued_for_deletion())


func test_enemy_collision_reports_one_target_then_queues_arrow() -> void:
	var enemy: Enemy = double(Enemy).new()
	watch_signals(arrow)
	arrow.global_position = Vector2(7, 9)
	arrow._on_body_entered(enemy)
	arrow._on_body_entered(enemy)
	assert_signal_emit_count(arrow, &"hit_requested", 1)
	assert_signal_emitted_with_parameters(
		arrow,
		&"hit_requested",
		[[enemy], Vector2(7, 9)],
	)
	assert_true(arrow.is_queued_for_deletion())


func test_enemy_hitbox_child_resolves_to_enemy_owner() -> void:
	var enemy: Enemy = double(Enemy).new()
	var hitbox := StaticBody2D.new()
	enemy.add_child(hitbox)
	hitbox.add_to_group(&"enemy")
	watch_signals(arrow)
	arrow._on_body_entered(hitbox)
	assert_signal_emitted_with_parameters(
		arrow,
		&"hit_requested",
		[[enemy], arrow.global_position],
	)


func test_world_collision_removes_arrow_without_requesting_damage() -> void:
	var wall := StaticBody2D.new()
	autofree(wall)
	watch_signals(arrow)
	arrow._on_body_entered(wall)
	assert_signal_emit_count(arrow, &"hit_requested", 0)
	assert_true(arrow.is_queued_for_deletion())
