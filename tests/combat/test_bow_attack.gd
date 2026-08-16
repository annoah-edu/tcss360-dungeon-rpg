extends GutTest

const BOW: WeaponData = preload("res://resources/items/weapons/bow.tres")

var behavior: BowAttack
var spawned_projectile: WeaponHitSource


func before_each() -> void:
	behavior = BOW.attack_behavior_scene.instantiate()
	add_child_autofree(behavior)
	behavior.configure(BOW)
	behavior.hit_source_spawned.connect(_capture_projectile)


func test_scene_configures_bow_art_and_projectile_archetype() -> void:
	assert_eq(behavior.position, Vector2(0, 3))
	assert_same(behavior.rest_bow.texture, BOW.held_texture)
	assert_eq(behavior.rest_bow.offset, BOW.grip_offset)
	assert_true(behavior.rest_bow.visible)
	assert_false(behavior.drawn_bow.visible)
	assert_eq(
		behavior.drawn_bow.texture.resource_path,
		"res://Dungeon Tileset v1.7/frames/weapon_bow_2.png",
	)
	assert_eq(behavior.muzzle.position, Vector2(12, 0))
	assert_eq(
		behavior.projectile_scene.resource_path,
		"res://scenes/combat/arrow_projectile.tscn",
	)


func test_aim_preserves_right_and_left_facing_rules() -> void:
	behavior.aim(Vector2.RIGHT)
	assert_eq(behavior.scale.x, 1.0)
	assert_almost_eq(behavior.rotation, 0.0, 0.001)
	behavior.aim(Vector2.LEFT)
	assert_eq(behavior.scale.x, -1.0)
	assert_almost_eq(behavior.rotation, PI * 2.0, 0.001)


func test_start_attack_uses_interval_scaled_fire_animation() -> void:
	behavior.start_attack()
	assert_eq(behavior.animation_player.current_animation, &"fire")
	assert_almost_eq(behavior.animation_player.speed_scale, 0.5 / 0.8, 0.0001)


func test_fire_animation_has_one_authored_release_event() -> void:
	var animation := behavior.animation_player.get_animation(&"fire")
	var release_times: Array[float] = []
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in animation.track_get_key_count(track_index):
			var value: Dictionary = animation.track_get_key_value(track_index, key_index)
			if value.get("method", &"") == &"_fire_projectile":
				release_times.append(animation.track_get_key_time(track_index, key_index))
	assert_eq(release_times.size(), 1)
	assert_almost_eq(release_times[0], 0.2, 0.0001)


func test_animation_reaches_release_and_returns_to_rest() -> void:
	behavior.animation_player.method_call_mode = AnimationPlayer.ANIMATION_METHOD_CALL_IMMEDIATE
	behavior.start_attack()
	behavior.animation_player.advance(0.0)
	behavior.animation_player.advance(0.4)
	assert_not_null(spawned_projectile)
	if spawned_projectile != null:
		autofree(spawned_projectile)
	assert_true(behavior.rest_bow.visible)
	assert_false(behavior.drawn_bow.visible)


func test_authored_release_spawns_world_arrow_in_aim_direction() -> void:
	behavior.aim(Vector2(3, 4))
	behavior._fire_projectile()
	assert_not_null(spawned_projectile)
	if spawned_projectile == null:
		return
	autofree(spawned_projectile)
	var arrow := spawned_projectile as ArrowProjectile
	assert_eq(arrow.direction, Vector2(0.6, 0.8))
	assert_eq(arrow.global_position, behavior.muzzle.global_position)
	assert_ne(arrow.get_parent(), behavior)


func test_wrong_projectile_scene_fails_without_spawning_or_leaking() -> void:
	var malformed_scene := PackedScene.new()
	var ordinary_root := Node2D.new()
	malformed_scene.pack(ordinary_root)
	ordinary_root.free()
	behavior.projectile_scene = malformed_scene
	watch_signals(behavior)
	behavior._fire_projectile()
	assert_signal_emit_count(behavior, &"hit_source_spawned", 0)


func _capture_projectile(projectile: WeaponHitSource) -> void:
	spawned_projectile = projectile
