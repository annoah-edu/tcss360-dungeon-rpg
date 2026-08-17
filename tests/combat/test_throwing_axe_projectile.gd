extends GutTest

var projectile: ThrowingAxeProjectile


func before_each() -> void:
	projectile = preload(
		"res://scenes/combat/throwing_axe_projectile.tscn"
	).instantiate()
	add_child_autofree(projectile)


func test_scene_uses_axe_art_world_collision_and_heavy_projectile_tuning() -> void:
	assert_almost_eq(projectile.speed_pixels_per_second, 200.0, 0.0001)
	assert_almost_eq(projectile.lifetime_seconds, 2.0, 0.0001)
	assert_almost_eq(projectile.spin_radians_per_second, TAU * 3.0, 0.0001)
	assert_eq(projectile.hit_detection.collision_layer, 0)
	assert_eq(projectile.hit_detection.collision_mask, 5)
	var sprite := projectile.get_node("Sprite2D") as Sprite2D
	assert_eq(
		sprite.texture.resource_path,
		"res://Dungeon Tileset v1.7/frames/weapon_throwing_axe.png",
	)
	var shape := projectile.hit_detection.get_node("CollisionShape2D") as CollisionShape2D
	assert_eq((shape.shape as RectangleShape2D).size, Vector2(10, 10))


func test_launch_moves_and_spins_in_world_space() -> void:
	projectile.global_position = Vector2(10, 20)
	projectile.launch(Vector2.RIGHT)
	projectile._physics_process(0.25)

	assert_eq(projectile.global_position, Vector2(60, 20))
	assert_almost_eq(projectile.rotation, TAU * 3.0 * 0.25, 0.001)


func test_first_enemy_collision_reports_hit_and_removes_projectile() -> void:
	var enemy: Enemy = double(Enemy).new()
	watch_signals(projectile)
	projectile.global_position = Vector2(8, 13)

	projectile._on_body_entered(enemy)
	projectile._on_body_entered(enemy)

	assert_signal_emitted_with_parameters(
		projectile,
		&"hit_requested",
		[[enemy], Vector2(8, 13)],
	)
	assert_signal_emit_count(projectile, &"hit_requested", 1)
	assert_true(projectile.is_queued_for_deletion())
