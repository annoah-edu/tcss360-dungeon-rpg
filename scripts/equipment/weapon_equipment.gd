class_name WeaponEquipment
extends Resource

## Owns the player's single equipped weapon definition. This pure state object has no
## scene dependencies; UI and combat react to its change signal.

signal equipped_weapon_changed(previous: WeaponData, current: WeaponData)

@export var equipped_weapon: WeaponData


func _init(initial_weapon: WeaponData = null) -> void:
	if _is_valid_weapon(initial_weapon):
		equipped_weapon = initial_weapon


## Atomically replaces the equipped weapon with a valid weapon from one occupied
## inventory slot. The previous weapon returns to that same slot.
func swap_from_inventory(inventory: InventoryData, slot_index: int) -> bool:
	if inventory == null or equipped_weapon == null:
		return false
	if slot_index < 0 or slot_index >= inventory.slots.size():
		return false

	var candidate_item := inventory.item_at(slot_index)
	if not _is_valid_weapon(candidate_item):
		return false
	var candidate_weapon := candidate_item as WeaponData
	if candidate_weapon == equipped_weapon:
		return false

	var previous_weapon := equipped_weapon
	inventory.slots[slot_index] = previous_weapon
	equipped_weapon = candidate_weapon
	inventory.inventory_changed.emit()
	equipped_weapon_changed.emit(previous_weapon, candidate_weapon)
	return true


func _is_valid_weapon(item: ItemData) -> bool:
	return (
		item is WeaponData
		and (item as WeaponData).validation_errors(false).is_empty()
	)
