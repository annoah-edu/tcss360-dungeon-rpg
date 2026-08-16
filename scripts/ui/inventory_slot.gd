class_name InventorySlot
extends PanelContainer

## One drag-and-drop target backed directly by an InventoryData slot. Drag data has
## the exact shape {"inventory": InventoryData, "index": int}.

var inventory: InventoryData
var slot_index: int
var _icon: TextureRect
var _name_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(72, 72)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 5)
	margin.add_theme_constant_override(&"margin_top", 5)
	margin.add_theme_constant_override(&"margin_right", 5)
	margin.add_theme_constant_override(&"margin_bottom", 5)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 2)
	margin.add_child(content)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(42, 42)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_icon)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override(&"font_size", 11)
	content.add_child(_name_label)
	refresh()


func setup(slot_inventory: InventoryData, index: int) -> void:
	inventory = slot_inventory
	slot_index = index
	if is_node_ready():
		refresh()


func refresh() -> void:
	if _icon == null or _name_label == null:
		return
	var item := inventory.item_at(slot_index) if inventory != null else null
	_icon.texture = item.icon if item != null else null
	_name_label.text = item.display_name if item != null else ""
	tooltip_text = item.display_name if item != null else "Empty slot"


func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory == null:
		return null
	var item := inventory.item_at(slot_index)
	if item == null:
		return null

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(48, 48)
	preview.texture = item.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return {"inventory": inventory, "index": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and data.has("inventory")
		and data.has("index")
		and data["inventory"] is InventoryData
		and inventory != null
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source := data["inventory"] as InventoryData
	source.transfer_item(int(data["index"]), inventory, slot_index)
