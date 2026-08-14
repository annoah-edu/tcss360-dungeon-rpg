class_name InventoryUI
extends CanvasLayer

## Screen-space inventory popup. It never copies item state: panels are bound to the
## inventories owned by the player and chest, so every drop immediately changes the game.

const PLAYER_COLUMNS := 3
const CHEST_COLUMNS := 2
const PANEL_SEPARATION := 64
const PLAYER_BORDER_COLOR := Color("5ad7ff")
const CHEST_BORDER_COLOR := Color("f5b642")

var active_chest: Chest
var _root: Control
var _inventory_center: CenterContainer
var _panel_row: HBoxContainer
var _player_panel: InventoryPanel
var _chest_panel: InventoryPanel
var _equipment_label: Label
var _equipment_slot: EquipmentSlot
var _player_inventory: InventoryData
var _weapon_equipment: WeaponEquipment


func _ready() -> void:
	layer = 50
	_build_ui()
	close()


func is_open() -> bool:
	return _root != null and _root.visible


## Binds the player's live inventory and equipment state without copying either.
func bind_player(
	player_inventory: InventoryData,
	weapon_equipment: WeaponEquipment,
) -> void:
	_player_inventory = player_inventory
	_weapon_equipment = weapon_equipment
	if _equipment_slot != null:
		_equipment_slot.setup(
			_player_inventory,
			_weapon_equipment,
			PLAYER_BORDER_COLOR,
		)


func toggle_player(player_inventory: InventoryData) -> void:
	if is_open():
		close()
	else:
		show_player(player_inventory)


func show_player(player_inventory: InventoryData) -> void:
	_set_active_chest(null)
	bind_player(player_inventory, _weapon_equipment)
	_player_panel.bind_inventory(
		"PLAYER", player_inventory, PLAYER_COLUMNS, PLAYER_BORDER_COLOR
	)
	_chest_panel.visible = false
	_root.visible = true


func toggle_chest(player_inventory: InventoryData, chest: Chest) -> void:
	if is_open() and active_chest == chest:
		close()
	else:
		show_chest(player_inventory, chest)


func show_chest(player_inventory: InventoryData, chest: Chest) -> void:
	if chest == null:
		return
	_set_active_chest(chest)
	bind_player(player_inventory, _weapon_equipment)
	_player_panel.bind_inventory(
		"PLAYER", player_inventory, PLAYER_COLUMNS, PLAYER_BORDER_COLOR
	)
	_chest_panel.bind_inventory(
		"CHEST", chest.inventory, CHEST_COLUMNS, CHEST_BORDER_COLOR
	)
	_chest_panel.visible = true
	_root.visible = true


func close() -> void:
	_set_active_chest(null)
	if _root != null:
		_root.visible = false


func _set_active_chest(chest: Chest) -> void:
	active_chest = chest
	if active_chest != null:
		active_chest.open()


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.01, 0.03, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_inventory_center = CenterContainer.new()
	_inventory_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_inventory_center)
	_inventory_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel_row = HBoxContainer.new()
	_panel_row.add_theme_constant_override(&"separation", PANEL_SEPARATION)
	_inventory_center.add_child(_panel_row)

	_chest_panel = InventoryPanel.new()
	_panel_row.add_child(_chest_panel)
	_player_panel = InventoryPanel.new()
	_panel_row.add_child(_player_panel)

	var equipment_column := VBoxContainer.new()
	equipment_column.add_theme_constant_override(&"separation", 8)

	_equipment_label = Label.new()
	_equipment_label.text = "EQUIPPED"
	_equipment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_equipment_label.add_theme_color_override(&"font_color", PLAYER_BORDER_COLOR)
	_equipment_label.add_theme_font_size_override(&"font_size", 16)
	equipment_column.add_child(_equipment_label)

	var equipment_center := CenterContainer.new()
	equipment_column.add_child(equipment_center)

	_equipment_slot = EquipmentSlot.new()
	equipment_center.add_child(_equipment_slot)
	_player_panel.set_accessory(equipment_column)
	_equipment_slot.setup(_player_inventory, _weapon_equipment, PLAYER_BORDER_COLOR)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "Drag player weapons onto EQUIPPED - I / E / Esc to close"
	hint.add_theme_font_size_override(&"font_size", 16)
	_root.add_child(hint)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-185, -54)
	hint.size = Vector2(370, 28)

	var theme := Theme.new()
	theme.default_font = load("res://resources/fonts/pixel.ttf") as Font
	theme.default_font_size = 16
	_root.theme = theme
