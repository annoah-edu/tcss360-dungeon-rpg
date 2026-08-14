class_name WeaponData
extends ItemData

## Immutable weapon definition shared by inventory, equipment, and combat systems.
## Runtime state such as durability must live in a separate instance type rather than
## mutating this resource.

@export var held_texture: Texture2D
@export var base_damage: int
@export_range(0.0, 1.0, 0.01) var damage_variance: float = 0.20
@export var attack_interval_seconds: float
@export var knockback_strength: int
@export var grip_offset: Vector2
@export var attack_behavior_scene: PackedScene


## Reports every invalid field. Combat-ready weapons require an attack behavior.
func validation_errors(require_behavior: bool = true) -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if icon == null:
		errors.append("icon must not be null")
	if held_texture == null:
		errors.append("held_texture must not be null")
	if base_damage <= 0:
		errors.append("base_damage must be greater than zero")
	if damage_variance < 0.0 or damage_variance > 1.0:
		errors.append("damage_variance must be between zero and one")
	if attack_interval_seconds <= 0.0:
		errors.append("attack_interval_seconds must be greater than zero")
	if knockback_strength < 0:
		errors.append("knockback_strength must not be negative")
	if require_behavior and attack_behavior_scene == null:
		errors.append("attack_behavior_scene must not be null")
	return errors
