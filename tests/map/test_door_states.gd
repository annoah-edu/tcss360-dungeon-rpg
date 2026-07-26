extends GdUnitTestSuite

## Tests for the data-driven door state system: presentation resolves to the
## highest-priority active state, and the Door state-set API behaves.

func test_resolve_picks_highest_priority() -> void:
	var lib := DoorStateLibrary.create_default()
	var style := lib.resolve([&"locked", &"boss"] as Array[StringName])
	assert_int(style.priority).is_equal(50)  # boss outranks locked

func test_open_does_not_block() -> void:
	var lib := DoorStateLibrary.create_default()
	assert_bool(lib.resolve([&"open"] as Array[StringName]).blocks).is_false()

func test_sealed_blocks() -> void:
	var lib := DoorStateLibrary.create_default()
	assert_bool(lib.resolve([&"sealed"] as Array[StringName]).blocks).is_true()

func test_no_states_resolves_to_null() -> void:
	var lib := DoorStateLibrary.create_default()
	assert_that(lib.resolve([] as Array[StringName])).is_null()

func test_static_states_are_tile_based() -> void:
	var lib := DoorStateLibrary.create_default()
	assert_int(lib.resolve([&"open"] as Array[StringName]).presentation).is_equal(DoorStateStyle.Presentation.OPEN)
	assert_int(lib.resolve([&"sealed"] as Array[StringName]).presentation).is_equal(DoorStateStyle.Presentation.WALL_TILE)

func test_interactive_state_is_entity() -> void:
	var lib := DoorStateLibrary.create_default()
	assert_int(lib.resolve([&"boss"] as Array[StringName]).presentation).is_equal(DoorStateStyle.Presentation.ENTITY)

func test_unknown_state_is_ignored() -> void:
	var lib := DoorStateLibrary.create_default()
	assert_that(lib.resolve([&"does_not_exist"] as Array[StringName])).is_null()

func test_door_state_membership() -> void:
	var door := Door.new()
	door.set_states([&"boss"] as Array[StringName])
	assert_bool(door.has_state(&"boss")).is_true()
	assert_bool(door.has_state(&"open")).is_false()
	door.add_state(&"locked")
	assert_bool(door.has_state(&"locked")).is_true()
	door.remove_state(&"boss")
	assert_bool(door.has_state(&"boss")).is_false()
	door.free()
