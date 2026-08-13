extends GdUnitTestSuite

## Tests for the wall texture handed to the field-of-view shader. This is pure data —
## the shader's use of it is verified separately against rendered pixels.
##
## Occlusion (red channel) is authored as polygons and rasterized here; drawn masonry
## (blue) comes from the tile sprites. A bare add() marks a whole cell in both, which is
## what most of the registration/packing tests below lean on.

func _field_with(cells: Array[Vector2i]) -> BlockerField:
	var f := BlockerField.new()
	f.add_all(cells)
	return f

## A closed rectangle polygon in pixels, for feeding add_polygon.
func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])

## Whether a world pixel occludes, addressed the way the field stores it.
func _solid_world(f: BlockerField, wx: int, wy: int) -> bool:
	var ts := f.tile_size
	var cell := Vector2i(floori(wx / float(ts)), floori(wy / float(ts)))
	return f.is_solid_at(cell, Vector2i(wx - cell.x * ts, wy - cell.y * ts))

# --- Registration ----------------------------------------------------------------

func test_registering_the_same_wall_twice_is_idempotent() -> void:
	# Neighbouring rooms share a wall line, so both register the shared cells.
	var f := BlockerField.new()
	f.add(Vector2i(3, 4))
	f.add(Vector2i(3, 4))
	assert_int(f.wall_count()).is_equal(1)
	assert_bool(f.has_wall(Vector2i(3, 4))).is_true()

func test_empty_field_commits_to_nothing() -> void:
	# A dungeon with no walls must not produce a texture the shader would then march
	# through; callers skip the fog entirely instead.
	var f := BlockerField.new()
	assert_bool(f.commit()).is_false()
	assert_object(f.texture).is_null()

func test_clear_drops_everything() -> void:
	var f := _field_with([Vector2i.ZERO, Vector2i(1, 1)] as Array[Vector2i])
	f.add_polygon(_rect(0, 0, 16, 16))
	f.commit()
	f.clear()
	assert_int(f.wall_count()).is_equal(0)
	assert_object(f.texture).is_null()
	assert_bool(f.is_solid_at(Vector2i.ZERO, Vector2i(8, 8))).is_false()

# --- Packing ---------------------------------------------------------------------

func test_texture_covers_every_wall_with_a_margin() -> void:
	var walls: Array[Vector2i] = [Vector2i(0, 0), Vector2i(5, 3), Vector2i(-2, -4)]
	var f := _field_with(walls)
	assert_bool(f.commit(2)).is_true()

	# Bounds run from (-2,-4) to (5,3); a 2-cell margin pads both ends.
	assert_that(f.origin).is_equal(Vector2i(-4, -6))
	assert_that(f.size).is_equal(Vector2i(12, 12))
	for w in walls:
		var px: Vector2i = w - f.origin
		assert_bool(px.x >= 0 and px.y >= 0 and px.x < f.size.x and px.y < f.size.y).is_true()

func test_bounds_grow_to_cover_occluders_with_no_wall_cell() -> void:
	# An occluder can be authored a hair past the wall cells it belongs to; the grid must
	# still enclose it or its pixels fall off the texture edge.
	var f := BlockerField.new()
	f.add(Vector2i(0, 0))
	f.add_polygon(_rect(80, 80, 16, 16))   # cell (5,5), well past the lone wall
	f.commit(1)
	assert_bool(_solid_world(f, 88, 88)).is_true()
	var px: Vector2i = Vector2i(5, 5) - f.origin
	assert_bool(px.x >= 0 and px.y >= 0 and px.x < f.size.x and px.y < f.size.y) \
		.override_failure_message("occluder cell must be inside the grid").is_true()

func test_margin_keeps_walls_off_the_texture_edge() -> void:
	# The shader treats out-of-bounds samples as open floor, so a wall sitting on the
	# boundary would let sight leak around it.
	var f := _field_with([Vector2i(7, 7)] as Array[Vector2i])
	f.commit(2)
	var px: Vector2i = Vector2i(7, 7) - f.origin
	assert_int(px.x).is_greater(0)
	assert_int(px.y).is_greater(0)
	assert_int(px.x).is_less(f.size.x - 1)
	assert_int(px.y).is_less(f.size.y - 1)

func test_texture_marks_walls_and_leaves_floor_clear() -> void:
	# The texture is one pixel per *art pixel*, not per tile, so a wall cell occupies a
	# tile_size square in it.
	var f := _field_with([Vector2i(2, 2), Vector2i(3, 2)] as Array[Vector2i])
	f.commit()
	var img: Image = f.texture.get_image()
	var ts := f.tile_size

	for wall: Vector2i in [Vector2i(2, 2), Vector2i(3, 2)]:
		var base: Vector2i = (wall - f.origin) * ts
		assert_float(img.get_pixel(base.x + ts / 2, base.y + ts / 2).r) \
			.override_failure_message("wall %s should be marked" % wall) \
			.is_greater(0.5)
	# A cell between the walls' row and the margin is open.
	var open: Vector2i = (Vector2i(2, 4) - f.origin) * ts
	assert_float(img.get_pixel(open.x + ts / 2, open.y + ts / 2).r).is_less(0.5)

func test_texture_is_art_pixel_resolution() -> void:
	# Per-tile resolution cannot express a wall that does not fill its cell, which is
	# most of them — an east/west wall is a 6px pillar in a 16px cell.
	var f := _field_with([Vector2i.ZERO] as Array[Vector2i])
	f.commit(1)
	assert_that(f.texture.get_size()).is_equal(Vector2(f.size * f.tile_size))

func test_bare_add_marks_the_whole_cell() -> void:
	# Callers with no authored polygons get a conservative solid cell: over-blocking looks
	# wrong, but under-blocking would let the player see through walls.
	var f := _field_with([Vector2i(1, 1)] as Array[Vector2i])
	f.commit()
	for local: Vector2i in [Vector2i(0, 0), Vector2i(15, 15), Vector2i(8, 3)]:
		assert_bool(f.is_solid_at(Vector2i(1, 1), local)) \
			.override_failure_message("expected %s solid" % local) \
			.is_true()
	assert_bool(f.is_solid_at(Vector2i(5, 5), Vector2i(8, 8))).is_false()

func test_world_rect_matches_the_grid_in_pixels() -> void:
	var f := _field_with([Vector2i(0, 0), Vector2i(4, 4)] as Array[Vector2i])
	f.commit(1)
	var rect := f.world_rect(16)
	assert_that(rect.position).is_equal(f.origin * 16)
	assert_that(rect.size).is_equal(f.size * 16)

# --- Occluder polygons -----------------------------------------------------------

func test_polygon_fills_the_pixels_it_covers() -> void:
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 16))
	# Interior pixels occlude; a pixel just outside the rectangle does not.
	assert_bool(_solid_world(f, 0, 0)).is_true()
	assert_bool(_solid_world(f, 8, 8)).is_true()
	assert_bool(_solid_world(f, 15, 15)).is_true()
	assert_bool(_solid_world(f, 16, 16)).is_false()
	assert_bool(_solid_world(f, -1, 8)).is_false()

func test_polygon_offset_lands_in_world_space() -> void:
	# add_polygon shifts a room-local outline into the shared grid; the offset is where
	# a neighbour's overlapping outline meets this one.
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 16), Vector2(32, 48))
	assert_bool(_solid_world(f, 40, 56)).is_true()
	assert_bool(_solid_world(f, 8, 8)).is_false()

func test_polygon_shows_only_in_the_red_channel() -> void:
	# A polygon stops sight but is not drawn masonry, so it must not set blue — otherwise
	# the fog would refuse to veil it.
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 16))
	f.commit(1)
	var img: Image = f.texture.get_image()
	var base: Vector2i = (Vector2i.ZERO - f.origin) * f.tile_size
	var c := img.get_pixel(base.x + 8, base.y + 8)
	assert_float(c.r).override_failure_message("occluder should set red").is_greater(0.5)
	assert_float(c.b).override_failure_message("occluder is not masonry").is_less(0.5)

func test_channels_separate_occlusion_from_masonry() -> void:
	# Red (stops sight) and blue (drawn masonry) are independent data. Author a pillar of
	# masonry in one cell and an occluder in the next, and neither bleeds into the other's
	# channel.
	var f := BlockerField.new()
	var mask: Array[bool] = []
	mask.resize(f.tile_size * f.tile_size)
	mask.fill(false)
	for y in f.tile_size:
		for x in range(5, 11):
			mask[y * f.tile_size + x] = true
	f._cells[Vector2i.ZERO] = mask            # masonry only, cell (0,0)
	f.add_polygon(_rect(16, 0, 16, 16))       # occluder only, cell (1,0)
	f.commit(1)
	var img: Image = f.texture.get_image()

	var masonry := img.get_pixel((Vector2i.ZERO - f.origin).x * f.tile_size + 8,
		(Vector2i.ZERO - f.origin).y * f.tile_size + 8)
	assert_float(masonry.b).override_failure_message("pillar is masonry").is_greater(0.5)
	assert_float(masonry.r).override_failure_message("pillar has no occluder").is_less(0.5)

	var occ_base: Vector2i = (Vector2i(1, 0) - f.origin) * f.tile_size
	var occ := img.get_pixel(occ_base.x + 8, occ_base.y + 8)
	assert_float(occ.r).override_failure_message("occluder sets red").is_greater(0.5)
	assert_float(occ.b).override_failure_message("occluder is not masonry").is_less(0.5)

# --- Pillar regions --------------------------------------------------------------

func test_pillar_polygon_fills_the_green_channel_only() -> void:
	# A pillar region marks directional-shading pixels; it must not stop sight (red) or
	# read as masonry (blue), only flag green.
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 16))          # a base occluder so the field commits
	f.add_pillar_polygon(_rect(0, -16, 16, 16))  # pillar body one cell above the base
	f.commit(1)
	assert_bool(f.is_pillar_at(Vector2i(0, -1), Vector2i(8, 8))).is_true()
	assert_bool(f.is_pillar_at(Vector2i(0, 0), Vector2i(8, 8))).is_false()

	var img: Image = f.texture.get_image()
	var body: Vector2i = (Vector2i(0, -1) - f.origin) * f.tile_size
	var c := img.get_pixel(body.x + 8, body.y + 8)
	assert_float(c.g).override_failure_message("pillar body sets green").is_greater(0.5)
	assert_float(c.r).override_failure_message("pillar body does not stop sight").is_less(0.5)
	assert_float(c.b).override_failure_message("pillar body is not masonry data").is_less(0.5)

func test_pillar_region_is_cleared_with_everything_else() -> void:
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 16))
	f.add_pillar_polygon(_rect(0, -16, 16, 16))
	f.commit()
	f.clear()
	assert_bool(f.is_pillar_at(Vector2i(0, -1), Vector2i(8, 8))).is_false()

# --- Connecting rooms ------------------------------------------------------------

func test_overlapping_boundary_occluders_leave_no_seam() -> void:
	# The connection method: neighbouring rooms each draw their boundary wall over the
	# full shared cell, so the outlines OVERLAP rather than abut. Rasterizing into one
	# shared grid unions them, so no pixel along the seam is left open for the fog to leak
	# through. Here two rooms overlap by a few pixels; the whole span must occlude.
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 48))        # room A boundary wall, cells (0,0..2)
	f.add_polygon(_rect(12, 0, 16, 48))       # room B, overlapping A's right edge
	for y in range(0, 48):
		for x in range(0, 28):
			assert_bool(_solid_world(f, x, y)) \
				.override_failure_message("seam gap at (%d,%d)" % [x, y]).is_true()

func test_a_one_pixel_gap_between_rooms_would_leak() -> void:
	# The failure the overlap rule prevents: abutting outlines that fall a pixel short of
	# each other leave an open column the fog pours through. Guards the reasoning behind
	# "overlap, never abut".
	var f := BlockerField.new()
	f.add_polygon(_rect(0, 0, 16, 16))        # covers world x 0..15
	f.add_polygon(_rect(17, 0, 16, 16))       # starts at 17: pixel 16 left open
	assert_bool(_solid_world(f, 15, 8)).is_true()
	assert_bool(_solid_world(f, 16, 8)).override_failure_message(
		"the 1px gap is exactly the leak overlap avoids").is_false()
	assert_bool(_solid_world(f, 17, 8)).is_true()

# --- Masonry / occupancy ---------------------------------------------------------

func test_empty_pixels_in_a_wall_cell_are_not_art() -> void:
	# The halo. A bare add() fills the cell, so build a sprite-shaped mask by hand to
	# stand in for a tile that leaves part of its cell empty.
	var f := BlockerField.new()
	var mask: Array[bool] = []
	mask.resize(f.tile_size * f.tile_size)
	mask.fill(false)
	# A 6px pillar down the middle, like the east/west wall tile.
	for y in f.tile_size:
		for x in range(5, 11):
			mask[y * f.tile_size + x] = true
	f._cells[Vector2i.ZERO] = mask
	f.commit()

	var img: Image = f.texture.get_image()
	var base: Vector2i = (Vector2i.ZERO - f.origin) * f.tile_size
	# Inside the pillar: art.
	assert_float(img.get_pixel(base.x + 8, base.y + 8).b).is_greater(0.5)
	# Beside it, still inside the cell but not on the sprite: not masonry, so it may be
	# shadowed like any floor.
	var halo := img.get_pixel(base.x + 1, base.y + 8)
	assert_float(halo.b) \
		.override_failure_message("empty space must not count as masonry, or it haloes") \
		.is_less(0.5)

func test_floor_reads_as_nothing() -> void:
	var f := BlockerField.new()
	f.add(Vector2i(0, 0))
	f.commit(2)
	var img: Image = f.texture.get_image()
	var floor_px: Vector2i = (Vector2i(2, 2) - f.origin) * f.tile_size
	var c := img.get_pixel(floor_px.x + 8, floor_px.y + 8)
	assert_float(c.r).is_less(0.5)
	assert_float(c.g).is_less(0.5)
	assert_float(c.b).is_less(0.5)

func test_a_realistic_dungeon_packs_small() -> void:
	# The whole point of packing rather than streaming a window: even a large dungeon
	# stays a trivially small texture, which is what lets the shader own visibility.
	var walls: Array[Vector2i] = []
	for x in range(-20, 21):
		for y in range(-18, 18):
			if absi(x) % 10 == 0 or absi(y) % 9 == 0:
				walls.append(Vector2i(x, y))
	var f := _field_with(walls)
	f.commit()
	# Art-pixel resolution costs tile_size^2 more than per-tile, but the whole field is
	# still small enough to hand the GPU outright rather than streaming a window.
	var bytes: int = f.size.x * f.size.y * f.tile_size * f.tile_size
	assert_int(bytes).is_less(4 * 1024 * 1024)
