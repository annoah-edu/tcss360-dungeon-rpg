class_name Chest
extends Node2D

## Owns a four-slot loot inventory with one uniformly selected starting weapon.
## The required ChestSprite child provides empty_open and full_open animations. Inventory
## changes select the correct sequence immediately without polling each frame. Opening is
## permanent for the lifetime of the chest; ending UI interaction never closes it. Negative
## loot_seed values randomize independently, while nonnegative values reproduce test/authoring loot.

const EMPTY_OPEN_ANIMATION: StringName = &"empty_open"
const FULL_OPEN_ANIMATION: StringName = &"full_open"
const BOW: WeaponData = preload("res://resources/items/weapons/bow.tres")
const WEAPON_AXE: WeaponData = preload("res://resources/items/weapons/weapon_axe.tres")
const STARTING_LOOT_POOL: Array[WeaponData] = [BOW, WEAPON_AXE]

@export var loot_seed: int = -1

@onready var sprite: AnimatedSprite2D = $ChestSprite

var is_open := false
var inventory: InventoryData
var _loot_rng := RandomNumberGenerator.new()

func _ready() -> void:
	if loot_seed < 0:
		_loot_rng.randomize()
	else:
		_loot_rng.seed = loot_seed
	inventory = InventoryData.new(4)
	inventory.inventory_changed.connect(_on_inventory_changed)
	inventory.add_item(_select_starting_loot())
	_on_inventory_changed()


func _select_starting_loot() -> WeaponData:
	var selected_index := _loot_rng.randi_range(0, STARTING_LOOT_POOL.size() - 1)
	return STARTING_LOOT_POOL[selected_index]

func open() -> void:
	if is_open:
		return

	is_open = true
	sprite.play(_animation_for_contents())

func _on_inventory_changed() -> void:
	var animation := _animation_for_contents()
	sprite.stop()
	sprite.animation = animation
	if is_open:
		sprite.frame = sprite.sprite_frames.get_frame_count(animation) - 1
	else:
		sprite.frame = 0


func _animation_for_contents() -> StringName:
	return EMPTY_OPEN_ANIMATION if inventory.is_empty() else FULL_OPEN_ANIMATION

func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body is Player:
		(body as Player).enter_chest_range(self)

func _on_interaction_area_body_exited(body: Node2D) -> void:
	if body is Player:
		(body as Player).exit_chest_range(self)
