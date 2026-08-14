class_name InventoryPanel
extends PanelContainer

## Renders one InventoryData as a titled grid. Its owner supplies dimensions and accent
## colour so the panel contains no player- or chest-specific state.

const SLOT_SIZE := 72
const SLOT_SEPARATION := 6

var _inventory: InventoryData
var _title_label: Label
var _grid: GridContainer
var _slots: Array[InventorySlot] = []


func _ready() -> void:
	var padding := MarginContainer.new()
	padding.add_theme_constant_override(&"margin_left", 18)
	padding.add_theme_constant_override(&"margin_top", 14)
	padding.add_theme_constant_override(&"margin_right", 18)
	padding.add_theme_constant_override(&"margin_bottom", 18)
	add_child(padding)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	padding.add_child(column)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override(&"font_size", 22)
	column.add_child(_title_label)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override(&"h_separation", SLOT_SEPARATION)
	_grid.add_theme_constant_override(&"v_separation", SLOT_SEPARATION)
	column.add_child(_grid)


## Bind a live inventory and configure its visual grid. The panel listens for model
## changes; it never owns or copies item state.
func bind_inventory(
	title: String,
	inventory: InventoryData,
	column_count: int,
	border_color: Color,
) -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_refresh):
		_inventory.inventory_changed.disconnect(_refresh)
	_inventory = inventory
	if _inventory != null:
		_inventory.inventory_changed.connect(_refresh)
	if _title_label != null:
		_title_label.text = title
		_title_label.add_theme_color_override(&"font_color", border_color)
	_grid.columns = maxi(column_count, 1)
	_apply_panel_style(border_color)
	_rebuild_slots()


func _apply_panel_style(border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.035, 0.075, 0.98)
	style.border_color = border_color
	style.set_border_width_all(4)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 8
	add_theme_stylebox_override(&"panel", style)


func _rebuild_slots() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_slots.clear()
	if _inventory == null:
		return
	for index in _inventory.slots.size():
		var slot := InventorySlot.new()
		slot.setup(_inventory, index)
		_grid.add_child(slot)
		_slots.append(slot)


func _refresh() -> void:
	for slot in _slots:
		slot.refresh()
