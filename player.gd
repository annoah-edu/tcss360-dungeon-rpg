extends CharacterBody2D

const SPEED = 100.0

@export var atk_dmg: int = 1
@export var knockback_strength: int = 130
@export var atk_rate: float = 0.5
@export_range(1, 100, 1) var max_health: int = 3

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D # The visual character sprite
@onready var weapon: Node2D = $WeaponHandle # The weapon handle to rotate around the mouse
@onready var weapon_sprite: Sprite2D = $WeaponHandle/Weapon # The weapon sprite itself
@onready var anim_player: AnimationPlayer = $AnimationPlayer # The animation player handling weapon animations
@onready var swing: Sprite2D = $WeaponHandle/Swing # The swing effect
@onready var weapon_hitbox: Area2D = $WeaponHandle/Hitbox # The physics area that will poll for enemies

var x_direction: float
var y_direction: float
var atk_cooldown: float = 0
var enemies_in_range: Array[Enemy] # The array of enemies inside the physics area

func _ready() -> void:
	_hide_swing() # Hide the swinging sprite in case it wasn't hidden in-editor yet
	
	# Connect the weapon hitbox's signals to functions in this script
	weapon_hitbox.body_entered.connect(_enemy_entered.bind())
	weapon_hitbox.body_exited.connect(_enemy_exited.bind())

func _physics_process(_delta: float) -> void:
	_handle_movement()
	_handle_animations()
	if atk_cooldown <= 0:
		_handle_weapon_rotation()

func _process(delta: float) -> void:
	atk_cooldown -= delta
	_handle_attacking()


# Movement and rotation related functions


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


# Attack related functions


## Plays attacking animations when the player is attacking.
func _handle_attacking() -> void:
	if Input.is_action_pressed("attack") and atk_cooldown <= 0:
		_handle_weapon_rotation()
		
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

## Adds an enemy to the array of enemies in range. I typecast the body to the Enemy class for the IDE so we can get things like autocompletion.
func _enemy_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		enemies_in_range.append(body.get_parent() as Enemy)

## Removes an enemy in the array of enemies in range.
func _enemy_exited(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		enemies_in_range.erase(body.get_parent() as Enemy)

## Damages enemies inside the current weapon's range by looping over the array of enemies.
func _damage_enemies() -> void:
	for enemy in enemies_in_range:
		enemy.take_damage(atk_dmg, weapon_hitbox.global_position, knockback_strength)
