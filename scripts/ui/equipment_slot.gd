class_name EquipmentSlot
extends PanelContainer

## Displays the equipped weapon or an empty state and accepts weapons only from
## the bound player inventory. The drag payload shape is
## {"inventory": InventoryData, "index": int}.

const SLOT_SIZE := Vector2(72, 72)

var _player_inventory: InventoryData
var _equipment: WeaponEquipment
var _icon: TextureRect
var _name_label: Label


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 5)
	margin.add_theme_constant_override(&"margin_top", 5)
	margin.add_theme_constant_override(&"margin_right", 5)
	margin.add_theme_constant_override(&"margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## Binds the only inventory permitted as a drag source and the authoritative
## equipment state. Rebinding safely disconnects the previous model.
func setup(
	player_inventory: InventoryData,
	equipment: WeaponEquipment,
	border_color: Color,
) -> void:
	if (
		_equipment != null
		and _equipment.equipped_weapon_changed.is_connected(
			_on_equipped_weapon_changed
		)
	):
		_equipment.equipped_weapon_changed.disconnect(_on_equipped_weapon_changed)

	_player_inventory = player_inventory
	_equipment = equipment
	if _equipment != null:
		_equipment.equipped_weapon_changed.connect(_on_equipped_weapon_changed)
	_apply_style(border_color)
	if is_node_ready():
		refresh()


func refresh() -> void:
	if _icon == null or _name_label == null:
		return
	var weapon := _equipment.equipped_weapon if _equipment != null else null
	_icon.texture = weapon.icon if weapon != null else null
	_name_label.text = weapon.display_name if weapon != null else ""
	tooltip_text = weapon.display_name if weapon != null else "Empty equipment slot"


## Equipment cannot be dragged out; it can only be replaced from the player inventory.
func _get_drag_data(_at_position: Vector2) -> Variant:
	return null


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or _equipment == null:
		return false
	if not data.has("inventory") or not data.has("index"):
		return false
	if (
		data["inventory"] != _player_inventory
		or not (data["inventory"] is InventoryData)
	):
		return false
	if typeof(data["index"]) != TYPE_INT:
		return false

	var source := data["inventory"] as InventoryData
	var candidate := source.item_at(int(data["index"]))
	return (
		candidate is WeaponData
		and candidate != _equipment.equipped_weapon
		and (candidate as WeaponData).validation_errors().is_empty()
	)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var source := data["inventory"] as InventoryData
	_equipment.swap_from_inventory(source, int(data["index"]))


func _on_equipped_weapon_changed(_previous: WeaponData, _current: WeaponData) -> void:
	refresh()


func _apply_style(border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.035, 0.075, 0.98)
	style.border_color = border_color
	style.set_border_width_all(4)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 8
	add_theme_stylebox_override(&"panel", style)
