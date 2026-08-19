class_name MenuUi
extends RefCounted

## Shared widget factory for the game's menus, so the start screen, pause menu, controls
## panel and run summary all share one look. Mirrors the styling that lived inline in
## start_screen.gd. Everything is static — call MenuUi.button("Play"), etc.

const BG_COLOR := Color(0.05, 0.05, 0.09)
const ACCENT := Color(0.66, 0.34, 0.95)
const TEXT_COLOR := Color(0.9, 0.9, 0.95)
const MUTED := Color(0.6, 0.6, 0.68)

const FONT_PATH := "res://resources/fonts/Minecraft.ttf"

static func font() -> Font:
	return load(FONT_PATH) as Font

## A screen-filling ColorRect backdrop in the menu background colour.
static func backdrop() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg

## A content VBox centred on screen. Add widgets to the returned box; its screen-filling
## CenterContainer wrapper (for add-to-tree / show / free) is reachable via root_of().
static func centered_box() -> VBoxContainer:
	var center := CenterContainer.new()
	# Fill the parent (anchors AND offsets) so the container has real size to centre within.
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.set_meta("screen_root", center)
	return box

static func root_of(box: VBoxContainer) -> Control:
	return box.get_meta("screen_root")

static func label(text: String, color: Color = TEXT_COLOR, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	var f := font()
	if f != null:
		l.add_theme_font_override("font", f)
	return l

static func title(text: String, size: int = 32, color: Color = ACCENT) -> Label:
	var l := label(text, color, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 48)
	btn.add_theme_font_size_override("font_size", 22)
	var f := font()
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	return btn

static func spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

## A caption/value row (caption grows to the left, value pinned right), for lists like the
## controls table and statistics.
static func row(caption: String, value: String, width: int = 420) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_constant_override("separation", 12)
	var left := label(caption, TEXT_COLOR, 18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := label(value, ACCENT, 18)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(left)
	r.add_child(right)
	return r
