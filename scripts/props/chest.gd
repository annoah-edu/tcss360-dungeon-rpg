class_name Chest
extends Node2D

## Owns a six-slot loot inventory filled by uniform selections from the weapon loot pool.
## The required ChestSprite child provides empty_open and full_open animations, while Coins
## presents the first-open reward effect. Inventory changes select the correct animation without
## polling. Opening is permanent and records statistics once. Negative loot_seed values randomize
## independently, while nonnegative values reproduce test and authoring loot.

const EMPTY_OPEN_ANIMATION: StringName = &"empty_open"
const FULL_OPEN_ANIMATION: StringName = &"full_open"
const INVENTORY_CAPACITY := 6
const STARTING_WEAPON_COUNT := 6
const STARTING_LOOT_POOL: WeaponLootPool = preload(
	"res://resources/items/weapon_loot_pool.tres"
)

@export var loot_seed: int = -1

@onready var sprite: AnimatedSprite2D = $ChestSprite
@onready var coins: GPUParticles2D = $Coins

var is_open := false
var inventory: InventoryData
var _loot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	if loot_seed < 0:
		_loot_rng.randomize()
	else:
		_loot_rng.seed = loot_seed
	inventory = InventoryData.new(INVENTORY_CAPACITY)
	for _weapon_index in STARTING_WEAPON_COUNT:
		inventory.add_item(STARTING_LOOT_POOL.random_weapon(_loot_rng))
	inventory.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed()


func open() -> void:
	if is_open:
		return

	is_open = true
	sprite.play(_animation_for_contents())
	coins.emitting = true
	Stats.add_chest()


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
