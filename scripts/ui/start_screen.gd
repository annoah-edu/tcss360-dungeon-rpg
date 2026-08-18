extends Control

## Main menu shown at launch. Builds its UI in code so the button list is data-driven:
## add an entry to MENU_ITEMS and a matching handler method, and a new menu button
## appears with no scene editing. Screens (seed prompt, statistics, settings) are plain
## Control panels swapped in and out of a single content slot.

const MAP_SCENE := "res://scenes/map/map.tscn"

const BG_COLOR := Color(0.05, 0.05, 0.09)
const ACCENT := Color(0.66, 0.34, 0.95)
const TEXT_COLOR := Color(0.9, 0.9, 0.95)
const MUTED := Color(0.6, 0.6, 0.68)

## The main menu. Each entry is {label, handler-method-name}; append here to add buttons.
const MENU_ITEMS := [
	{"label": "Start Run", "method": "_on_start_pressed"},
	{"label": "Statistics", "method": "_on_statistics_pressed"},
	{"label": "Settings", "method": "_on_settings_pressed"},
]

var _font: Font
var _menu: Control
## The panel currently overlaying the menu (seed/stats/settings), or null on the menu.
var _panel: Control

func _ready() -> void:
	_font = load("res://resources/fonts/Minecraft.ttf") as Font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_menu()

# --- Main menu ---------------------------------------------------------------

func _build_menu() -> void:
	var box := _centered_box()
	_menu = _root_of(box)
	add_child(_menu)

	box.add_child(_title("DUNGEON RPG", 48, ACCENT))
	box.add_child(_spacer(24))
	for item in MENU_ITEMS:
		var btn := _button(item["label"])
		btn.pressed.connect(Callable(self, item["method"]))
		box.add_child(btn)

# --- Start Run / seed prompt -------------------------------------------------

func _on_start_pressed() -> void:
	var box := _centered_box()
	box.add_child(_title("Choose a seed", 32, TEXT_COLOR))
	box.add_child(_spacer(8))

	var hint := _label("A blank or random seed counts toward your\nstatistics. A chosen seed is for practice and\ndoes not.", MUTED, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	box.add_child(_spacer(12))

	var field := LineEdit.new()
	field.placeholder_text = "seed (leave blank for random)"
	field.custom_minimum_size = Vector2(320, 44)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_line_edit(field)
	box.add_child(field)
	box.add_child(_spacer(16))

	var start_btn := _button("Start with seed")
	start_btn.pressed.connect(func() -> void: _launch_with_text(field.text))
	box.add_child(start_btn)

	var random_btn := _button("Random Seed")
	random_btn.pressed.connect(func() -> void: _launch_random())
	box.add_child(random_btn)

	box.add_child(_back_button())
	_show_panel(_root_of(box))
	field.grab_focus()
	field.text_submitted.connect(func(t: String) -> void: _launch_with_text(t))

func _launch_random() -> void:
	Stats.configure_run(0, true)
	_enter_dungeon()

## Interpret the seed field: blank -> random; all digits -> that integer; any other
## text -> its stable hash, so "duck" is a valid (non-counting) seed too.
func _launch_with_text(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_launch_random()
		return
	var seed_value: int
	if trimmed.is_valid_int():
		seed_value = trimmed.to_int()
	else:
		seed_value = int(hash(trimmed))
	Stats.configure_run(seed_value, false)
	_enter_dungeon()

func _enter_dungeon() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)

# --- Statistics --------------------------------------------------------------

func _on_statistics_pressed() -> void:
	var box := _centered_box()
	box.add_child(_title("Statistics", 32, TEXT_COLOR))
	box.add_child(_spacer(12))

	for def in Stats.STAT_DEFS:
		box.add_child(_stat_row(def["label"], Stats.format_value(Stats.lifetime(def["key"]), def["kind"])))

	# The joke stat: a caption plus the live vibrating "???" value.
	var duck_row := HBoxContainer.new()
	duck_row.add_theme_constant_override("separation", 12)
	duck_row.custom_minimum_size = Vector2(420, 0)
	var duck_caption := _label("Distance from The Duck", MUTED, 18)
	duck_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duck_row.add_child(duck_caption)
	var duck := DuckDistance.new()
	duck_row.add_child(duck)
	box.add_child(_spacer(8))
	box.add_child(duck_row)

	box.add_child(_back_button())
	_show_panel(_root_of(box))

# --- Settings ----------------------------------------------------------------

func _on_settings_pressed() -> void:
	var box := _centered_box()
	box.add_child(_title("Settings", 32, TEXT_COLOR))
	box.add_child(_spacer(12))

	var status := _label("", MUTED, 16)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var clear_btn := _button("Clear statistics")
	clear_btn.pressed.connect(func() -> void:
		Stats.clear()
		status.text = "Statistics cleared."
	)
	box.add_child(clear_btn)
	box.add_child(_spacer(8))
	box.add_child(status)
	box.add_child(_back_button())
	_show_panel(_root_of(box))

# --- Panel plumbing ----------------------------------------------------------

## Swap the given panel in for the menu. Passing null restores the menu.
func _show_panel(panel: Control) -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = panel
	_menu.visible = panel == null
	if panel != null:
		add_child(panel)

func _back_button() -> Button:
	var btn := _button("Back")
	btn.pressed.connect(func() -> void: _show_panel(null))
	return btn

# --- Widget factory ----------------------------------------------------------

## A content VBox centered on screen. The returned box is where callers add widgets;
## its screen-filling CenterContainer wrapper (used for add-to-tree / show / free) is
## reachable via _root_of(). A CenterContainer sizes the box to its content and holds it
## dead center, which a bare anchored VBox does not do reliably.
func _centered_box() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.set_meta("screen_root", center)
	return box

## The screen-filling wrapper for a box returned by _centered_box().
func _root_of(box: VBoxContainer) -> Control:
	return box.get_meta("screen_root")

func _title(text: String, size: int, color: Color) -> Label:
	var l := _label(text, color, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if _font != null:
		l.add_theme_font_override("font", _font)
	return l

func _stat_row(caption: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(420, 0)
	row.add_theme_constant_override("separation", 12)
	var left := _label(caption, TEXT_COLOR, 18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := _label(value, ACCENT, 18)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	row.add_child(right)
	return row

func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 48)
	btn.add_theme_font_size_override("font_size", 22)
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	return btn

func _style_line_edit(field: LineEdit) -> void:
	field.add_theme_font_size_override("font_size", 20)
	if _font != null:
		field.add_theme_font_override("font", _font)

func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
