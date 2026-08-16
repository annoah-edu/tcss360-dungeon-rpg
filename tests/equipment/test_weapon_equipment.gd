extends GutTest

const TEST_TEXTURE: Texture2D = preload(
	"res://Dungeon Tileset v1.7/frames/weapon_regular_sword.png"
)
const MELEE_BEHAVIOR: PackedScene = preload(
	"res://scenes/combat/melee_swing_attack.tscn"
)
const REGULAR_SWORD: WeaponData = preload(
	"res://resources/items/weapons/regular_sword.tres"
)
const WEAPON_AXE: WeaponData = preload(
	"res://resources/items/weapons/weapon_axe.tres"
)
const BOW: WeaponData = preload(
	"res://resources/items/weapons/bow.tres"
)


func test_initializes_with_a_valid_weapon() -> void:
	var starting_weapon := _create_weapon(&"starting_weapon")
	var equipment := WeaponEquipment.new(starting_weapon)

	assert_same(equipment.equipped_weapon, starting_weapon)


func test_swap_is_atomic_and_emits_each_change_once() -> void:
	var starting_weapon := _create_weapon(&"starting_weapon")
	var incoming_weapon := _create_weapon(&"incoming_weapon")
	var inventory := InventoryData.new(1)
	inventory.add_item(incoming_weapon)
	var equipment := WeaponEquipment.new(starting_weapon)
	watch_signals(inventory)
	watch_signals(equipment)

	assert_true(equipment.swap_from_inventory(inventory, 0))

	assert_same(equipment.equipped_weapon, incoming_weapon)
	assert_same(inventory.item_at(0), starting_weapon)
	assert_signal_emit_count(inventory, &"inventory_changed", 1)
	assert_signal_emit_count(equipment, &"equipped_weapon_changed", 1)
	assert_signal_emitted_with_parameters(
		equipment,
		&"equipped_weapon_changed",
		[starting_weapon, incoming_weapon],
	)


func test_swap_rejects_non_weapon_without_changing_either_owner() -> void:
	var starting_weapon := _create_weapon(&"starting_weapon")
	var ordinary_item := ItemData.create(&"potion", "Potion", TEST_TEXTURE)
	var inventory := InventoryData.new(1)
	inventory.add_item(ordinary_item)
	var equipment := WeaponEquipment.new(starting_weapon)
	watch_signals(inventory)
	watch_signals(equipment)

	assert_false(equipment.swap_from_inventory(inventory, 0))

	assert_same(equipment.equipped_weapon, starting_weapon)
	assert_same(inventory.item_at(0), ordinary_item)
	assert_signal_emit_count(inventory, &"inventory_changed", 0)
	assert_signal_emit_count(equipment, &"equipped_weapon_changed", 0)


func test_swap_rejects_missing_inventory_invalid_index_and_empty_slot() -> void:
	var starting_weapon := _create_weapon(&"starting_weapon")
	var inventory := InventoryData.new(1)
	var equipment := WeaponEquipment.new(starting_weapon)
	watch_signals(equipment)

	assert_false(equipment.swap_from_inventory(null, 0))
	assert_false(equipment.swap_from_inventory(inventory, -1))
	assert_false(equipment.swap_from_inventory(inventory, 1))
	assert_false(equipment.swap_from_inventory(inventory, 0))

	assert_same(equipment.equipped_weapon, starting_weapon)
	assert_null(inventory.item_at(0))
	assert_signal_emit_count(equipment, &"equipped_weapon_changed", 0)


func test_swap_rejects_same_or_invalid_weapon_without_item_loss() -> void:
	var starting_weapon := _create_weapon(&"starting_weapon")
	var inventory := InventoryData.new(1)
	var equipment := WeaponEquipment.new(starting_weapon)
	inventory.add_item(starting_weapon)

	assert_false(equipment.swap_from_inventory(inventory, 0))
	assert_same(equipment.equipped_weapon, starting_weapon)
	assert_same(inventory.item_at(0), starting_weapon)

	var invalid_weapon := WeaponData.new()
	inventory.slots[0] = invalid_weapon
	assert_false(equipment.swap_from_inventory(inventory, 0))
	assert_same(equipment.equipped_weapon, starting_weapon)
	assert_same(inventory.item_at(0), invalid_weapon)


func test_stage_four_resources_swap_without_losing_any_weapon() -> void:
	var inventory := InventoryData.new(1)
	inventory.add_item(REGULAR_SWORD)
	var equipment := WeaponEquipment.new(WEAPON_AXE)

	assert_true(equipment.swap_from_inventory(inventory, 0))
	assert_same(equipment.equipped_weapon, REGULAR_SWORD)
	assert_same(inventory.item_at(0), WEAPON_AXE)

	assert_true(equipment.swap_from_inventory(inventory, 0))
	assert_same(equipment.equipped_weapon, WEAPON_AXE)
	assert_same(inventory.item_at(0), REGULAR_SWORD)


func test_bow_swaps_through_the_same_equipment_contract() -> void:
	var inventory := InventoryData.new(1)
	inventory.add_item(BOW)
	var equipment := WeaponEquipment.new(WEAPON_AXE)
	assert_true(equipment.swap_from_inventory(inventory, 0))
	assert_same(equipment.equipped_weapon, BOW)
	assert_same(inventory.item_at(0), WEAPON_AXE)


func _create_weapon(weapon_id: StringName) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.id = weapon_id
	weapon.display_name = String(weapon_id)
	weapon.icon = TEST_TEXTURE
	weapon.held_texture = TEST_TEXTURE
	weapon.base_damage = 10
	weapon.damage_variance = 0.10
	weapon.attack_interval_seconds = 0.5
	weapon.knockback_strength = 50
	weapon.attack_behavior_scene = MELEE_BEHAVIOR
	return weapon
