extends GdUnitTestSuite

## Tests for how entities leave sight: a grace period at their real position, then a
## pixel-scatter dissolve, then hidden.

var _in_sight := true

func _sight_fn(_node: Node2D) -> bool:
	return _in_sight

## A minimal body with a sprite child, standing in for an enemy.
func _entity() -> Node2D:
	var body := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	sprite.texture = ImageTexture.create_from_image(img)
	body.add_child(sprite)
	add_child(body)
	return body

func _vaporizer(linger: float = 1.0, fade: float = 0.9) -> Vaporizer:
	var v := Vaporizer.new()
	v.linger_time = linger
	v.fade_time = fade
	return v

func _material_of(node: Node2D) -> ShaderMaterial:
	return (node.get_child(0) as Sprite2D).material as ShaderMaterial

func before_test() -> void:
	_in_sight = true

# --- Tracking --------------------------------------------------------------------

func test_tracking_applies_the_dissolve_shader() -> void:
	var v := _vaporizer()
	var e := _entity()
	v.track(e)
	assert_int(v.tracked_count()).is_equal(1)
	var mat := _material_of(e)
	assert_object(mat).is_not_null()
	# Intact until the dissolve begins.
	assert_float(mat.get_shader_parameter(&"progress")).is_equal_approx(0.0, 0.001)

func test_tracking_the_same_entity_twice_is_idempotent() -> void:
	var v := _vaporizer()
	var e := _entity()
	v.track(e)
	v.track(e)
	assert_int(v.tracked_count()).is_equal(1)

func test_freed_entities_are_dropped() -> void:
	var v := _vaporizer()
	var e := _entity()
	v.track(e)
	e.free()
	v.update(0.1, _sight_fn)
	assert_int(v.tracked_count()).is_equal(0)

# --- Lifecycle -------------------------------------------------------------------

func test_entity_in_sight_stays_visible_and_undissolved() -> void:
	var v := _vaporizer()
	var e := _entity()
	v.track(e)
	v.update(0.5, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.VISIBLE)
	assert_bool(e.visible).is_true()

func test_entity_lingers_at_its_real_position_before_fading() -> void:
	# The point of the grace period: the player gets to see where it actually was
	# rather than having it vanish the instant it clears the light pool.
	var v := _vaporizer(1.0, 0.9)
	var e := _entity()
	v.track(e)
	_in_sight = false

	v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.LINGERING)
	# Halfway through the linger it is still fully drawn and undissolved.
	for i in 4:
		v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.LINGERING)
	assert_bool(e.visible).is_true()
	assert_float(_material_of(e).get_shader_parameter(&"progress")).is_equal_approx(0.0, 0.001)

func test_dissolve_starts_after_the_linger_and_advances() -> void:
	var v := _vaporizer(1.0, 0.9)
	var e := _entity()
	v.track(e)
	_in_sight = false
	# Past the linger.
	for i in 12:
		v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.VAPORIZING)
	var early: float = _material_of(e).get_shader_parameter(&"progress")
	# ...and it keeps progressing.
	for i in 3:
		v.update(0.1, _sight_fn)
	var later: float = _material_of(e).get_shader_parameter(&"progress")
	assert_float(later).is_greater(early)
	# Still drawn while dissolving — that is the whole effect.
	assert_bool(e.visible).is_true()

func test_entity_is_hidden_once_fully_dissolved() -> void:
	var v := _vaporizer(1.0, 0.9)
	var e := _entity()
	v.track(e)
	_in_sight = false
	for i in 40:
		v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.GONE)
	assert_bool(e.visible).is_false()
	assert_float(_material_of(e).get_shader_parameter(&"progress")).is_equal_approx(1.0, 0.001)

# --- Re-entry --------------------------------------------------------------------

func test_re_entering_sight_cancels_the_dissolve() -> void:
	# An enemy pacing the edge of vision must not flicker through the sequence over
	# and over, so any sighting resets it outright.
	var v := _vaporizer(1.0, 0.9)
	var e := _entity()
	v.track(e)
	_in_sight = false
	for i in 14:
		v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.VAPORIZING)

	_in_sight = true
	v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.VISIBLE)
	assert_bool(e.visible).is_true()
	assert_float(_material_of(e).get_shader_parameter(&"progress")).is_equal_approx(0.0, 0.001)

func test_re_entering_after_full_dissolve_restores_the_entity() -> void:
	var v := _vaporizer(1.0, 0.9)
	var e := _entity()
	v.track(e)
	_in_sight = false
	for i in 40:
		v.update(0.1, _sight_fn)
	assert_bool(e.visible).is_false()

	_in_sight = true
	v.update(0.1, _sight_fn)
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.VISIBLE)
	assert_bool(e.visible).is_true()

# --- Configuration ---------------------------------------------------------------

func test_zero_linger_goes_straight_to_dissolving() -> void:
	var v := _vaporizer(0.0, 0.5)
	var e := _entity()
	v.track(e)
	_in_sight = false
	v.update(0.1, _sight_fn)   # enters LINGERING
	v.update(0.1, _sight_fn)   # linger already expired
	assert_int(v.phase_of(e)).is_equal(Vaporizer.Phase.VAPORIZING)

func test_shader_resource_loads() -> void:
	var shader := load(Vaporizer.SHADER_PATH)
	assert_object(shader).is_not_null()
	assert_bool(shader is Shader).is_true()
