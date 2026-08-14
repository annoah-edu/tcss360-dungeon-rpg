class_name WeaponController
extends Node2D

var equipped_weapon: WeaponData
var active_behavior: WeaponAttackBehavior
var attack_cooldown_seconds: float = 0.0
var damage_rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = -1
	damage_rng.randomize()


func _process(delta: float) -> void:
	attack_cooldown_seconds -= delta


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
	active_behavior.hit_requested.connect(_on_hit_requested)
	attack_cooldown_seconds = 0.0


func aim_at(world_position: Vector2) -> void:
	if active_behavior == null or attack_cooldown_seconds > 0.0:
		return
	active_behavior.aim(world_position - active_behavior.global_position)


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
	if active_behavior.hit_requested.is_connected(_on_hit_requested):
		active_behavior.hit_requested.disconnect(_on_hit_requested)
	active_behavior.free()
	active_behavior = null


func _on_hit_requested(targets: Array[Enemy], source_position: Vector2) -> void:
	if equipped_weapon == null:
		return
	for enemy in targets:
		if not is_instance_valid(enemy):
			continue
		var total_damage := roundi(
			equipped_weapon.base_damage
			* damage_rng.randf_range(
				1.0 - equipped_weapon.damage_variance,
				1.0 + equipped_weapon.damage_variance,
			)
		)
		enemy.take_damage(
			total_damage,
			source_position,
			equipped_weapon.knockback_strength,
		)
