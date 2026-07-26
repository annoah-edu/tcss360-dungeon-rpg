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
