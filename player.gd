extends CharacterBody2D

const SPEED = 100.0

@export var atk_rate: float = 0.5

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon: Node2D = $WeaponHandle
@onready var weapon_sprite: Sprite2D = $WeaponHandle/Weapon
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var swing: Sprite2D = $WeaponHandle/Swing

var x_direction: float
var y_direction: float
var atk_cooldown: float = 0

func _ready() -> void:
	_hide_swing()

func _physics_process(_delta: float) -> void:
	_handle_movement()
	_handle_animations()
	_handle_weapon_rotation()

func _process(delta: float) -> void:
	atk_cooldown -= delta
	_handle_attacking()

## Uses the CharacterController and input axis to apply movement. Also flips the Sprite when moving backwards.
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

## Uses input axis to determine whether the player's animation should be moving or not.
func _handle_animations() -> void:
	if x_direction == 0 and y_direction == 0:
		sprite.play("idle")
	else:
		sprite.play("moving")

## Rotates the weapon to face the mouse. Uses scale to flip the weapon in order to keep animations upright.
func _handle_weapon_rotation() -> void:
	var direction: Vector2 = get_global_mouse_position() - weapon.global_position
	weapon.rotation = direction.angle()
	if direction.x < 0:
		weapon.scale.x = -1
		weapon.rotation_degrees += 180
	else:
		weapon.scale.x = 1

## Plays attacking animations when the player is attacking.
func _handle_attacking() -> void:
	if Input.is_action_pressed("attack") and atk_cooldown <= 0:
		anim_player.stop()
		anim_player.speed_scale = 0.5 / atk_rate
		anim_player.play("swing")
		atk_cooldown = atk_rate

## Shows the swing effect.
func _show_swing() -> void:
	swing.visible = true
	swing.position = weapon_sprite.position
	swing.rotation = weapon_sprite.rotation + PI * 1.15

## Hides the swing effect.
func _hide_swing() -> void:
	swing.visible = false
