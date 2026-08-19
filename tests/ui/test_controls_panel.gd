extends GutTest

## Proves the controls panel's content is centred within its host, in both axes, so the
## menu reads correctly from both the main menu and the pause menu.

func test_controls_panel_content_is_centered() -> void:
	var parent := Control.new()
	parent.size = Vector2(1000, 700)
	add_child_autofree(parent)

	var panel := ControlsPanel.new()
	panel.setup(func() -> void: pass)  # a Back button, so it is the full panel
	parent.add_child(panel)
	# Let the container layout settle.
	await wait_frames(2)

	# ControlsPanel > CenterContainer > VBox(content).
	var center := panel.get_child(0) as CenterContainer
	assert_not_null(center, "expected a CenterContainer wrapper")
	var box := center.get_child(0) as VBoxContainer
	assert_not_null(box, "expected a content VBox")

	var box_center_x := box.global_position.x + box.size.x / 2.0
	var box_center_y := box.global_position.y + box.size.y / 2.0
	assert_almost_eq(box_center_x, 500.0, 1.0)
	assert_almost_eq(box_center_y, 350.0, 1.0)
