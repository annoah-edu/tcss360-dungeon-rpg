class_name BowAttack
extends WeaponAttackBehavior

## Presents an aimed bow draw and spawns one detached arrow at the authored release time.
## Requires RestBow, DrawnBow, Muzzle, and AnimationPlayer children plus a projectile scene.

@export var projectile_scene: PackedScene

@onready var rest_bow: Sprite2D = $RestBow
@onready var drawn_bow: Sprite2D = $DrawnBow
@onready var muzzle: Marker2D = $Muzzle
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _aim_direction := Vector2.RIGHT
var _attack_speed_scale := 1.0


func _ready() -> void:
	_show_rest()


func configure(data: WeaponData) -> void:
	rest_bow.texture = data.held_texture
	rest_bow.offset = data.grip_offset
	drawn_bow.offset = data.grip_offset
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
	animation_player.play(&"fire")


func _show_drawn() -> void:
	rest_bow.visible = false
	drawn_bow.visible = true


func _show_rest() -> void:
	rest_bow.visible = true
	drawn_bow.visible = false


func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	var instance := projectile_scene.instantiate()
	if not instance is ArrowProjectile:
		instance.free()
		return
	var projectile := instance as ArrowProjectile
	var projectile_parent: Node = get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_tree().root
	projectile_parent.add_child(projectile)
	projectile.global_position = muzzle.global_position
	hit_source_spawned.emit(projectile)
	projectile.launch(_aim_direction)
