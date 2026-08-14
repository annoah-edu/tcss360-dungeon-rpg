class_name InventoryData
extends Resource

## Slot-based inventory state shared by players, chests and the UI.

signal inventory_changed

@export var capacity: int = 12
var slots: Array[ItemData] = []


func _init(initial_capacity: int = 12) -> void:
	capacity = maxi(initial_capacity, 1)
	slots.resize(capacity)


func item_at(index: int) -> ItemData:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Whether the inventory currently contains no items.
func is_empty() -> bool:
	for item in slots:
		if item != null:
			return false
	return true


func add_item(item: ItemData) -> bool:
	if item == null:
		return false
	for index in slots.size():
		if slots[index] == null:
			slots[index] = item
			inventory_changed.emit()
			return true
	return false


func remove_item(index: int) -> ItemData:
	if index < 0 or index >= slots.size():
		return null
	var item := slots[index]
	if item == null:
		return null
	slots[index] = null
	inventory_changed.emit()
	return item


## Move an item into another slot. Occupied destinations are swapped so a drag never
## silently destroys an item.
func transfer_item(from_index: int, destination: InventoryData, to_index: int) -> bool:
	if destination == null:
		return false
	if from_index < 0 or from_index >= slots.size():
		return false
	if to_index < 0 or to_index >= destination.slots.size():
		return false
	if slots[from_index] == null:
		return false
	if destination == self and from_index == to_index:
		return false

	var displaced := destination.slots[to_index]
	destination.slots[to_index] = slots[from_index]
	slots[from_index] = displaced
	inventory_changed.emit()
	if destination != self:
		destination.inventory_changed.emit()
	return true
