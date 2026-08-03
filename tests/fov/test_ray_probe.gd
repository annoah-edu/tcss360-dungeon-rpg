extends GdUnitTestSuite

## Tests for the CPU replica of the fog shader's sightline march (RayProbe). Because the
## probe mirrors the shader pixel for pixel, these also pin the behaviour the shader is
## expected to render — most importantly that a thin occluder is not tunnelled through.

const RADIUS := 9   # tiles; 144 world pixels

func _probe(f: BlockerField) -> RayProbe:
	return RayProbe.new(f, 16, RADIUS)

## A vertical occluder `thickness` pixels wide at world x = `x`, tall enough to span the
## sightlines below.
func _wall(x: float, thickness: float) -> BlockerField:
	var f := BlockerField.new()
	f.add_polygon(PackedVector2Array([
		Vector2(x, 0), Vector2(x + thickness, 0),
		Vector2(x + thickness, 64), Vector2(x, 64)]))
	return f

func test_a_clear_line_reaches_its_target() -> void:
	var hit := _probe(BlockerField.new()).cast(Vector2(4, 32), Vector2(60, 32))
	assert_bool(hit.blocked).is_false()
	assert_bool(hit.out_of_range).is_false()

func test_a_thin_occluder_still_blocks_sight() -> void:
	# The regression: a 2px wall between viewer and target. The old fixed 4px stride
	# stepped over it and let sight through; the DDA visits the pixels it occupies.
	var hit := _probe(_wall(30.0, 2.0)).cast(Vector2(4, 32), Vector2(60, 32))
	assert_bool(hit.blocked) \
		.override_failure_message("a 2px occluder must stop the ray").is_true()
	# It stopped at the wall, not somewhere past it.
	assert_int(hit.hit_cell.x).is_equal(1)   # x 30 falls in tile 1

func test_a_single_pixel_occluder_still_blocks_sight() -> void:
	# The hardest case a stride march loses entirely.
	var hit := _probe(_wall(30.0, 1.0)).cast(Vector2(4, 32), Vector2(60, 32))
	assert_bool(hit.blocked).override_failure_message("a 1px occluder must stop the ray").is_true()

func test_a_thin_diagonal_sightline_is_blocked_too() -> void:
	# Tunnelling is worst off-axis; a diagonal ray must still be stopped by the thin wall.
	var hit := _probe(_wall(30.0, 2.0)).cast(Vector2(4, 8), Vector2(60, 56))
	assert_bool(hit.blocked).is_true()

func test_the_target_surface_does_not_shadow_itself() -> void:
	# The destination pixel is the fragment's own surface; an occluder only on that pixel
	# must not read as blocked, or a wall would shade its own outer face. (A thicker wall
	# whose near pixels sit *before* the target still blocks — that is its body, handled
	# as masonry self-shadow elsewhere.)
	var f := _wall(60.0, 1.0)                 # a single occluder pixel at the target
	var hit := _probe(f).cast(Vector2(4, 32), Vector2(60, 32))
	assert_bool(hit.blocked) \
		.override_failure_message("a fragment on the occluder is lit by its own surface") \
		.is_false()

func test_the_viewer_pixel_never_blocks() -> void:
	# An occluder on the player's own pixel must not black out the view; the march starts
	# past the origin pixel. (Occluder pixels in front of the viewer still block.)
	var hit := _probe(_wall(5.0, 1.0)).cast(Vector2(5, 32), Vector2(60, 32))
	assert_bool(hit.blocked).is_false()

func test_a_target_out_of_range_is_flagged_not_blocked() -> void:
	var hit := _probe(BlockerField.new()).cast(Vector2(0, 0), Vector2(300, 0))
	assert_bool(hit.out_of_range).is_true()
	assert_bool(hit.blocked).is_false()
