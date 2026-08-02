extends GdUnitTestSuite

## Tests for the star-map backdrop. The visual result needs a human eye, but the
## structural guarantees — buffer resolution, filtering, layering — are what keep the
## lines at the same pixel density as the tile art, and those are checkable.

func _starfield(scale: int = 5) -> Starfield:
	var sf := Starfield.new()
	sf.pixel_scale = scale
	add_child(sf)
	await get_tree().process_frame
	return sf

func _viewport_of(sf: Starfield) -> SubViewport:
	for c in sf.get_children():
		if c is SubViewport:
			return c
	return null

func _display_of(sf: Starfield) -> TextureRect:
	for c in sf.get_children():
		if c is TextureRect:
			return c
	return null

# --- Pixel density ---------------------------------------------------------------

func test_buffer_is_the_screen_divided_by_the_camera_zoom() -> void:
	# The whole point of the SubViewport: at zoom N a screen-space shader would draw N
	# times finer than the 16px art and read as smooth gradients against pixel art.
	var sf: Starfield = await _starfield(5)
	var vp := _viewport_of(sf)
	assert_object(vp).is_not_null()
	var screen := Vector2(get_tree().root.get_visible_rect().size)
	assert_that(vp.size).is_equal(Vector2i((screen / 5.0).ceil()))

func test_changing_pixel_scale_resizes_the_buffer() -> void:
	var sf: Starfield = await _starfield(5)
	var vp := _viewport_of(sf)
	var at_five := vp.size
	sf.pixel_scale = 10
	await get_tree().process_frame
	# Coarser scale means a smaller buffer, so each pixel covers more screen.
	assert_int(vp.size.x).is_less(at_five.x)

func test_upscale_uses_nearest_neighbour() -> void:
	# Linear filtering would blur the lines back into smooth gradients, defeating the
	# low-resolution buffer entirely.
	var sf: Starfield = await _starfield()
	var display := _display_of(sf)
	assert_object(display).is_not_null()
	assert_int(display.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)

func test_pixel_scale_never_drops_below_one() -> void:
	# A zero or negative scale would divide the screen size into nothing.
	var sf: Starfield = await _starfield()
	sf.pixel_scale = 0
	assert_int(sf.pixel_scale).is_greater_equal(1)
	await get_tree().process_frame
	assert_int(_viewport_of(sf).size.x).is_greater(0)

# --- Layering --------------------------------------------------------------------

func test_backdrop_sits_behind_the_world_and_ignores_input() -> void:
	var sf: Starfield = await _starfield()
	# Negative layer keeps every room drawn on top.
	assert_int(sf.layer).is_less(0)
	# Fixed to the screen rather than scrolling with the camera.
	assert_bool(sf.follow_viewport_enabled).is_false()
	# Decorative only: it must not swallow clicks meant for the game.
	assert_int(_display_of(sf).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

# --- Shader parameters -----------------------------------------------------------

func test_line_settings_reach_the_shader() -> void:
	var sf: Starfield = await _starfield()
	sf.line_count = 31
	sf.brightness = 0.42
	sf.drift_speed = 9.5
	var mat := _display_of(sf).material
	# The shader lives on the ColorRect inside the buffer, not on the display rect.
	var rect: ColorRect = null
	for c in _viewport_of(sf).get_children():
		if c is ColorRect:
			rect = c
	assert_object(rect).is_not_null()
	var shader_mat := rect.material as ShaderMaterial
	assert_object(shader_mat).is_not_null()
	assert_int(shader_mat.get_shader_parameter(&"line_count")).is_equal(31)
	assert_float(shader_mat.get_shader_parameter(&"brightness")).is_equal_approx(0.42, 0.001)
	assert_float(shader_mat.get_shader_parameter(&"drift_speed")).is_equal_approx(9.5, 0.001)

func test_shade_steps_reaches_the_shader() -> void:
	# The gradient is quantised into flat bands so individual pixels stay legible
	# instead of blending into a smooth ramp.
	var sf: Starfield = await _starfield()
	sf.shade_steps = 4
	var rect: ColorRect = null
	for c in _viewport_of(sf).get_children():
		if c is ColorRect:
			rect = c
	var shader_mat := rect.material as ShaderMaterial
	assert_int(shader_mat.get_shader_parameter(&"shade_steps")).is_equal(4)

func test_haze_settings_reach_the_shader() -> void:
	# The grey noise field behind the lines, so the void reads as a faded memory
	# rather than flat black.
	var sf: Starfield = await _starfield()
	sf.noise_strength = 0.13
	sf.noise_scale = 12.0
	sf.noise_steps = 6
	var rect: ColorRect = null
	for c in _viewport_of(sf).get_children():
		if c is ColorRect:
			rect = c
	var mat := rect.material as ShaderMaterial
	assert_float(mat.get_shader_parameter(&"noise_strength")).is_equal_approx(0.13, 0.001)
	assert_float(mat.get_shader_parameter(&"noise_scale")).is_equal_approx(12.0, 0.001)
	assert_int(mat.get_shader_parameter(&"noise_steps")).is_equal(6)

func test_haze_is_present_but_subtle_by_default() -> void:
	# Strong enough to lift the void off pure black, weak enough that the lines stay
	# the subject rather than the texture.
	var sf: Starfield = await _starfield()
	assert_float(sf.noise_strength).is_greater(0.0)
	assert_float(sf.noise_strength).is_less(0.3)
	# A raised floor is what guarantees no patch bottoms out at black.
	assert_float(sf.noise_floor).is_greater(0.0)

func test_lines_are_derived_from_the_haze_colour() -> void:
	# The lines read as a brighter version of the background rather than a separate
	# hue, so recolouring the haze has to carry them with it.
	var sf: Starfield = await _starfield()
	var rect: ColorRect = null
	for c in _viewport_of(sf).get_children():
		if c is ColorRect:
			rect = c
	var mat := rect.material as ShaderMaterial
	# Partial tint: fully 1.0 would ignore the haze hue entirely.
	var tint: float = mat.get_shader_parameter(&"line_tint")
	assert_float(tint).is_greater(0.0)
	assert_float(tint).is_less(1.0)

func test_background_palette_is_purple() -> void:
	# Purple means red and blue both sit above green. Asserting the relationship
	# rather than exact values leaves the shade free to be retuned.
	var sf: Starfield = await _starfield()
	assert_float(sf.noise_color.r).is_greater(sf.noise_color.g)
	assert_float(sf.noise_color.b).is_greater(sf.noise_color.g)
	# The lines' own tint target keeps the same relationship.
	assert_float(sf.line_color.r).is_greater(sf.line_color.g)
	assert_float(sf.line_color.b).is_greater(sf.line_color.g)
	# And the lines are the brighter of the two.
	var haze_sum: float = sf.noise_color.r + sf.noise_color.g + sf.noise_color.b
	var line_sum: float = sf.line_color.r + sf.line_color.g + sf.line_color.b
	assert_float(line_sum).is_greater(haze_sum)

func test_shader_resource_loads() -> void:
	var shader := load(Starfield.SHADER_PATH)
	assert_object(shader).is_not_null()
	assert_bool(shader is Shader).is_true()
