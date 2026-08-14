extends GutTest

var player: Player
var chest: Chest


func before_each() -> void:
	player = preload("res://scenes/player/player.tscn").instantiate()
	chest = preload("res://scenes/props/chest.tscn").instantiate()
	add_child_autofree(player)
	add_child_autofree(chest)


func test_inventory_action_toggles_player_inventory() -> void:
	var event := InputEventAction.new()
	event.action = &"inventory"
	event.pressed = true

	player._unhandled_input(event)
	assert_true(player.inventory_ui.is_open())
	assert_null(player.inventory_ui.active_chest)

	player._unhandled_input(event)
	assert_false(player.inventory_ui.is_open())


func test_player_and_chest_have_requested_slot_counts() -> void:
	assert_eq(player.inventory.capacity, 6)
	assert_eq(player.inventory.slots.size(), 6)
	assert_eq(chest.inventory.capacity, 4)
	assert_eq(chest.inventory.slots.size(), 4)


func test_chest_animations_use_dedicated_empty_and_full_frame_files() -> void:
	var frames := chest.sprite.sprite_frames
	for frame in 3:
		var empty_texture := frames.get_frame_texture(Chest.EMPTY_OPEN_ANIMATION, frame)
		var full_texture := frames.get_frame_texture(Chest.FULL_OPEN_ANIMATION, frame)
		assert_eq(
			empty_texture.resource_path,
			"res://Dungeon Tileset v1.7/frames/chest_empty_open_anim_f%d.png" % frame,
		)
		assert_eq(
			full_texture.resource_path,
			"res://Dungeon Tileset v1.7/frames/chest_full_open_anim_f%d.png" % frame,
		)
	assert_eq(chest.sprite.animation, Chest.FULL_OPEN_ANIMATION)
	assert_eq(chest.sprite.frame, 0)


func test_closed_chest_uses_empty_animation_after_last_item_is_removed() -> void:
	chest.inventory.remove_item(0)

	assert_true(chest.inventory.is_empty())
	assert_eq(chest.sprite.animation, Chest.EMPTY_OPEN_ANIMATION)
	assert_eq(chest.sprite.frame, 0)


func test_inventory_panels_are_centered_with_separate_grid_dimensions() -> void:
	player.inventory_ui.show_chest(player.inventory, chest)
	await get_tree().process_frame

	var viewport_center := (
		player.inventory_ui._inventory_center.get_global_rect().get_center()
	)
	var row_center := player.inventory_ui._panel_row.get_global_rect().get_center()
	assert_almost_eq(row_center.x, viewport_center.x, 0.5)
	assert_almost_eq(row_center.y, viewport_center.y, 0.5)
	assert_eq(player.inventory_ui._player_panel._grid.columns, 3)
	assert_eq(player.inventory_ui._chest_panel._grid.columns, 2)
	var player_style := (
		player.inventory_ui._player_panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	)
	var chest_style := (
		player.inventory_ui._chest_panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	)
	assert_eq(player_style.border_color, InventoryUI.PLAYER_BORDER_COLOR)
	assert_eq(chest_style.border_color, InventoryUI.CHEST_BORDER_COLOR)
	assert_eq(
		player.inventory_ui._panel_row.get_theme_constant(&"separation"),
		InventoryUI.PANEL_SEPARATION,
	)


func test_interact_opens_only_a_chest_in_range() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true

	player._unhandled_input(event)
	assert_false(player.inventory_ui.is_open())

	player.enter_chest_range(chest)
	player._unhandled_input(event)
	assert_true(player.inventory_ui.is_open())
	assert_same(player.inventory_ui.active_chest, chest)
	assert_true(chest.is_open)
	assert_eq(chest.sprite.animation, Chest.FULL_OPEN_ANIMATION)
	assert_true(chest.sprite.is_playing())


func test_opened_chest_stays_open_after_player_leaves_its_radius() -> void:
	player.enter_chest_range(chest)
	player.inventory_ui.show_chest(player.inventory, chest)

	player.exit_chest_range(chest)

	assert_false(player.inventory_ui.is_open())
	assert_null(player.inventory_ui.active_chest)
	assert_true(chest.is_open)
	assert_eq(chest.sprite.animation, Chest.FULL_OPEN_ANIMATION)


func test_looted_item_remains_in_player_inventory_after_closing_and_leaving() -> void:
	player.enter_chest_range(chest)
	player.inventory_ui.show_chest(player.inventory, chest)
	var sword := chest.inventory.item_at(0)

	assert_true(chest.inventory.transfer_item(0, player.inventory, 0))
	player.inventory_ui.close()
	player.exit_chest_range(chest)

	assert_same(player.inventory.item_at(0), sword)
	assert_null(chest.inventory.item_at(0))
	assert_true(chest.is_open)
	assert_eq(chest.sprite.animation, Chest.EMPTY_OPEN_ANIMATION)
	assert_eq(chest.sprite.frame, 2)
