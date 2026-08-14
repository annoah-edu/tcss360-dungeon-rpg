extends GutTest


func test_add_item_uses_first_empty_slot() -> void:
	var inventory := InventoryData.new(3)
	var sword := ItemData.create(&"sword", "Sword")

	assert_true(inventory.add_item(sword))
	assert_same(inventory.item_at(0), sword)
	assert_false(inventory.is_empty())


func test_new_inventory_is_empty() -> void:
	assert_true(InventoryData.new(3).is_empty())


func test_add_item_returns_false_when_full() -> void:
	var inventory := InventoryData.new(1)
	inventory.add_item(ItemData.create(&"sword", "Sword"))

	assert_false(inventory.add_item(ItemData.create(&"potion", "Potion")))


func test_transfer_moves_item_between_real_inventories() -> void:
	var chest := InventoryData.new(2)
	var player := InventoryData.new(2)
	var sword := ItemData.create(&"sword", "Sword")
	chest.add_item(sword)

	assert_true(chest.transfer_item(0, player, 1))
	assert_null(chest.item_at(0))
	assert_same(player.item_at(1), sword)


func test_transfer_swaps_occupied_slots_without_losing_items() -> void:
	var chest := InventoryData.new(1)
	var player := InventoryData.new(1)
	var sword := ItemData.create(&"sword", "Sword")
	var potion := ItemData.create(&"potion", "Potion")
	chest.add_item(sword)
	player.add_item(potion)

	assert_true(chest.transfer_item(0, player, 0))
	assert_same(chest.item_at(0), potion)
	assert_same(player.item_at(0), sword)


func test_transfer_rejects_invalid_source_and_destination_slots() -> void:
	var source := InventoryData.new(1)
	var destination := InventoryData.new(1)
	var sword := ItemData.create(&"sword", "Sword")
	source.add_item(sword)

	assert_false(source.transfer_item(-1, destination, 0))
	assert_false(source.transfer_item(0, destination, 2))
	assert_same(source.item_at(0), sword)
