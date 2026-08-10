extends GdUnitTestSuite

## Unit tests for the procedural map system's pure logic. Everything here runs
## without a SceneTree: templates are built by hand, so the door-matching,
## alignment, overlap, and determinism guarantees are tested in isolation.

func _template(id: String, w: int, h: int, doors: Array[RoomDoor], tags: Array[StringName], weight: float) -> RoomTemplate:
	var t := RoomTemplate.new()
	t.id = StringName(id)
	# Footprint = floor (0..w-1, 0..h-1) plus a 1-tile wall ring around it.
	t.bounds = Rect2i(-1, -1, w + 2, h + 2)
	t.doors = doors
	t.tags = tags
	t.weight = weight
	return t

func _catalog() -> Array[RoomTemplate]:
	var start := _template("start", 9, 9, [
		RoomDoor.new(Vector2i(4, -1), Door.Direction.NORTH),
		RoomDoor.new(Vector2i(4, 9), Door.Direction.SOUTH),
		RoomDoor.new(Vector2i(9, 4), Door.Direction.EAST),
		RoomDoor.new(Vector2i(-1, 4), Door.Direction.WEST),
	] as Array[RoomDoor], [&"start"] as Array[StringName], 1.0)
	var hall := _template("hall", 11, 5, [
		RoomDoor.new(Vector2i(-1, 2), Door.Direction.WEST),
		RoomDoor.new(Vector2i(11, 2), Door.Direction.EAST),
	] as Array[RoomDoor], [&"combat"] as Array[StringName], 2.0)
	var junction := _template("junction", 9, 9, [
		RoomDoor.new(Vector2i(4, -1), Door.Direction.NORTH),
		RoomDoor.new(Vector2i(4, 9), Door.Direction.SOUTH),
		RoomDoor.new(Vector2i(9, 4), Door.Direction.EAST),
	] as Array[RoomDoor], [&"combat"] as Array[StringName], 1.5)
	return [start, hall, junction] as Array[RoomTemplate]

# --- Door compatibility --------------------------------------------------------

func test_doors_connect_only_when_facing_opposite() -> void:
	var north := RoomDoor.new(Vector2i.ZERO, Door.Direction.NORTH)
	var south := RoomDoor.new(Vector2i.ZERO, Door.Direction.SOUTH)
	var east := RoomDoor.new(Vector2i.ZERO, Door.Direction.EAST)
	assert_bool(north.is_compatible(south)).is_true()
	assert_bool(north.is_compatible(east)).is_false()
	assert_bool(north.is_compatible(north)).is_false()

func test_doors_require_matching_width() -> void:
	var single := RoomDoor.new(Vector2i.ZERO, Door.Direction.NORTH, 1)
	var double := RoomDoor.new(Vector2i.ZERO, Door.Direction.SOUTH, 2)
	assert_bool(single.is_compatible(double)).is_false()

func test_direction_helpers() -> void:
	assert_that(Door.direction_vector(Door.Direction.NORTH)).is_equal(Vector2i(0, -1))
	assert_that(Door.direction_vector(Door.Direction.EAST)).is_equal(Vector2i(1, 0))
	assert_that(Door.opposite(Door.Direction.WEST)).is_equal(Door.Direction.EAST)

# --- Alignment -----------------------------------------------------------------

func test_alignment_puts_thresholds_one_tile_apart() -> void:
	var host_origin := Vector2i(0, 0)
	var host_door := RoomDoor.new(Vector2i(4, -1), Door.Direction.NORTH)
	var new_door := RoomDoor.new(Vector2i(4, 9), Door.Direction.SOUTH)
	var new_origin := MapGenerator.aligned_origin(host_origin, host_door, new_door)
	var host_world: Vector2i = host_origin + host_door.cell
	var new_world: Vector2i = new_origin + new_door.cell
	# The neighbour's threshold sits exactly one tile out the host's north side.
	assert_that(new_world).is_equal(host_world + Door.direction_vector(Door.Direction.NORTH))

func test_double_wide_doors_line_up_across_a_connection() -> void:
	# Two 2-wide doors facing each other. Their openings must coincide once aligned,
	# not spread apart by (width - 1) tiles.
	var host := RoomDoor.new(Vector2i(4, -1), Door.Direction.NORTH, 2)
	var mate := RoomDoor.new(Vector2i(4, 9), Door.Direction.SOUTH, 2)
	assert_bool(host.is_compatible(mate)).is_true()

	var host_origin := Vector2i.ZERO
	var mate_origin := MapGenerator.aligned_origin(host_origin, host, mate)
	var outward := Door.direction_vector(Door.Direction.NORTH)
	var host_cells := _world_opening(host_origin, host)
	var mate_cells := _world_opening(mate_origin, mate)

	# The neighbour's opening is exactly the host's opening shifted one tile outward,
	# so the two gaps align perpendicular to the doorway with no half-tile offset.
	assert_int(mate_cells.size()).is_equal(2)
	assert_int(host_cells.size()).is_equal(2)
	for c in host_cells:
		assert_bool(mate_cells.has(c + outward)).is_true()

## World-space cells an opening covers, for alignment assertions.
func _world_opening(origin: Vector2i, d: RoomDoor) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in Door.opening_cells(d.cell, d.direction, d.width):
		result.append(origin + c)
	return result

# --- Overlap -------------------------------------------------------------------

func test_interior_overlap_detection() -> void:
	var room := _template("r", 5, 5, [] as Array[RoomDoor], [] as Array[StringName], 1.0)
	# Same spot overlaps itself.
	assert_bool(room.interior(Vector2i.ZERO).intersects(room.interior(Vector2i.ZERO))).is_true()
	# Far apart does not.
	assert_bool(room.interior(Vector2i.ZERO).intersects(room.interior(Vector2i(100, 0)))).is_false()
	# Neighbours sharing only a wall line do not overlap in the interior.
	assert_bool(room.interior(Vector2i.ZERO).intersects(room.interior(Vector2i(6, 0)))).is_false()

# --- Generator invariants ------------------------------------------------------

func test_generation_produces_no_overlapping_rooms() -> void:
	var gen := MapGenerator.new()
	gen.target_rooms = 10
	var placements := gen.generate(_catalog(), 42)
	assert_int(placements.size()).is_greater(1)
	assert_int(placements.size()).is_less_equal(10)
	for i in placements.size():
		for j in range(i + 1, placements.size()):
			var a := placements[i].template.interior(placements[i].origin)
			var b := placements[j].template.interior(placements[j].origin)
			assert_bool(a.intersects(b)).is_false()

func test_same_seed_is_deterministic() -> void:
	var gen := MapGenerator.new()
	gen.target_rooms = 10
	var a := gen.generate(_catalog(), 123)
	var b := gen.generate(_catalog(), 123)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_that(a[i].origin).is_equal(b[i].origin)
		assert_that(a[i].template.id).is_equal(b[i].template.id)

func test_start_room_is_placed_exactly_once() -> void:
	var gen := MapGenerator.new()
	gen.target_rooms = 12
	var placements := gen.generate(_catalog(), 7)
	var starts := 0
	for p in placements:
		if p.template.has_tag(&"start"):
			starts += 1
	assert_int(starts).is_equal(1)

func test_start_room_is_at_origin() -> void:
	var gen := MapGenerator.new()
	var placements := gen.generate(_catalog(), 99)
	assert_that(placements[0].origin).is_equal(Vector2i.ZERO)
	assert_bool(placements[0].template.has_tag(&"start")).is_true()

# --- Connectors ----------------------------------------------------------------

func test_aligned_origin_gap_spaces_the_far_door() -> void:
	# gap tiles between the two thresholds: 1 when rooms sit flush, length + 1 with a
	# corridor between them.
	var host_origin := Vector2i.ZERO
	var host_door := RoomDoor.new(Vector2i(4, -1), Door.Direction.NORTH)
	var new_door := RoomDoor.new(Vector2i(4, 9), Door.Direction.SOUTH)
	var origin := MapGenerator.aligned_origin(host_origin, host_door, new_door, 4)  # length 3
	var host_world: Vector2i = host_origin + host_door.cell
	var new_world: Vector2i = origin + new_door.cell
	assert_that(new_world).is_equal(host_world + Door.direction_vector(Door.Direction.NORTH) * 4)

func test_every_connection_gets_one_connector() -> void:
	# The layout is a tree grown from the start room, so each room past the first is
	# joined by exactly one corridor.
	var gen := MapGenerator.new()
	gen.target_rooms = 10
	var placements := gen.generate(_catalog(), 42)
	assert_int(gen.connectors.size()).is_equal(placements.size() - 1)

func test_connector_floor_never_enters_a_room_interior() -> void:
	# The whole point: a corridor sits in open space between rooms, so no room's interior
	# is ever crossed by connector floor.
	var gen := MapGenerator.new()
	gen.target_rooms = 12
	var placements := gen.generate(_catalog(), 7)
	for conn in gen.connectors:
		for cell in conn.floor_cells():
			for pl in placements:
				assert_bool(pl.template.interior(pl.origin).has_point(cell)) \
					.override_failure_message("connector floor %s sits inside a room" % cell) \
					.is_false()

func test_connectors_do_not_overlap_each_other() -> void:
	var gen := MapGenerator.new()
	gen.target_rooms = 12
	gen.generate(_catalog(), 256)
	for i in gen.connectors.size():
		for j in range(i + 1, gen.connectors.size()):
			assert_bool(gen.connectors[i].footprint().intersects(gen.connectors[j].footprint())) \
				.override_failure_message("two corridors overlap").is_false()

func test_connectors_are_deterministic() -> void:
	var a := MapGenerator.new()
	a.target_rooms = 12
	var b := MapGenerator.new()
	b.target_rooms = 12
	a.generate(_catalog(), 77)
	b.generate(_catalog(), 77)
	assert_int(a.connectors.size()).is_equal(b.connectors.size())
	for i in a.connectors.size():
		assert_that(a.connectors[i].origin).is_equal(b.connectors[i].origin)
		assert_int(a.connectors[i].length).is_equal(b.connectors[i].length)

func test_connector_geometry_matches_its_direction_and_size() -> void:
	# A north-running corridor, length 3, width 3, mouth at the origin. width counts the
	# whole passage — wall · floor · wall — so the walls sit on the outer columns (x = 0 and
	# x = 2) and the single floor column runs up the middle (x = 1), s = 1..3 north (-y).
	var conn := Connector.new(Vector2i(0, 0), Door.Direction.NORTH, 3, 3)
	assert_int(conn.floor_cells().size()).is_equal(3)
	assert_int(conn.wall_cells().size()).is_equal(6)
	assert_bool(conn.floor_cells().has(Vector2i(1, -1))).is_true()
	assert_bool(conn.floor_cells().has(Vector2i(1, -3))).is_true()
	assert_bool(conn.near_wall_cells().has(Vector2i(0, -1))).is_true()
	assert_bool(conn.far_wall_cells().has(Vector2i(2, -1))).is_true()
	assert_that(conn.footprint()).is_equal(Rect2i(0, -3, 3, 3))

# --- Compactness ---------------------------------------------------------------

## Mean Chebyshev distance from the origin to each room's centre: the summary
## statistic compactness is meant to move.
func _spread(placements: Array[Placement]) -> float:
	if placements.is_empty():
		return 0.0
	var total := 0.0
	for p in placements:
		var rect := p.template.footprint(p.origin)
		var centre := rect.position + rect.size / 2
		total += float(maxi(absi(centre.x), absi(centre.y)))
	return total / float(placements.size())

func test_compact_layouts_stay_closer_to_the_origin_than_sprawling_ones() -> void:
	# Averaged over several seeds: the bias is statistical, so any single seed may
	# buck the trend even though the tendency across runs is reliable.
	var compact_total := 0.0
	var sprawl_total := 0.0
	var seeds := [1, 7, 13, 42, 99, 256, 1337, 2024]
	for s: int in seeds:
		var compact := MapGenerator.new()
		compact.target_rooms = 14
		compact.compactness = 1.0
		compact_total += _spread(compact.generate(_catalog(), s))

		var sprawling := MapGenerator.new()
		sprawling.target_rooms = 14
		sprawling.compactness = 0.0
		sprawl_total += _spread(sprawling.generate(_catalog(), s))

	assert_float(compact_total).is_less(sprawl_total)

func test_compactness_extremes_still_produce_valid_layouts() -> void:
	for c: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var gen := MapGenerator.new()
		gen.target_rooms = 12
		gen.compactness = c
		var placements := gen.generate(_catalog(), 5150)
		assert_int(placements.size()).is_greater(1)
		assert_int(placements.size()).is_less_equal(12)
		# The core invariant must survive every setting of the knob.
		for i in placements.size():
			for j in range(i + 1, placements.size()):
				var a := placements[i].template.interior(placements[i].origin)
				var b := placements[j].template.interior(placements[j].origin)
				assert_bool(a.intersects(b)).is_false()

func test_compactness_layouts_are_deterministic() -> void:
	var a := MapGenerator.new()
	a.target_rooms = 12
	a.compactness = 0.9
	var b := MapGenerator.new()
	b.target_rooms = 12
	b.compactness = 0.9
	var first := a.generate(_catalog(), 77)
	var second := b.generate(_catalog(), 77)
	assert_int(first.size()).is_equal(second.size())
	for i in first.size():
		assert_that(first[i].origin).is_equal(second[i].origin)
		assert_that(first[i].template.id).is_equal(second[i].template.id)
