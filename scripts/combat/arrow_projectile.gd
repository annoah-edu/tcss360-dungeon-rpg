class_name ArrowProjectile
extends WeaponHitSource

## Moves one arrow through world space and reports its first enemy collision.
## Requires Sprite2D, HitDetection/CollisionShape2D, and no authoritative weapon statistics.

@export var speed_pixels_per_second: float = 240.0
@export var lifetime_seconds: float = 2.0

@onready var hit_detection: Area2D = $HitDetection

var direction: Vector2 = Vector2.RIGHT
var _remaining_lifetime_seconds: float
var _has_collided := false


func _ready() -> void:
	_remaining_lifetime_seconds = lifetime_seconds
	hit_detection.body_entered.connect(_on_body_entered)
	set_physics_process(false)


## Starts the arrow along a normalized world-space direction.
func launch(world_direction: Vector2) -> void:
	direction = world_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	rotation = direction.angle()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	global_position += direction * speed_pixels_per_second * delta
	_remaining_lifetime_seconds -= delta
	if _remaining_lifetime_seconds <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _has_collided:
		return
	_has_collided = true
	hit_detection.set_deferred(&"monitoring", false)
	var enemy := _enemy_from_body(body)
	if enemy != null:
		hit_requested.emit([enemy] as Array[Enemy], global_position)
	queue_free()


func _enemy_from_body(body: Node2D) -> Enemy:
	if body is Enemy:
		return body as Enemy
	if body.is_in_group(&"enemy"):
		return body.get_parent() as Enemy
	return null
