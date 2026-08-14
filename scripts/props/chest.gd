class_name Chest
extends Node2D

## Owns a four-slot loot inventory and selects its sprite from open/empty/filled state.
## The required ChestSprite child provides empty_open and full_open animations. Inventory
## changes select the correct sequence immediately without polling each frame. Opening is
## permanent for the lifetime of the chest; ending UI interaction never closes it.

const EMPTY_OPEN_ANIMATION: StringName = &"empty_open"
const FULL_OPEN_ANIMATION: StringName = &"full_open"

@onready var sprite: AnimatedSprite2D = $ChestSprite

var is_open := false
var inventory: InventoryData

func _ready() -> void:
	inventory = InventoryData.new(4)
	inventory.inventory_changed.connect(_on_inventory_changed)
	inventory.add_item(ItemData.create(
		&"rusty_sword",
		"Rusty Sword",
		preload("res://Dungeon Tileset v1.7/frames/weapon_rusty_sword.png")
	))
	_on_inventory_changed()

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
