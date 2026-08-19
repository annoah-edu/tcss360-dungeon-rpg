class_name PauseMenu
extends CanvasLayer

## In-run pause overlay: Resume / Save Game / Controls / Main Menu. Runs while the tree is
## paused (PROCESS_MODE_ALWAYS) so its buttons stay live; gameplay nodes are pausable and
## halt. Esc toggles it — there is no conflict with the inventory, because Player only
## consumes ui_cancel while an inventory panel is open, so Esc reaches here otherwise.

const START_SCENE := "res://scenes/ui/start_screen.tscn"

## Set by MapAssembler so Save Game can capture the live run.
var assembler: Node

var _root: Control
var _buttons: Control
var _status: Label
## The controls sub-panel while it is showing, else null.
var _sub_panel: Control

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _root.visible:
		# Esc backs out of the controls sub-panel first, otherwise closes the menu.
		if _sub_panel != null:
			_close_sub_panel()
		else:
			resume()
	else:
		open()
	get_viewport().set_input_as_handled()

func open() -> void:
	get_tree().paused = true
	_close_sub_panel()
	_status.text = ""
	_buttons.visible = true
	_root.visible = true

func resume() -> void:
	_close_sub_panel()
	_root.visible = false
	get_tree().paused = false

# --- Buttons -----------------------------------------------------------------

func _on_save_pressed() -> void:
	var ok := SaveManager.save_game(assembler)
	_status.text = "Saved." if ok else "Save failed."

func _on_controls_pressed() -> void:
	_buttons.visible = false
	_sub_panel = ControlsPanel.new()
	(_sub_panel as ControlsPanel).setup(_close_sub_panel)
	_root.add_child(_sub_panel)

func _on_main_menu_pressed() -> void:
	# Leaving the run: unpause so the next scene runs normally.
	get_tree().paused = false
	get_tree().change_scene_to_file(START_SCENE)

func _close_sub_panel() -> void:
	if _sub_panel != null and is_instance_valid(_sub_panel):
		_sub_panel.queue_free()
	_sub_panel = null
	if _buttons != null:
		_buttons.visible = true

# --- Construction ------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)

	var box := MenuUi.centered_box()
	_buttons = MenuUi.root_of(box)
	_root.add_child(_buttons)

	box.add_child(MenuUi.title("Paused", 40, MenuUi.ACCENT))
	box.add_child(MenuUi.spacer(20))

	var resume_btn := MenuUi.button("Resume")
	resume_btn.pressed.connect(resume)
	box.add_child(resume_btn)

	var save_btn := MenuUi.button("Save Game")
	save_btn.pressed.connect(_on_save_pressed)
	box.add_child(save_btn)

	var controls_btn := MenuUi.button("Controls")
	controls_btn.pressed.connect(_on_controls_pressed)
	box.add_child(controls_btn)

	var menu_btn := MenuUi.button("Main Menu")
	menu_btn.pressed.connect(_on_main_menu_pressed)
	box.add_child(menu_btn)

	box.add_child(MenuUi.spacer(8))
	_status = MenuUi.label("", MenuUi.MUTED, 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
