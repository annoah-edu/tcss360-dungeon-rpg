extends CharacterBody2D

@export var speed: float = 80.0
@export var wander_radius: float = 300.0
@export var min_wait: float = 2.0
@export var max_wait: float = 3.0
@export_range(1, 100, 1) var max_health: int = 3

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: Line2D = $HealthBar

const HIT_JUMP_HEIGHT := 4.0
const HIT_JUMP_UP_TIME := 0.08
const HIT_JUMP_DOWN_TIME := 0.12
const HIT_FLASH_COLOR := Color(1.0, 0.2, 0.2, 1.0)
const HIT_FLASH_IN_TIME := 0.04
const HIT_FLASH_OUT_TIME := 0.12

var start_position: Vector2
var is_waiting: bool = false
var health: int
var hit_tween: Tween
var hit_flash_tween: Tween
var sprite_rest_position: Vector2
var sprite_rest_modulate: Color
var health_bar_full_width: float

func _ready() -> void:
	start_position = global_position
	sprite_rest_position = animation.position
	sprite_rest_modulate = animation.modulate
	health = max_health
	health_bar_full_width = health_bar.get_point_position(1).x
	nav_agent.path_desired_distance = 5.0
	nav_agent.target_desired_distance = 5.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	await get_tree().physics_frame
	_pick_new_target()

func _physics_process(_delta: float) -> void:
	if is_waiting:
		return

	if nav_agent.is_navigation_finished():
		_wait_then_pick_new_target()
		return

	var next_point: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = global_position.direction_to(next_point)
	nav_agent.set_velocity(direction * speed)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	if velocity.x < -0.2:
		animation.flip_h = true
	elif velocity.x > 0.2:
		animation.flip_h = false
	move_and_slide()

func _wait_then_pick_new_target() -> void:
	is_waiting = true
	animation.play("idle")
	velocity = Vector2.ZERO
	await get_tree().create_timer(randf_range(min_wait, max_wait)).timeout
	is_waiting = false
	_pick_new_target()

func _pick_new_target() -> void:
	var random_offset := Vector2(
		randf_range(-wander_radius, wander_radius),
		randf_range(-wander_radius, wander_radius)
	)
	nav_agent.target_position = global_position + random_offset
	animation.play("moving")

## Reduces health, updates the health bar, and removes the enemy at zero health.
func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0:
		return

	health = maxi(health - amount, 0)
	_update_health_bar()
	if health == 0:
		queue_free()
		return

	react_to_hit()

func _update_health_bar() -> void:
	var health_ratio := float(health) / float(max_health)
	health_bar.set_point_position(1, Vector2(health_bar_full_width * health_ratio, 0.0))

## Gives immediate visual feedback when an attack connects without disturbing
## navigation or the enemy's physical position.
func react_to_hit() -> void:
	if hit_tween != null and hit_tween.is_valid():
		hit_tween.kill()
	if hit_flash_tween != null and hit_flash_tween.is_valid():
		hit_flash_tween.kill()
	animation.position = sprite_rest_position
	animation.modulate = sprite_rest_modulate

	hit_tween = create_tween()
	hit_tween.set_trans(Tween.TRANS_QUAD)
	hit_tween.set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(
		animation,
		"position",
		sprite_rest_position + Vector2.UP * HIT_JUMP_HEIGHT,
		HIT_JUMP_UP_TIME
	)
	hit_tween.set_ease(Tween.EASE_IN)
	hit_tween.tween_property(
		animation,
		"position",
		sprite_rest_position,
		HIT_JUMP_DOWN_TIME
	)

	hit_flash_tween = create_tween()
	hit_flash_tween.tween_property(
		animation,
		"modulate",
		HIT_FLASH_COLOR,
		HIT_FLASH_IN_TIME
	)
	hit_flash_tween.tween_property(
		animation,
		"modulate",
		sprite_rest_modulate,
		HIT_FLASH_OUT_TIME
	)
