class_name ControlsPanel
extends Control

## Read-only explanation of the game's controls, reachable from both the main menu and the
## pause menu. It only describes the bindings — there is no rebinding. Kept in sync by hand
## with project.godot's [input] map.

## action label -> key description. Order is preserved for display.
const CONTROLS := [
	["Move", "W  A  S  D"],
	["Attack", "Left Mouse"],
	["Inventory", "I"],
	["Interact / Open chest", "E"],
	["Pause", "Esc"],
	["Close menu", "Esc"],
	["Potion of Visibility (debug)", "V"],
]

## Optional callback invoked by the Back button. When null, no Back button is shown (the
## host provides its own way out).
var _on_back: Callable

func setup(on_back: Callable = Callable()) -> void:
	_on_back = on_back

func _ready() -> void:
	# Fill the host (anchors AND offsets) so the centred wrapper spans the whole screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := MenuUi.centered_box()
	var root := MenuUi.root_of(box)
	add_child(root)

	box.add_child(MenuUi.title("Controls", 32, MenuUi.TEXT_COLOR))
	box.add_child(MenuUi.spacer(12))
	for entry in CONTROLS:
		box.add_child(MenuUi.row(entry[0], entry[1]))

	if _on_back.is_valid():
		box.add_child(MenuUi.spacer(12))
		var back := MenuUi.button("Back")
		back.pressed.connect(func() -> void: _on_back.call())
		box.add_child(back)
