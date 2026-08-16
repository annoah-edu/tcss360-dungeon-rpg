class_name WeaponController
extends Node2D

## Owns equipped weapon data, the active attack behavior, cooldown, and damage application.
## The parent forwards input and world-space aim; behavior children own attack presentation.

var equipped_weapon: WeaponData
var active_behavior: WeaponAttackBehavior
var attack_cooldown_seconds: float = 0.0
var damage_rng := RandomNumberGenerator.new()
var _active_hit_callable: Callable
var _active_source_callable: Callable


func _ready() -> void:
	process_priority = -1
	damage_rng.randomize()


func _process(delta: float) -> void:
	attack_cooldown_seconds -= delta


## Replaces the equipped definition and behavior only when both are valid.
func equip_weapon(data: WeaponData) -> void:
	if data == null or not data.validation_errors().is_empty():
		return

	var instance := data.attack_behavior_scene.instantiate()
	if not instance is WeaponAttackBehavior:
		instance.free()
		return

	_remove_active_behavior()
	equipped_weapon = data
	active_behavior = instance as WeaponAttackBehavior
	add_child(active_behavior)
	active_behavior.configure(data)
	_active_hit_callable = _on_hit_requested.bind(data)
	_active_source_callable = _on_hit_source_spawned.bind(data)
	active_behavior.hit_requested.connect(_active_hit_callable)
	active_behavior.hit_source_spawned.connect(_active_source_callable)
	attack_cooldown_seconds = 0.0


## Updates the behavior's facing while the current attack cooldown is ready.
func aim_at(world_position: Vector2) -> void:
	if active_behavior == null or attack_cooldown_seconds > 0.0:
		return
	active_behavior.aim(world_position - active_behavior.global_position)


## Starts an attack when equipped and ready, returning whether it began.
func try_attack() -> bool:
	if (
		equipped_weapon == null
		or active_behavior == null
		or attack_cooldown_seconds > 0.0
	):
		return false
	active_behavior.start_attack()
	attack_cooldown_seconds = equipped_weapon.attack_interval_seconds
	return true


func _remove_active_behavior() -> void:
	if active_behavior == null:
		return
	if active_behavior.hit_requested.is_connected(_active_hit_callable):
		active_behavior.hit_requested.disconnect(_active_hit_callable)
	if active_behavior.hit_source_spawned.is_connected(_active_source_callable):
		active_behavior.hit_source_spawned.disconnect(_active_source_callable)
	active_behavior.free()
	active_behavior = null


func _on_hit_source_spawned(source: WeaponHitSource, weapon_data: WeaponData) -> void:
	if source == null:
		return
	source.hit_requested.connect(
		_on_hit_requested.bind(weapon_data),
		CONNECT_ONE_SHOT,
	)


func _on_hit_requested(
	targets: Array[Enemy],
	source_position: Vector2,
	weapon_data: WeaponData,
) -> void:
	if weapon_data == null:
		return
	for enemy in targets:
		if not is_instance_valid(enemy):
			continue
		var total_damage := roundi(
			weapon_data.base_damage
			* damage_rng.randf_range(
				1.0 - weapon_data.damage_variance,
				1.0 + weapon_data.damage_variance,
			)
		)
		enemy.take_damage(
			total_damage,
			source_position,
			weapon_data.knockback_strength,
		)
