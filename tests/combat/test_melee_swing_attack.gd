extends GutTest

const RUSTY_SWORD: WeaponData = preload(
	"res://resources/items/weapons/rusty_sword.tres"
)

var behavior: MeleeSwingAttack


func before_each() -> void:
	behavior = RUSTY_SWORD.attack_behavior_scene.instantiate()
	add_child_autofree(behavior)
	behavior.configure(RUSTY_SWORD)


func test_scene_preserves_authored_presentation_and_hitbox() -> void:
	assert_eq(behavior.position, Vector2(0, 3))
	assert_almost_eq(behavior.weapon_sprite.rotation, 1.5707964, 0.0001)
	assert_eq(behavior.weapon_sprite.offset, Vector2(0, -10))
	assert_eq(behavior.swing.position, Vector2(0, -3))
	assert_eq(behavior.swing.offset, Vector2(20, 0))
	assert_false(behavior.swing.visible)
	assert_eq(behavior.hitbox.collision_mask, 4)
	var polygon := behavior.hitbox.get_node("CollisionPolygon2D") as CollisionPolygon2D
	assert_eq(polygon.position, Vector2(0, 3))
	assert_eq(
		polygon.polygon,
		PackedVector2Array([
			Vector2(0, -3),
			Vector2(15, -30),
			Vector2(25, -28),
			Vector2(32, -17),
			Vector2(36, -3),
			Vector2(32, 10),
			Vector2(25, 21),
			Vector2(15, 23),
		]),
	)


func test_swing_preserves_timing_and_single_hit_event() -> void:
	var animation := behavior.animation_player.get_animation(&"swing")
	assert_almost_eq(animation.length, 0.7, 0.0001)
	var hit_times: Array[float] = []
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in animation.track_get_key_count(track_index):
			var value: Dictionary = animation.track_get_key_value(track_index, key_index)
			if value.get("method", &"") == &"_request_hit":
				hit_times.append(animation.track_get_key_time(track_index, key_index))
	assert_eq(hit_times.size(), 1)
	assert_almost_eq(hit_times[0], 1.0 / 6.0, 0.0001)


func test_aim_preserves_right_and_left_facing_rules() -> void:
	behavior.aim(Vector2.RIGHT)
	assert_eq(behavior.scale.x, 1.0)
	assert_almost_eq(behavior.rotation, 0.0, 0.001)
	behavior.aim(Vector2.LEFT)
	assert_eq(behavior.scale.x, -1.0)
	assert_almost_eq(behavior.rotation, PI * 2.0, 0.001)


func test_hit_request_snapshots_targets_and_source_position() -> void:
	var enemy: Enemy = double(Enemy).new()
	behavior.enemies_in_range.append(enemy)
	watch_signals(behavior)
	behavior._request_hit()
	assert_signal_emit_count(behavior, &"hit_requested", 1)
	assert_signal_emitted_with_parameters(
		behavior,
		&"hit_requested",
		[[enemy], behavior.hitbox.global_position],
	)
