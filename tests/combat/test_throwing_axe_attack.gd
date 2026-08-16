extends GutTest

const THROWING_AXE: WeaponData = preload(
	"res://resources/items/weapons/throwing_axe.tres"
)

var behavior: ThrowingAxeAttack
var spawned_projectile: WeaponHitSource


func before_each() -> void:
	behavior = THROWING_AXE.attack_behavior_scene.instantiate()
	add_child_autofree(behavior)
	behavior.configure(THROWING_AXE)
	behavior.hit_source_spawned.connect(_capture_projectile)


func test_scene_configures_single_use_axe_art_and_projectile() -> void:
	assert_true(THROWING_AXE.consumed_on_attack)
	assert_eq(THROWING_AXE.base_damage, 100)
	assert_same(behavior.weapon_sprite.texture, THROWING_AXE.held_texture)
	assert_eq(behavior.weapon_sprite.offset, THROWING_AXE.grip_offset)
	assert_eq(behavior.muzzle.position, Vector2(10, 0))
	assert_eq(
		behavior.projectile_scene.resource_path,
		"res://scenes/combat/throwing_axe_projectile.tscn",
	)


func test_authored_animation_release_spawns_one_projectile_then_commits_use() -> void:
	behavior.aim(Vector2(3, 4))
	behavior.animation_player.method_call_mode = AnimationPlayer.ANIMATION_METHOD_CALL_IMMEDIATE
	watch_signals(behavior)

	behavior.start_attack()
	behavior.animation_player.advance(0.0)
	behavior.animation_player.advance(0.25)

	assert_not_null(spawned_projectile)
	if spawned_projectile == null:
		return
	autofree(spawned_projectile)
	var projectile := spawned_projectile as ThrowingAxeProjectile
	assert_eq(projectile.direction, Vector2(0.6, 0.8))
	assert_eq(projectile.global_position, behavior.muzzle.global_position)
	assert_ne(projectile.get_parent(), behavior)
	assert_signal_emit_count(behavior, &"hit_source_spawned", 1)
	assert_signal_emit_count(behavior, &"attack_committed", 1)


func test_malformed_projectile_does_not_commit_or_consume_use() -> void:
	var malformed_scene := PackedScene.new()
	var ordinary_root := Node2D.new()
	malformed_scene.pack(ordinary_root)
	ordinary_root.free()
	behavior.projectile_scene = malformed_scene
	watch_signals(behavior)

	behavior._throw_projectile()

	assert_signal_emit_count(behavior, &"hit_source_spawned", 0)
	assert_signal_emit_count(behavior, &"attack_committed", 0)


func _capture_projectile(projectile: WeaponHitSource) -> void:
	spawned_projectile = projectile
