class_name Player
extends CharacterBody2D

## Owns player movement, health, inventory, equipment, pillar progress, and run lifecycle hooks.
## WeaponController owns combat execution; this node forwards aim and attack input only while the
## inventory UI is closed.

const SPEED := 100.0
const RUN_SUMMARY_SCENE := "res://scenes/ui/run_summary.tscn"
## Seconds between player death and the run-summary scene transition.
const DEATH_SUMMARY_DELAY := 0.8

@export var max_health: int = 200
@export var starting_weapon: WeaponData
## Temporary gameplay toggle. Disable this in the inspector to restore normal damage.
@export var invincible := true

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var healthbar: TextureProgressBar = $HealthBar
@onready var damage_number: PackedScene = preload(
	"res://scenes/effects/damage_number.tscn"
)
@onready var inventory_ui: InventoryUI = $InventoryUI
@onready var weapon_controller: WeaponController = $WeaponController

var x_direction: float
var y_direction: float
var velocity_vector: Vector2
var health: int
var inventory: InventoryData
var nearby_chests: Array[Chest] = []
var weapon_equipment: WeaponEquipment
var pillar_inventory: Array[String] = []

# The assembler teleports the player after _ready, so the first physics frame is excluded.
var _previous_position: Vector2
var _distance_tracking := false
## Prevents repeated death transitions while the summary hand-off is pending.
var _dead := false


func _ready() -> void:
	invincible = GameState.invincibility_enabled
	inventory = InventoryData.new(6)
	weapon_equipment = WeaponEquipment.new(starting_weapon)
	weapon_equipment.equipped_weapon_changed.connect(_on_equipped_weapon_changed)
	weapon_controller.weapon_consumed.connect(_on_weapon_consumed)
	weapon_controller.equip_weapon(weapon_equipment.equipped_weapon)
	inventory_ui.bind_player(inventory, weapon_equipment)
	health = max_health
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
		_track_distance()
		return
	_handle_movement()
	_handle_animations()
	weapon_controller.aim_at(get_global_mouse_position())
	_track_distance()


func _process(delta: float) -> void:
	if not inventory_ui.is_open() and Input.is_action_pressed("attack"):
		weapon_controller.try_attack()
	sprite.modulate = sprite.modulate.lerp(Color.WHITE, delta * 5.0)


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
	elif event.is_action_pressed("visibility"):
		# Debug "Potion of Visibility": reveal the whole map. The player is a child of the
		# MapAssembler (see _spawn_player), which owns the fog and minimap.
		var map := get_parent()
		if map != null and map.has_method("reveal_all_map"):
			map.reveal_all_map()
		get_viewport().set_input_as_handled()


## Restore this player from a save payload (see SaveManager). Called by MapAssembler after
## the map is built and _ready() has already created the inventory and equipment objects, so
## it mutates those in place rather than replacing them.
func apply_save(data: Dictionary) -> void:
	health = int(data.get("health", max_health))
	healthbar.max_value = max_health
	healthbar.value = health
	healthbar.visible = health < max_health

	pillar_inventory.clear()
	for pillar_name in data.get("pillar_inventory", []):
		pillar_inventory.append(str(pillar_name))

	var slot_paths: Array = data.get("inventory", [])
	for i in inventory.slots.size():
		var path := str(slot_paths[i]) if i < slot_paths.size() else ""
		inventory.slots[i] = (load(path) as ItemData) if not path.is_empty() else null
	inventory.inventory_changed.emit()

	# Emit the change so WeaponController re-equips (or clears) through the normal path.
	var equipped_path := str(data.get("equipped", ""))
	var equipped: WeaponData = (load(equipped_path) as WeaponData) if not equipped_path.is_empty() else null
	var previous := weapon_equipment.equipped_weapon
	weapon_equipment.equipped_weapon = equipped
	weapon_equipment.equipped_weapon_changed.emit(previous, equipped)


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


## Applies movement input and keeps the character sprite facing horizontally.
func _handle_movement() -> void:
	x_direction = Input.get_axis("move left", "move right")
	if x_direction:
		velocity_vector.x = x_direction
	else:
		velocity_vector.x = move_toward(velocity_vector.x, 0, SPEED)

	if x_direction != 0.0:
		sprite.flip_h = x_direction < 0.0

	y_direction = Input.get_axis("move up", "move down")
	if y_direction:
		velocity_vector.y = y_direction
	else:
		velocity_vector.y = move_toward(velocity_vector.y, 0, SPEED)

	velocity = velocity_vector.normalized() * SPEED
	move_and_slide()


func _handle_animations() -> void:
	if x_direction == 0.0 and y_direction == 0.0:
		sprite.play(&"idle")
	else:
		sprite.play(&"moving")


## Accumulates actual world displacement so blocked movement does not count as travel.
func _track_distance() -> void:
	if not _distance_tracking:
		_previous_position = global_position
		_distance_tracking = true
		return
	Stats.add_distance_pixels(global_position.distance_to(_previous_position))
	_previous_position = global_position


func _on_equipped_weapon_changed(previous: WeaponData, current: WeaponData) -> void:
	if current == null:
		weapon_controller.clear_weapon(previous)
	else:
		weapon_controller.equip_weapon(current)


func _on_weapon_consumed(weapon: WeaponData) -> void:
	weapon_equipment.consume_if_equipped(weapon)


## Applies incoming damage and begins the run-summary hand-off when health reaches zero.
func take_damage(amount: int) -> void:
	if invincible or _dead:
		return
	var damage_popup: DamageNumber = damage_number.instantiate()
	damage_popup.text_label = str(amount)
	damage_popup.text_color = Color.RED
	damage_popup.global_position = global_position - Vector2(
		0,
		sprite.sprite_frames.get_frame_texture(&"idle", 0).get_height() / 2.0,
	)
	get_tree().current_scene.add_child(damage_popup)

	health -= amount
	if health <= 0:
		_die()
		return

	healthbar.visible = true
	healthbar.value = health
	sprite.modulate = Color.RED


## Ends the run once and transitions to the summary after a short visual delay.
func _die() -> void:
	_dead = true
	Stats.end_run(true)
	set_physics_process(false)
	set_process(false)
	velocity = Vector2.ZERO
	sprite.modulate = Color.RED
	var tree := get_tree()
	tree.create_timer(DEATH_SUMMARY_DELAY).timeout.connect(
		func() -> void: tree.change_scene_to_file(RUN_SUMMARY_SCENE)
	)
