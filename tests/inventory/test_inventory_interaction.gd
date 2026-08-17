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
	assert_eq(chest.inventory.capacity, 6)
	assert_eq(chest.inventory.slots.size(), 6)
	assert_same(player.weapon_equipment.equipped_weapon, player.starting_weapon)


func test_player_inventory_shows_labeled_non_draggable_equipment_slot() -> void:
	player.inventory_ui.show_player(player.inventory)

	assert_eq(player.inventory_ui._equipment_label.text, "EQUIPPED")
	assert_true(player.inventory_ui._equipment_slot.visible)
	assert_same(
		player.inventory_ui._equipment_slot._equipment,
		player.weapon_equipment,
	)
	assert_null(
		player.inventory_ui._equipment_slot._get_drag_data(Vector2.ZERO),
		"The equipped weapon cannot be dragged out",
	)
	assert_eq(player.inventory_ui._player_panel._grid.columns, 3)
	assert_eq(player.inventory_ui._player_panel._slots.size(), 6)


func test_player_weapon_drop_atomically_equips_and_updates_combat() -> void:
	var incoming_weapon := _create_test_weapon(&"incoming_weapon")
	var previous_weapon := player.weapon_equipment.equipped_weapon
	player.inventory.add_item(incoming_weapon)
	player.inventory_ui.show_player(player.inventory)
	var drag_data := {"inventory": player.inventory, "index": 0}

	assert_true(
		player.inventory_ui._equipment_slot._can_drop_data(Vector2.ZERO, drag_data)
	)
	player.inventory_ui._equipment_slot._drop_data(Vector2.ZERO, drag_data)

	assert_same(player.weapon_equipment.equipped_weapon, incoming_weapon)
	assert_same(player.weapon_controller.equipped_weapon, incoming_weapon)
	assert_same(player.inventory.item_at(0), previous_weapon)
	var behavior := player.weapon_controller.active_behavior as MeleeSwingAttack
	assert_same(behavior.weapon_sprite.texture, incoming_weapon.held_texture)
	assert_eq(behavior.weapon_sprite.offset, incoming_weapon.grip_offset)


func test_equipment_slot_rejects_chest_items_and_non_weapons() -> void:
	var chest_weapon := _create_test_weapon(&"chest_weapon")
	chest.inventory.slots[0] = chest_weapon
	var chest_drag := {"inventory": chest.inventory, "index": 0}
	assert_false(
		player.inventory_ui._equipment_slot._can_drop_data(Vector2.ZERO, chest_drag)
	)

	var potion := ItemData.create(&"potion", "Potion", chest_weapon.icon)
	player.inventory.add_item(potion)
	var potion_drag := {"inventory": player.inventory, "index": 0}
	assert_false(
		player.inventory_ui._equipment_slot._can_drop_data(Vector2.ZERO, potion_drag)
	)
	assert_same(player.inventory.item_at(0), potion)


func test_chest_contains_six_shared_weapon_definitions_from_the_full_pool() -> void:
	assert_eq(Chest.STARTING_LOOT_POOL.weapons.size(), 25)
	assert_true(Chest.STARTING_LOOT_POOL.validation_errors().is_empty())
	for slot_index in chest.inventory.capacity:
		var weapon := chest.inventory.item_at(slot_index) as WeaponData
		assert_not_null(weapon)
		assert_true(Chest.STARTING_LOOT_POOL.weapons.has(weapon))


func test_equal_loot_seed_reproduces_all_six_weapons() -> void:
	var chest_scene: PackedScene = preload("res://scenes/props/chest.tscn")
	var first_chest: Chest = chest_scene.instantiate()
	var second_chest: Chest = chest_scene.instantiate()
	first_chest.loot_seed = 24680
	second_chest.loot_seed = 24680
	add_child_autofree(first_chest)
	add_child_autofree(second_chest)
	for slot_index in first_chest.inventory.capacity:
		assert_same(
			first_chest.inventory.item_at(slot_index),
			second_chest.inventory.item_at(slot_index),
		)


func test_different_seeds_can_produce_different_six_weapon_sequences() -> void:
	var chest_scene: PackedScene = preload("res://scenes/props/chest.tscn")
	var first_chest: Chest = chest_scene.instantiate()
	var second_chest: Chest = chest_scene.instantiate()
	first_chest.loot_seed = 1
	second_chest.loot_seed = 2
	add_child_autofree(first_chest)
	add_child_autofree(second_chest)
	assert_ne(first_chest.inventory.slots, second_chest.inventory.slots)


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
	for slot_index in chest.inventory.capacity:
		chest.inventory.remove_item(slot_index)

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
	assert_eq(player.inventory_ui._chest_panel._slots.size(), 6)
	assert_true(player.inventory_ui._equipment_slot.visible)
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
	var weapon := chest.inventory.item_at(0)

	assert_true(chest.inventory.transfer_item(0, player.inventory, 0))
	player.inventory_ui.close()
	player.exit_chest_range(chest)

	assert_same(player.inventory.item_at(0), weapon)
	assert_null(chest.inventory.item_at(0))
	assert_true(chest.is_open)
	assert_eq(chest.sprite.animation, Chest.FULL_OPEN_ANIMATION)
	assert_eq(chest.sprite.frame, 2)


func _create_test_weapon(weapon_id: StringName) -> WeaponData:
	var texture: Texture2D = preload(
		"res://Dungeon Tileset v1.7/frames/weapon_regular_sword.png"
	)
	var weapon := WeaponData.new()
	weapon.id = weapon_id
	weapon.display_name = String(weapon_id)
	weapon.icon = texture
	weapon.held_texture = texture
	weapon.base_damage = 21
	weapon.damage_variance = 0.05
	weapon.attack_interval_seconds = 0.25
	weapon.knockback_strength = 90
	weapon.grip_offset = Vector2(1, -8)
	weapon.attack_behavior_scene = preload(
		"res://scenes/combat/melee_swing_attack.tscn"
	)
	return weapon
