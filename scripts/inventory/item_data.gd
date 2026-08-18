class_name ItemData
extends Resource

## The smallest useful description of an inventory item. More gameplay data (damage,
## armour, stack size, etc.) can be added here without changing the inventory UI.

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D


static func create(item_id: StringName, item_name: String, item_icon: Texture2D = null) -> ItemData:
	var item := ItemData.new()
	item.id = item_id
	item.display_name = item_name
	item.icon = item_icon
	return item
