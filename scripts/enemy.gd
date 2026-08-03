extends CharacterBody2D
class_name Enemy

@export var max_health: int = 3
@export var knockback_recovery_spd: int = 500
@export var speed: float = 80.0

@export var wander_radius: float = 300.0
@export var min_wait: float = 2.0
@export var max_wait: float = 3.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D
@onready var healthbar: TextureProgressBar = $HealthBar

var health: int

var start_position: Vector2
var is_waiting: bool = false
var knockback_velocity: Vector2 = Vector2.ZERO # Used on top of navigation to apply knockback

func _ready() -> void:
	health = max_health
	
	# Hide the healthbar initially, and set its max value
	healthbar.visible = false
	healthbar.max_value = max_health
	
	# Start the navigation
	start_position = global_position
	health = max_health
	nav_agent.path_desired_distance = 5.0
	nav_agent.target_desired_distance = 5.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	await get_tree().physics_frame
	_pick_new_target()

func _physics_process(delta: float) -> void:
	# Apply knockback first before navigation
	if knockback_velocity.length() > 1.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * knockback_recovery_spd)
		move_and_slide()
		return
	
	# If idling, don't update navigation
	if is_waiting:
		return
	
	# If the navigation path is finished, find a new target position
	if nav_agent.is_navigation_finished():
		_wait_then_pick_new_target()
		return
	
	# Determine the next point in the navigation path, and move there
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = global_position.direction_to(next_point)
	nav_agent.set_velocity(direction * speed)


func _process(delta: float) -> void:
	animation.modulate = animation.modulate.lerp(Color.WHITE, delta * 10)

# Navigation and pathfinding functions


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	if velocity.x < -0.2:
		animation.flip_h = true
	elif velocity.x > 0.2:
		animation.flip_h = false
	move_and_slide()

## Stops moving, waits a random amount of time, then pathfinds somewhere else.
func _wait_then_pick_new_target() -> void:
	is_waiting = true
	animation.play("idle")
	velocity = Vector2.ZERO
	await get_tree().create_timer(randf_range(min_wait, max_wait)).timeout
	is_waiting = false
	_pick_new_target()

## Picks a new target within a specified range, and sets the navigation agent's goal to that
func _pick_new_target() -> void:
	var random_offset := Vector2(
		randf_range(-wander_radius, wander_radius),
		randf_range(-wander_radius, wander_radius)
	)
	nav_agent.target_position = global_position + random_offset
	animation.play("moving")


# Attacking and damage functions

## Takes a specified amount of damage, and dies if health is below 0
func take_damage(amount: int, source: Vector2, knockback_strength: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()
		return
	
	var direction: Vector2 = (global_position - source).normalized()
	knockback_velocity = direction * knockback_strength
	
	healthbar.visible = true
	healthbar.value = health
	animation.modulate = Color.RED
