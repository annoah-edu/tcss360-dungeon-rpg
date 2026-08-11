extends CharacterBody2D
class_name Player

const SPEED = 100.0

@export var max_health: int = 200
@export var atk_dmg: int = 34
@export var knockback_strength: int = 150
@export var atk_rate: float = 0.5

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D # The visual character sprite
@onready var weapon: Node2D = $WeaponHandle # The weapon handle to rotate around the mouse
@onready var weapon_sprite: Sprite2D = $WeaponHandle/Weapon # The weapon sprite itself
@onready var anim_player: AnimationPlayer = $AnimationPlayer # The animation player handling weapon animations
@onready var swing: Sprite2D = $WeaponHandle/Swing # The swing effect
@onready var weapon_hitbox: Area2D = $WeaponHandle/Hitbox # The physics area that will poll for enemies
@onready var healthbar: TextureProgressBar = $HealthBar # The healthbar
@onready var damage_number: PackedScene = preload("res://scenes/effects/damage_number.tscn") # The damage number popup

var x_direction: float
var y_direction: float
var velocity_vector: Vector2
var health: int
var atk_cooldown: float = 0
var enemies_in_range: Array[Enemy] # The array of enemies inside the physics area

func _ready() -> void:
	health = max_health
	_hide_swing() # Hide the swinging sprite in case it wasn't hidden in-editor yet
	
	# Hide the healthbar initially, and set its max value
	healthbar.visible = false
	healthbar.max_value = max_health
	
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
	
	sprite.modulate = sprite.modulate.lerp(Color.WHITE, delta * 5) # Smooth the color modulation back to pure white


# Movement and rotation related functions


## Uses the CharacterController and input axis to apply movement. Also flips the Sprite when moving backwards.
func _handle_movement() -> void:
	# Get x input and apply
	x_direction = Input.get_axis("move left", "move right")
	if x_direction:
		velocity_vector.x = x_direction
	else:
		velocity_vector.x = move_toward(velocity_vector.x, 0, SPEED)
	
	# Flip the sprite if necessary
	if not x_direction == 0:
		if x_direction < 0:
			sprite.flip_h = true
		else:
			sprite.flip_h = false
	
	# Get y input and apply
	y_direction = Input.get_axis("move up", "move down")
	if y_direction:
		velocity_vector.y = y_direction
	else:
		velocity_vector.y = move_toward(velocity_vector.y, 0, SPEED)
	
	velocity = velocity_vector.normalized() * SPEED
	move_and_slide()

## Uses input axis to determine whether the player's animation should be moving or not.
func _handle_animations() -> void:
	if x_direction == 0 and y_direction == 0:
		sprite.play("idle")
	else:
		sprite.play("moving")

## Rotates the weapon to face the mouse.
func _handle_weapon_rotation() -> void:
	var direction: Vector2 = get_global_mouse_position() - weapon.global_position
	_apply_weapon_facing(direction)

## Rotates the weapon to face a position. Uses scale to flip the weapon in order to keep animations upright.
func _apply_weapon_facing(direction: Vector2) -> void:
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
		var total_damage: int = round(atk_dmg * randf_range(0.80, 1.20)) # 20% random damage deviation per attack
		enemy.take_damage(total_damage, weapon_hitbox.global_position, knockback_strength)

## Takes a specified amount of damage, and dies if health is below 0
func take_damage(amount: int) -> void:
	# Create a damage number
	var damage_popup: DamageNumber = damage_number.instantiate()
	damage_popup.text_label = str(amount)
	damage_popup.text_color = Color.RED
	damage_popup.global_position = global_position - Vector2(0, sprite.sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0)
	get_tree().current_scene.add_child(damage_popup)
	
	health -= amount
	if health <= 0:
		var camera: Camera2D = find_child("Camera2D")
		if camera:
			camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # Disable interpolation to prevent weird snapping when reparenting
			camera.reparent(get_tree().current_scene)
		queue_free()
		return
	
	# Visibly flash red
	healthbar.visible = true
	healthbar.value = health
	sprite.modulate = Color.RED
