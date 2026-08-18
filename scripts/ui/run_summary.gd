extends Control

## Post-run recap. Reads the deltas Stats snapshotted in end_run() and shows each stat
## with its "(+num)" gain, plus the "Distance from The Duck" line — how much closer the
## Duck crept this run (a random fraction of the run's seconds, shown as "(-num m)"). The
## Statistics panel shows the same "Distance from The Duck" stat but as the unknowable
## "???" instead of a delta. A counted run adds the deltas into the lifetime totals it
## displays; a practice run shows the raw run numbers with a "not recorded" note.

const START_SCENE := "res://scenes/ui/start_screen.tscn"

const BG_COLOR := Color(0.05, 0.05, 0.09)
const ACCENT := Color(0.66, 0.34, 0.95)
const TEXT_COLOR := Color(0.9, 0.9, 0.95)
const MUTED := Color(0.6, 0.6, 0.68)
const GAIN := Color(0.4, 0.85, 0.45)
const DRIFT := Color(0.86, 0.4, 0.4)

var _font: Font

func _ready() -> void:
	_font = load("res://resources/fonts/Minecraft.ttf") as Font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	if Stats.last_run_died:
		box.add_child(_title("You Died", 40, DRIFT))
	else:
		box.add_child(_title("Run Complete", 40, ACCENT))
	if not Stats.last_run_counted:
		box.add_child(_center_label("Practice run — not recorded", MUTED, 16))
	box.add_child(_spacer(16))

	for def in Stats.STAT_DEFS:
		box.add_child(_summary_row(def))

	# How much closer the Duck crept this run: random(0.01..1.0) * run seconds, always a
	# gain on the Duck's part (a loss of distance), shown as "(-num m)".
	box.add_child(_spacer(8))
	var drift_row := _row()
	drift_row.add_child(_grow_label("Distance from The Duck", MUTED, 18))
	drift_row.add_child(_label("(-%s m)" % Stats._trim(Stats.last_run_drift), DRIFT, 18))
	box.add_child(drift_row)

	box.add_child(_spacer(20))
	var menu_btn := _button("Return to Menu")
	menu_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(START_SCENE))
	box.add_child(menu_btn)

## One stat line: caption on the left, then either "<lifetime> (+gain)" for a counted
## run, or just the run's own value for a practice run.
func _summary_row(def: Dictionary) -> HBoxContainer:
	var row := _row()
	row.add_child(_grow_label(def["label"], TEXT_COLOR, 18))
	var run_delta: float = Stats.last_run_value(def["key"])
	if Stats.last_run_counted:
		row.add_child(_label(Stats.format_value(Stats.lifetime(def["key"]), def["kind"]), ACCENT, 18))
		row.add_child(_label(Stats.format_delta(run_delta, def["kind"]), GAIN, 18))
	else:
		row.add_child(_label(Stats.format_value(run_delta, def["kind"]), ACCENT, 18))
	return row

# --- Widget factory (mirrors start_screen.gd) --------------------------------

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(480, 0)
	row.add_theme_constant_override("separation", 12)
	return row

func _title(text: String, size: int, color: Color) -> Label:
	return _center_label(text, color, size)

func _center_label(text: String, color: Color, size: int) -> Label:
	var l := _label(text, color, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _grow_label(text: String, color: Color, size: int) -> Label:
	var l := _label(text, color, size)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if _font != null:
		l.add_theme_font_override("font", _font)
	return l

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

func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
