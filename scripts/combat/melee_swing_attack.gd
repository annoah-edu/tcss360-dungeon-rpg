class_name MeleeSwingAttack
extends WeaponAttackBehavior

@onready var weapon_sprite: Sprite2D = $Weapon
@onready var swing: Sprite2D = $Swing
@onready var hitbox: Area2D = $Hitbox
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var enemies_in_range: Array[Enemy] = []
var _attack_speed_scale: float = 1.0


func _ready() -> void:
	_hide_swing()
	hitbox.body_entered.connect(_enemy_entered)
	hitbox.body_exited.connect(_enemy_exited)


func configure(data: WeaponData) -> void:
	weapon_sprite.texture = data.held_texture
	weapon_sprite.offset = data.grip_offset
	_attack_speed_scale = 0.5 / data.attack_interval_seconds


func aim(direction: Vector2) -> void:
	rotation = direction.angle()
	if direction.x < 0:
		scale.x = -1
		rotation_degrees += 180
	else:
		scale.x = 1


func start_attack() -> void:
	animation_player.stop()
	animation_player.speed_scale = _attack_speed_scale
	animation_player.play(&"swing")


func _show_swing() -> void:
	swing.visible = true
	swing.position = weapon_sprite.position
	swing.rotation = weapon_sprite.rotation + PI * 1.15


func _hide_swing() -> void:
	swing.visible = false


func _enemy_entered(body: Node2D) -> void:
	if not body.is_in_group(&"enemy"):
		return
	var enemy := body.get_parent() as Enemy
	if enemy != null and not enemies_in_range.has(enemy):
		enemies_in_range.append(enemy)


func _enemy_exited(body: Node2D) -> void:
	if body.is_in_group(&"enemy"):
		enemies_in_range.erase(body.get_parent() as Enemy)


func _request_hit() -> void:
	var targets: Array[Enemy] = enemies_in_range.duplicate()
	hit_requested.emit(targets, hitbox.global_position)
