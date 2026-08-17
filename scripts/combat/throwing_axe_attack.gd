class_name ThrowingAxeAttack
extends WeaponAttackBehavior

## Aims one held axe and releases a detached projectile at the authored animation event.
## Requires Weapon, Muzzle, and AnimationPlayer children plus a ThrowingAxeProjectile scene.

@export var projectile_scene: PackedScene

@onready var weapon_sprite: Sprite2D = $Weapon
@onready var muzzle: Marker2D = $Muzzle
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _aim_direction := Vector2.RIGHT
var _attack_speed_scale := 1.0


func configure(data: WeaponData) -> void:
	weapon_sprite.texture = data.held_texture
	weapon_sprite.offset = data.grip_offset
	_attack_speed_scale = 0.5 / data.attack_interval_seconds


func aim(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		_aim_direction = direction.normalized()
	rotation = _aim_direction.angle()
	if _aim_direction.x < 0.0:
		scale.x = -1.0
		rotation_degrees += 180.0
	else:
		scale.x = 1.0


func start_attack() -> void:
	animation_player.stop()
	animation_player.speed_scale = _attack_speed_scale
	animation_player.play(&"throw")


func _throw_projectile() -> void:
	if projectile_scene == null:
		return
	var instance := projectile_scene.instantiate()
	if not instance is ThrowingAxeProjectile:
		instance.free()
		return
	var projectile := instance as ThrowingAxeProjectile
	var projectile_parent: Node = get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_tree().root
	projectile_parent.add_child(projectile)
	projectile.global_position = muzzle.global_position
	hit_source_spawned.emit(projectile)
	projectile.launch(_aim_direction)
	attack_committed.emit()
