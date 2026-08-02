extends GdUnitTestSuite

## Integration checks for the seam between the map and the field of view: tile
## coordinate conversion, and blockers gathered from real room scenes. These load
## actual scenes, unlike the pure VisibilityMap suite.

const START_ROOM := "res://scenes/rooms/room_start.tscn"

# --- Coordinate conversion -------------------------------------------------------

func test_world_to_tile_floors_toward_negative_infinity() -> void:
	# Plain integer division truncates toward zero, which would map the whole strip
	# from -15..15 onto tile 0 and misplace the player west/north of the origin.
	assert_that(MapAssembler.world_to_tile(Vector2(0, 0))).is_equal(Vector2i(0, 0))
	assert_that(MapAssembler.world_to_tile(Vector2(15, 15))).is_equal(Vector2i(0, 0))
	assert_that(MapAssembler.world_to_tile(Vector2(16, 16))).is_equal(Vector2i(1, 1))
	assert_that(MapAssembler.world_to_tile(Vector2(-1, -1))).is_equal(Vector2i(-1, -1))
	assert_that(MapAssembler.world_to_tile(Vector2(-16, -16))).is_equal(Vector2i(-1, -1))
	assert_that(MapAssembler.world_to_tile(Vector2(-17, -17))).is_equal(Vector2i(-2, -2))

# --- Blockers from a real room ---------------------------------------------------

## A start room added to the tree and finalized with the given connection flags.
## Doors only seal once the node is inside the tree, so the caller must await a frame
## before the walls reflect sealing.
func _room_with(connected: Array[bool]) -> Room:
	var scene: PackedScene = load(START_ROOM)
	var room: Room = scene.instantiate()
	add_child(room)
	await get_tree().process_frame
	room.setup(connected)
	return room

func test_sealing_a_door_adds_wall_cells() -> void:
	var open: Room = await _room_with([true, true, true, true] as Array[bool])
	var open_walls := open.get_wall_cells().size()

	var sealed: Room = await _room_with([false, false, false, false] as Array[bool])
	var sealed_walls := sealed.get_wall_cells().size()

	# Every sealed doorway stamps a wall into the gap the author left open.
	assert_int(sealed_walls).is_greater(open_walls)

func test_open_doorways_leave_a_gap_but_sealed_ones_do_not() -> void:
	var open: Room = await _room_with([true, true, true, true] as Array[bool])
	var open_cells := open.get_wall_cells()
	var sealed: Room = await _room_with([false, false, false, false] as Array[bool])
	var sealed_cells := sealed.get_wall_cells()

	for door in open.get_doors():
		var gap := Door.opening_cells(door.get_threshold_cell(), door.direction, door.width)
		# The authored opening leaves at least one cell clear while connected...
		var clear := 0
		for c: Vector2i in gap:
			if not open_cells.has(c):
				clear += 1
		assert_int(clear) \
			.override_failure_message("door %s has no clear cell while connected" % door.name) \
			.is_greater(0)
		# ...and nothing clear once sealed, so sight cannot leak through.
		for c: Vector2i in gap:
			assert_bool(sealed_cells.has(c)) \
				.override_failure_message("sealed door %s left cell %s open" % [door.name, c]) \
				.is_true()

func test_blockers_translate_from_room_local_to_world() -> void:
	# A room placed away from the origin must contribute blockers offset by its
	# origin, not raw room-local cells.
	var room: Room = await _room_with([false, false, false, false] as Array[bool])
	var origin := Vector2i(40, -25)
	var vm := VisibilityMap.new()
	for cell in room.get_wall_cells():
		vm.set_blocker(origin + cell)

	for cell in room.get_wall_cells():
		assert_bool(vm.is_blocker(origin + cell)).is_true()
	# The un-translated cell is only a blocker by coincidence if the offset is zero.
	assert_bool(vm.is_blocker(room.get_wall_cells()[0])).is_false()

func test_a_sealed_room_traps_sight_inside_itself() -> void:
	# The end-to-end guarantee: with every door sealed, nothing outside the room's
	# footprint may be lit from within it.
	var room: Room = await _room_with([false, false, false, false] as Array[bool])
	var vm := VisibilityMap.new()
	for cell in room.get_wall_cells():
		vm.set_blocker(cell)

	var bounds := room.get_bounds()
	vm.update_from(Vector2i(4, 4), 30)
	for cell: Vector2i in vm.visible_cells():
		assert_bool(bounds.has_point(cell)) \
			.override_failure_message("sight escaped a fully sealed room at %s" % cell) \
			.is_true()
