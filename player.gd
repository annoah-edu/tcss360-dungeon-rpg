extends CharacterBody2D

const SPEED = 100.0
const WEAPON_OFFSET = 15

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon: Sprite2D = $Weapon

var x_direction: float
var y_direction: float

func _physics_process(_delta: float) -> void:
	_handle_movement()
	_handle_animations()
	_handle_weapon_rotation()

func _handle_movement() -> void:
	# Get x input and apply
	x_direction = Input.get_axis("move left", "move right")
	if x_direction:
		velocity.x = x_direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	# Flip the sprite if necessary
	if not x_direction == 0:
		if x_direction < 0:
			sprite.flip_h = true
		else:
			sprite.flip_h = false
	
	# Get y input and apply
	y_direction = Input.get_axis("move up", "move down")
	if y_direction:
		velocity.y = y_direction * SPEED
	else:
		velocity.y = move_toward(velocity.y, 0, SPEED)
	
	move_and_slide()

func _handle_animations() -> void:
	if x_direction == 0 and y_direction == 0:
		sprite.play("idle")
	else:
		sprite.play("moving")

func _handle_weapon_rotation() -> void:
	var mouse_position: Vector2 = get_global_mouse_position()
	weapon.global_position = global_position
	weapon.look_at(mouse_position)
	weapon.global_position += weapon.transform.x * WEAPON_OFFSET
	
	if mouse_position.x < global_position.x:
		weapon.flip_v = true
	else:
		weapon.flip_v = false
