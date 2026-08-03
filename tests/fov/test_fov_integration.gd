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

## Rasterize a room's authored + door occluders into a field, the way the assembler
## does, so occlusion can be queried per pixel.
func _occluder_field(room: Room) -> BlockerField:
	var field := BlockerField.new()
	for poly in room.get_occluder_polygons():
		field.add_polygon(poly)
	return field

func test_an_open_doorway_leaves_the_occluder_gap_clear() -> void:
	# The fog must pour through a connected doorway. Occlusion follows the walls, so a
	# cell in the opening that carries no wall tile — the actual passage — must not
	# occlude. (A door may be declared wider than its authored gap, in which case the
	# flanking cells are genuine wall and rightly stay solid; only the open passage is
	# tested here.)
	var open: Room = await _room_with([true, true, true, true] as Array[bool])
	var field := _occluder_field(open)
	var walls := open.get_wall_cells()
	var passage_cells := 0
	for door in open.get_doors():
		for cell in Door.opening_cells(door.get_threshold_cell(), door.direction, door.width):
			if walls.has(cell):
				continue   # a jamb / narrow-gap wall cell; correct that it occludes
			passage_cells += 1
			assert_bool(field.is_solid_at(cell, Vector2i(8, 8))) \
				.override_failure_message("open door %s occludes passage cell %s" % [door.name, cell]) \
				.is_false()
	# Guard the test itself: there must be some open passage, or it proves nothing.
	assert_int(passage_cells).override_failure_message("no open passage cell found").is_greater(0)

## Strip any hand-authored seal occluders from a room's doors, forcing the door to fall
## back to its computed occluder. Rooms are authored by hand and their door occluders
## change, so a seal test must not depend on them being drawn — this isolates the engine's
## fallback path.
func _strip_door_occluders(room: Room) -> void:
	for door in room.get_doors():
		var doomed: Array[Node] = []
		for c in door.get_children():
			if c is LightOccluder2D:
				doomed.append(c)
		for c in doomed:
			door.remove_child(c)
			c.free()

func test_a_sealed_door_plugs_its_gap_via_the_fallback_occluder() -> void:
	# The special case: sealing plugs the wall tile AND the occluder hole, or the fog
	# would stream through a door the player sees as shut. Tested on the computed fallback
	# (authored door occluders removed first), so it holds regardless of a room's authoring.
	var scene: PackedScene = load(START_ROOM)
	var sealed: Room = scene.instantiate()
	add_child(sealed)
	_strip_door_occluders(sealed)
	await get_tree().process_frame
	sealed.setup([false, false, false, false] as Array[bool])
	var field := _occluder_field(sealed)
	for door in sealed.get_doors():
		for cell in Door.opening_cells(door.get_threshold_cell(), door.direction, door.width):
			assert_bool(field.is_solid_at(cell, Vector2i(8, 8))) \
				.override_failure_message("sealed door %s left cell %s see-through" % [door.name, cell]) \
				.is_true()

## Attach a hand-authored seal occluder to a door, shaped as a triangle so it is
## distinguishable from every rectangular wall/procedural occluder in the results.
func _mark_door_with_occluder(door: Door) -> void:
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(0, 6)])
	var occ := LightOccluder2D.new()
	occ.name = "AuthoredSealMark"
	occ.occluder = poly
	door.add_child(occ)

func _authored_marks(room: Room) -> int:
	var n := 0
	for poly in room.get_occluder_polygons():
		if poly.size() == 3:   # only the triangle marker has three vertices
			n += 1
	return n

func test_authored_door_occluder_contributes_only_when_sealed() -> void:
	# The authoring convenience: draw the seal occluder as a child of the door. It must
	# block sight when the door seals and be ignored while it stays open — the door
	# hides it, and Room.get_occluder_polygons skips hidden occluders.
	var scene: PackedScene = load(START_ROOM)

	var sealed: Room = scene.instantiate()
	add_child(sealed)
	_mark_door_with_occluder(sealed.get_doors()[0])
	await get_tree().process_frame
	sealed.setup([false, false, false, false] as Array[bool])
	assert_int(_authored_marks(sealed)) \
		.override_failure_message("sealed door's authored occluder should count").is_equal(1)

	var open: Room = scene.instantiate()
	add_child(open)
	_mark_door_with_occluder(open.get_doors()[0])
	await get_tree().process_frame
	open.setup([true, true, true, true] as Array[bool])
	assert_int(_authored_marks(open)) \
		.override_failure_message("open door's authored occluder should be ignored").is_equal(0)

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
