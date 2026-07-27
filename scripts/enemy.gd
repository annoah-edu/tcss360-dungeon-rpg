extends CharacterBody2D

@export var speed: float = 80.0
@export var wander_radius: float = 300.0
@export var min_wait: float = 2.0
@export var max_wait: float = 3.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D

var start_position: Vector2
var is_waiting: bool = false

func _ready() -> void:
	start_position = global_position
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
