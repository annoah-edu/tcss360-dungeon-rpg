extends GdUnitTestSuite

## Unit tests for the field-of-view core. Like the map generator suite, everything
## here is pure logic with no SceneTree: blockers are placed by hand so occlusion,
## symmetry, and the remembered-tile guarantee are tested in isolation.

func _open_map() -> VisibilityMap:
	return VisibilityMap.new()

## A map walled along `x = wall_x`, spanning y in [-span, span].
func _wall_column(wall_x: int, span: int) -> VisibilityMap:
	var vm := VisibilityMap.new()
	for y in range(-span, span + 1):
		vm.set_blocker(Vector2i(wall_x, y))
	return vm

# --- Basic lighting --------------------------------------------------------------

func test_origin_is_always_visible() -> void:
	var vm := _open_map()
	vm.update_from(Vector2i.ZERO, 5)
	assert_bool(vm.is_visible_cell(Vector2i.ZERO)).is_true()

func test_zero_radius_lights_only_the_origin() -> void:
	var vm := _open_map()
	vm.update_from(Vector2i.ZERO, 0)
	assert_int(vm.visible_count()).is_equal(1)
	assert_bool(vm.is_visible_cell(Vector2i.ZERO)).is_true()

func test_open_field_lights_a_round_pool() -> void:
	var vm := _open_map()
	var radius := 6
	vm.update_from(Vector2i.ZERO, radius)
	# Cells are measured to their far edge, so the bound is (r + 0.5)^2 rather than
	# r^2 — a strict centre test notches the cardinal extremes into a lumpy cross.
	var limit := (radius + 0.5) * (radius + 0.5)
	for c: Vector2i in vm.visible_cells():
		assert_float(float(c.x * c.x + c.y * c.y)).is_less_equal(limit)
	# Round, not square: the far corner is well outside the radius and stays dark,
	# while the cardinal extreme is lit.
	assert_bool(vm.is_visible_cell(Vector2i(radius, radius))).is_false()
	assert_bool(vm.is_visible_cell(Vector2i(radius, 0))).is_true()

func test_player_inside_a_wall_still_sees_its_own_tile() -> void:
	# Degenerate but reachable (spawning in a doorway that later seals).
	var vm := VisibilityMap.new()
	vm.set_blocker(Vector2i.ZERO)
	vm.update_from(Vector2i.ZERO, 4)
	assert_bool(vm.is_visible_cell(Vector2i.ZERO)).is_true()

# --- Occlusion -------------------------------------------------------------------

func test_walls_block_sight_behind_them() -> void:
	var vm := _wall_column(3, 8)
	vm.update_from(Vector2i.ZERO, 10)
	# The wall itself is lit, so the room boundary is drawn...
	assert_bool(vm.is_visible_cell(Vector2i(3, 0))).is_true()
	# ...but nothing directly behind it is.
	assert_bool(vm.is_visible_cell(Vector2i(4, 0))).is_false()
	assert_bool(vm.is_visible_cell(Vector2i(5, 0))).is_false()

func test_sight_passes_through_a_gap_in_a_wall() -> void:
	# A wall with a one-cell doorway at y = 0 must let sight through the gap.
	var vm := VisibilityMap.new()
	for y in range(-8, 9):
		if y != 0:
			vm.set_blocker(Vector2i(3, y))
	vm.update_from(Vector2i.ZERO, 10)
	assert_bool(vm.is_visible_cell(Vector2i(4, 0))).is_true()
	# Well off the gap's axis stays shadowed.
	assert_bool(vm.is_visible_cell(Vector2i(5, 4))).is_false()

func test_blockers_do_not_light_the_far_side_of_a_closed_room() -> void:
	# Fully enclose the origin; only the box interior and its walls may light up.
	var vm := VisibilityMap.new()
	for x in range(-2, 3):
		for y in range(-2, 3):
			if absi(x) == 2 or absi(y) == 2:
				vm.set_blocker(Vector2i(x, y))
	vm.update_from(Vector2i.ZERO, 12)
	for c: Vector2i in vm.visible_cells():
		assert_bool(absi(c.x) <= 2 and absi(c.y) <= 2).is_true()

# --- Symmetry --------------------------------------------------------------------

## Two rooms sharing a wall with a doorway between them — the shape MapGenerator
## actually emits, and the case where wedge-edge asymmetry would otherwise appear.
func _two_rooms() -> VisibilityMap:
	var vm := VisibilityMap.new()
	for room_x in [0, 10]:
		for x in range(room_x - 1, room_x + 10):
			for y in range(-1, 10):
				if x == room_x - 1 or x == room_x + 9 or y == -1 or y == 9:
					vm.set_blocker(Vector2i(x, y))
	vm.set_blocker(Vector2i(9, 4), false)
	vm.set_blocker(Vector2i(10, 4), false)
	return vm

func test_visibility_is_symmetric_in_room_geometry() -> void:
	# If A sees B, B must see A. Asymmetry reads in game as enemies attacking from
	# tiles the player cannot see back into. Raw shadowcasting does not guarantee
	# this on its own; VisibilityMap adds a pruning pass (enforce_symmetry) to get it.
	var radius := 8
	var origin := Vector2i(6, 4)  # near the doorway, where the wedge fans out
	var vm := _two_rooms()
	vm.update_from(origin, radius)

	for cell: Vector2i in vm.visible_cells():
		if vm.is_blocker(cell):
			continue  # Walls are lit when hit; sight *from* inside one is meaningless.
		var reverse := _two_rooms()
		reverse.update_from(cell, radius)
		assert_bool(reverse.is_visible_cell(origin)) \
			.override_failure_message("%s is visible from %s but not vice versa" % [cell, origin]) \
			.is_true()

func test_symmetry_holds_from_every_tile_in_a_room() -> void:
	# Sweep every standing position rather than trusting a single vantage point.
	var radius := 8
	for x in range(0, 9):
		for y in range(0, 9):
			var origin := Vector2i(x, y)
			var vm := _two_rooms()
			if vm.is_blocker(origin):
				continue
			vm.update_from(origin, radius)
			for cell: Vector2i in vm.visible_cells():
				if vm.is_blocker(cell):
					continue
				var reverse := _two_rooms()
				reverse.update_from(cell, radius)
				assert_bool(reverse.is_visible_cell(origin)) \
					.override_failure_message("%s sees %s but not the reverse" % [origin, cell]) \
					.is_true()

func test_symmetry_pass_can_be_disabled() -> void:
	# The knob exists so the raw cast can be isolated; with it off the pruning simply
	# does not run, so the lit set is a superset of the enforced one.
	var strict := _two_rooms()
	strict.update_from(Vector2i(6, 4), 8)
	var raw := _two_rooms()
	raw.enforce_symmetry = false
	raw.update_from(Vector2i(6, 4), 8)
	assert_int(raw.visible_count()).is_greater_equal(strict.visible_count())
	for c: Vector2i in strict.visible_cells():
		assert_bool(raw.is_visible_cell(c)).is_true()

# --- Remembered tiles ------------------------------------------------------------

func test_seen_tiles_are_remembered_after_moving_away() -> void:
	var vm := _open_map()
	vm.update_from(Vector2i.ZERO, 3)
	assert_that(vm.state_of(Vector2i.ZERO)).is_equal(VisibilityMap.State.VISIBLE)

	# Walk far enough that the origin drops out of the light pool.
	vm.update_from(Vector2i(50, 50), 3)
	assert_that(vm.state_of(Vector2i.ZERO)).is_equal(VisibilityMap.State.REMEMBERED)
	assert_bool(vm.is_seen(Vector2i.ZERO)).is_true()
	assert_bool(vm.is_visible_cell(Vector2i.ZERO)).is_false()

func test_seen_set_only_grows() -> void:
	var vm := _open_map()
	vm.update_from(Vector2i.ZERO, 4)
	var after_first := vm.seen_count()
	vm.update_from(Vector2i(20, 0), 4)
	assert_int(vm.seen_count()).is_greater(after_first)
	# Revisiting ground already covered adds nothing new.
	var after_second := vm.seen_count()
	vm.update_from(Vector2i.ZERO, 4)
	assert_int(vm.seen_count()).is_equal(after_second)

func test_symmetry_pruning_never_erases_a_legitimately_seen_tile() -> void:
	# Pruning removes cells the cast lit spuriously, and must not clear their seen
	# state — but a tile genuinely seen from a good vantage point has to stay
	# remembered even if a later frame's cast rejects it.
	var vm := _two_rooms()
	var spot := Vector2i(4, 4)
	vm.update_from(spot, 8)
	assert_that(vm.state_of(spot)).is_equal(VisibilityMap.State.VISIBLE)

	# Walk around the room; the tile must never fall back to UNSEEN.
	for x in range(1, 9):
		vm.update_from(Vector2i(x, 7), 8)
		assert_that(vm.state_of(spot)).is_not_equal(VisibilityMap.State.UNSEEN)

func test_never_seen_tiles_report_unseen() -> void:
	var vm := _open_map()
	vm.update_from(Vector2i.ZERO, 3)
	assert_that(vm.state_of(Vector2i(100, 100))).is_equal(VisibilityMap.State.UNSEEN)

func test_reset_clears_all_state() -> void:
	var vm := _wall_column(3, 4)
	vm.update_from(Vector2i.ZERO, 5)
	vm.reset()
	assert_int(vm.seen_count()).is_equal(0)
	assert_int(vm.visible_count()).is_equal(0)
	assert_int(vm.blocker_count()).is_equal(0)

# --- Blocker bookkeeping ---------------------------------------------------------

func test_registering_the_same_blocker_twice_is_idempotent() -> void:
	# Adjacent rooms share a wall line, so both register the shared cells.
	var vm := VisibilityMap.new()
	vm.set_blocker(Vector2i(1, 1))
	vm.set_blocker(Vector2i(1, 1))
	assert_int(vm.blocker_count()).is_equal(1)
	vm.set_blocker(Vector2i(1, 1), false)
	assert_bool(vm.is_blocker(Vector2i(1, 1))).is_false()

func test_update_is_deterministic() -> void:
	var a := _wall_column(4, 6)
	var b := _wall_column(4, 6)
	a.update_from(Vector2i(-2, 1), 7)
	b.update_from(Vector2i(-2, 1), 7)
	assert_int(a.visible_count()).is_equal(b.visible_count())
	for c: Vector2i in a.visible_cells():
		assert_bool(b.is_visible_cell(c)).is_true()
