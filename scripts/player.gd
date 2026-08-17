extends CharacterBody2D
class_name Player

const SPEED = 100.0

@export var max_health: int = 200
@export var starting_weapon: WeaponData

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D # The visual character sprite
@onready var healthbar: TextureProgressBar = $HealthBar # The healthbar
@onready var damage_number: PackedScene = preload("res://scenes/effects/damage_number.tscn") # The damage number popup
@onready var inventory_ui: InventoryUI = $InventoryUI
@onready var weapon_controller: WeaponController = $WeaponController

var x_direction: float
var y_direction: float
var velocity_vector: Vector2
var health: int
var inventory: InventoryData
var nearby_chests: Array[Chest] = []
var weapon_equipment: WeaponEquipment

func _ready() -> void:
	inventory = InventoryData.new(6)
	weapon_equipment = WeaponEquipment.new(starting_weapon)
	weapon_equipment.equipped_weapon_changed.connect(_on_equipped_weapon_changed)
	weapon_controller.weapon_consumed.connect(_on_weapon_consumed)
	weapon_controller.equip_weapon(weapon_equipment.equipped_weapon)
	inventory_ui.bind_player(inventory, weapon_equipment)
	health = max_health
	
	# Hide the healthbar initially, and set its max value
	healthbar.visible = false
	healthbar.max_value = max_health
	
func _physics_process(_delta: float) -> void:
	if inventory_ui.is_open():
		x_direction = 0.0
		y_direction = 0.0
		velocity_vector = Vector2.ZERO
		velocity = Vector2.ZERO
		move_and_slide()
		_handle_animations()
		return
	_handle_movement()
	_handle_animations()
	weapon_controller.aim_at(get_global_mouse_position())

func _process(delta: float) -> void:
	if not inventory_ui.is_open() and Input.is_action_pressed("attack"):
		weapon_controller.try_attack()
	
	sprite.modulate = sprite.modulate.lerp(Color.WHITE, delta * 5) # Smooth the color modulation back to pure white


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		inventory_ui.toggle_player(inventory)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		var chest := _nearest_chest()
		if chest != null:
			inventory_ui.toggle_chest(inventory, chest)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and inventory_ui.is_open():
		inventory_ui.close()
		get_viewport().set_input_as_handled()


func enter_chest_range(chest: Chest) -> void:
	if chest != null and not nearby_chests.has(chest):
		nearby_chests.append(chest)


func exit_chest_range(chest: Chest) -> void:
	nearby_chests.erase(chest)
	if inventory_ui.active_chest == chest:
		inventory_ui.close()


func _nearest_chest() -> Chest:
	var nearest: Chest
	var nearest_distance := INF
	for chest in nearby_chests:
		if not is_instance_valid(chest):
			continue
		var distance := global_position.distance_squared_to(chest.global_position)
		if distance < nearest_distance:
			nearest = chest
			nearest_distance = distance
	return nearest


# Movement related functions


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

func _on_equipped_weapon_changed(_previous: WeaponData, current: WeaponData) -> void:
	if current == null:
		weapon_controller.clear_weapon(_previous)
	else:
		weapon_controller.equip_weapon(current)


func _on_weapon_consumed(weapon: WeaponData) -> void:
	weapon_equipment.consume_if_equipped(weapon)

## Takes a specified amount of damage, and dies if health is below 0
func take_damage(amount: int) -> void:
	# Create a damage number
	var damage_popup: DamageNumber = damage_number.instantiate()
	damage_popup.text_label = str(amount)
	damage_popup.text_color = Color.CRIMSON
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
