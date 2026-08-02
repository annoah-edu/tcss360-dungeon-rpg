extends GdUnitTestSuite

## Tests for the wall texture handed to the field-of-view shader. This is pure data —
## the shader's use of it is verified separately against rendered pixels.

## A field with the inner-skin trim disabled, so tests that care about the raw
## silhouette are not measuring the trim as well. Trimming has its own tests below.
func _field_with(cells: Array[Vector2i]) -> BlockerField:
	var f := BlockerField.new()
	f.inner_skin = 0
	f.add_all(cells)
	return f

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
	f.commit()
	f.clear()
	assert_int(f.wall_count()).is_equal(0)
	assert_object(f.texture).is_null()

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
	# Callers with no tile data get a conservative solid cell: over-blocking looks
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

# --- Inner skin ------------------------------------------------------------------

func test_inner_skin_peels_faces_that_front_onto_open_floor() -> void:
	# Sight should stop at the far side of a wall, not the face the player stands
	# against — otherwise a wall casts shadow from a wall-thickness too early.
	var f := BlockerField.new()
	f.inner_skin = 4
	f.add(Vector2i(0, 0))
	f.add(Vector2i(0, -1))   # wall above, so the top face is interior
	f.commit()

	# The bottom fronts onto floor and is peeled.
	assert_bool(f.is_solid_at(Vector2i(0, 0), Vector2i(8, 15))).is_false()
	assert_bool(f.is_solid_at(Vector2i(0, 0), Vector2i(8, 12))).is_false()
	# The core survives.
	assert_bool(f.is_solid_at(Vector2i(0, 0), Vector2i(8, 8))).is_true()
	# The top abuts another wall, so it is not a face and is left alone.
	assert_bool(f.is_solid_at(Vector2i(0, 0), Vector2i(8, 0))).is_true()

func test_a_wall_inside_a_block_keeps_its_whole_silhouette() -> void:
	# Nothing to front onto means nothing to peel.
	var f := BlockerField.new()
	f.inner_skin = 4
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			f.add(Vector2i(dx, dy))
	f.commit()
	for local: Vector2i in [Vector2i(0, 0), Vector2i(15, 15), Vector2i(8, 8)]:
		assert_bool(f.is_solid_at(Vector2i.ZERO, local)) \
			.override_failure_message("enclosed wall should keep %s" % local) \
			.is_true()

func test_zero_skin_leaves_the_silhouette_untouched() -> void:
	var f := BlockerField.new()
	f.inner_skin = 0
	f.add(Vector2i(0, 0))
	f.commit()
	assert_bool(f.is_solid_at(Vector2i(0, 0), Vector2i(8, 15))).is_true()
	assert_bool(f.is_solid_at(Vector2i(0, 0), Vector2i(0, 0))).is_true()

func test_skin_never_eats_the_whole_cell() -> void:
	# An over-large skin must still leave a core, or walls would stop occluding.
	var f := BlockerField.new()
	f.inner_skin = 999
	f.add(Vector2i(0, 0))
	f.commit()
	var any := false
	for y in 16:
		for x in 16:
			if f.is_solid_at(Vector2i(0, 0), Vector2i(x, y)):
				any = true
	assert_bool(any).is_true()

func test_texture_separates_occlusion_art_and_occupancy() -> void:
	# Three channels answering three questions:
	#   red   stops sight (trimmed silhouette)
	#   blue  is drawn masonry (untrimmed sprite)
	#   green is inside a wall cell
	# Red and blue differ by the inner skin; blue and green by whatever the sprite
	# leaves empty. Using green as the no-shadow mask is what haloed the walls.
	var f := BlockerField.new()
	f.inner_skin = 4
	f.add(Vector2i(0, 0))
	f.add(Vector2i(0, -1))   # wall above, so only the lower faces are exposed
	f.commit()
	var img: Image = f.texture.get_image()
	var base: Vector2i = (Vector2i(0, 0) - f.origin) * f.tile_size

	# Core: occludes, is art, is occupied.
	var core := img.get_pixel(base.x + 8, base.y + 8)
	assert_float(core.r).is_greater(0.5)
	assert_float(core.b).is_greater(0.5)
	assert_float(core.g).is_greater(0.5)

	# Peeled skin: still art, no longer occluding.
	var skin := img.get_pixel(base.x + 8, base.y + f.tile_size - 1)
	assert_float(skin.r) \
		.override_failure_message("skin should not occlude") \
		.is_less(0.5)
	assert_float(skin.b) \
		.override_failure_message("skin is still drawn masonry") \
		.is_greater(0.5)

func test_empty_pixels_in_a_wall_cell_are_not_art() -> void:
	# The halo. A bare add() fills the cell, so build a sprite-shaped mask by hand to
	# stand in for a tile that leaves part of its cell empty.
	var f := BlockerField.new()
	f.inner_skin = 0
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
	# Beside it, still inside the cell: occupied, but NOT art, so it may be shadowed.
	var halo := img.get_pixel(base.x + 1, base.y + 8)
	assert_float(halo.g) \
		.override_failure_message("still inside the cell") \
		.is_greater(0.5)
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
