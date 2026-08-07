extends CharacterBody2D
class_name Enemy

@export var los_radius: int = 75
@export var max_health: int = 100
@export var knockback_recovery_spd: int = 500
@export var speed: float = 80.0

@export var wander_radius: float = 300.0
@export var min_wait: float = 2.0
@export var max_wait: float = 3.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D
@onready var healthbar: TextureProgressBar = $HealthBar
@onready var damage_number: PackedScene = preload("res://scenes/effects/damage_number.tscn")

var health: int

var is_waiting: bool = false
var knockback_velocity: Vector2 = Vector2.ZERO # Used on top of navigation to apply knockback
var found_player: bool = false # Not associated with line of sight. Will chase the player once attacked permanently
var _is_configured := false

## Apply database-owned archetype data before this enemy enters the scene tree.
func apply_definition(definition: EnemyDefinition) -> void:
	if is_inside_tree():
		push_error("Enemy definitions must be applied before add_child()")
		return
	if definition == null or not definition.is_valid():
		push_error("Enemy received an invalid definition")
		return
	max_health = definition.max_health
	speed = definition.movement_speed
	los_radius = definition.sight_radius
	knockback_recovery_spd = definition.knockback_recovery_speed
	wander_radius = definition.wander_radius
	min_wait = definition.minimum_wait
	max_wait = definition.maximum_wait
	_is_configured = true

func _ready() -> void:
	if not _is_configured:
		push_error("Enemy entered the scene tree without a database definition")
		set_physics_process(false)
		set_process(false)
		return
	health = max_health

	# Hide the healthbar initially, and set its max value
	healthbar.visible = false
	healthbar.max_value = max_health

	# Start the navigation
	nav_agent.path_desired_distance = 5.0
	nav_agent.target_desired_distance = 10.0
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

	# Chase the player when close enough. If idling, don't update navigation
	if global_position.distance_to(GameState.player.global_position) < los_radius or found_player:
		nav_agent.target_position = GameState.player.global_position
		animation.play("moving")
	elif is_waiting:
		return
	elif nav_agent.is_navigation_finished(): # If the navigation path is finished, find a new target position
		_wait_then_pick_new_target()
		return

	# Determine the next point in the navigation path, and move there
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = global_position.direction_to(next_point)
	nav_agent.set_velocity(direction * speed)


func _process(delta: float) -> void:
	animation.modulate = animation.modulate.lerp(Color.WHITE, delta * 10) # Smooth the color modulation back to pure white


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
	# Create a damage number
	var damage_popup: DamageNumber = damage_number.instantiate()
	damage_popup.popup_text = str(amount)
	var sprite_height := animation.sprite_frames.get_frame_texture("idle", 0).get_height()
	damage_popup.global_position = global_position - Vector2(0, sprite_height / 2.0)
	get_tree().current_scene.add_child(damage_popup)

	health -= amount
	if health <= 0:
		queue_free()
		return

	# Knockback
	var direction: Vector2 = (global_position - source).normalized()
	knockback_velocity = direction * knockback_strength

	# Visibly flash red
	healthbar.visible = true
	healthbar.value = health
	animation.modulate = Color.RED

	found_player = true # Target the player after taking damage
