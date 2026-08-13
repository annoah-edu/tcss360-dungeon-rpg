class_name DuckDistance
extends Control

## The joke stat: "Distance the Duck is from your location." There is no number — it
## renders as "??? <unit>" where every '?' is a hostile red glyph that shakes violently
## and erratically (each on its own random jitter, never in unison), and the unit cycles
## through the shorthand m -> km -> mi -> ft -> in forever, jolting each time it flips over.
##
## Self-contained so the Statistics panel can drop one in. Renders only the value
## ("??? mi"); the surrounding UI supplies the "Distance from The Duck" caption, matching
## how the honest stats lay out.

## Evil red, biased dark so it reads as a warning rather than a valentine.
const EVIL_RED := Color(0.86, 0.06, 0.06)
## Peak stray, in pixels, a glyph jumps from rest on each shake re-roll.
const JITTER_PIXELS := 5
## Peak random tilt per glyph, in radians, added on each re-roll. 0 disables the tilt.
const JITTER_ROT := 0.0
## Times per second the glyphs re-roll their random shake. Higher is faster and more
## frantic; lower is slower and chunkier. Framerate-independent — the offset is held
## between rolls, so this drives the shake speed rather than the frame rate doing it.
const JITTER_HZ := 25.0
## Seconds each unit stays up before the label cycles to the next.
const UNIT_PERIOD := 2.0
## Seconds the unit-change jolt takes to settle.
const JOLT_TIME := 0.16

@export var question_count: int = 3
@export var font_size: int = 22

var _glyphs: Array[Label] = []
## Current held shake per glyph, re-rolled at JITTER_HZ and applied every frame.
var _offsets: Array[Vector2] = []
var _rots: Array[float] = []
## Time banked toward the next shake re-roll.
var _shake_accum: float = 0.0
var _unit_label: Label
var _unit_base_x: float = 0.0
var _elapsed: float = 0.0
## Which unit is currently shown, so a change can trigger the jolt.
var _unit_idx: int = -1
## Decays 1 -> 0 over JOLT_TIME after each unit flip, driving the little pop.
var _jolt: float = 0.0
var _font: Font

func _ready() -> void:
	_font = load("res://resources/fonts/Minecraft.ttf") as Font
	# Advance from the real glyph metrics, plus a healthy gap, so three shaking '?'
	# can never overlap into a "777" smear.
	var advance := _measure("?")
	var step := advance + maxf(advance * 0.6, 6.0)
	var pivot := Vector2(advance, font_size) * 0.5
	var x := 0.0
	for i in question_count:
		var g := _make_label("?", EVIL_RED)
		g.position = Vector2(x, 0)
		g.set_meta("base_x", x)
		# Rotate about the glyph's centre so the tilt looks like a shake, not a swing.
		g.pivot_offset = pivot
		add_child(g)
		_glyphs.append(g)
		_offsets.append(Vector2.ZERO)
		_rots.append(0.0)
		x += step
	x += step * 0.4
	_unit_base_x = x
	_unit_label = _make_label(_unit_name(0), Color(0.75, 0.75, 0.8))
	_unit_label.position = Vector2(x, 0)
	_unit_label.pivot_offset = Vector2(0, font_size * 0.5)
	add_child(_unit_label)
	_unit_idx = 0
	# Reserve room for the widest unit (plus the jolt swell) so nothing clips.
	var widest := _widest_unit() * 1.3
	custom_minimum_size = Vector2(x + widest + JITTER_PIXELS * 2.0, font_size + JITTER_PIXELS * 2.0)

func _process(delta: float) -> void:
	_elapsed += delta

	# Re-roll each glyph's random shake at JITTER_HZ (not every frame), so the shake
	# speed is set by the const rather than by the frame rate. Loop in case a slow frame
	# banked more than one interval.
	_shake_accum += delta
	var interval := 1.0 / JITTER_HZ
	while _shake_accum >= interval:
		_shake_accum -= interval
		for i in _glyphs.size():
			_offsets[i] = Vector2(
				randf_range(-JITTER_PIXELS, JITTER_PIXELS),
				randf_range(-JITTER_PIXELS, JITTER_PIXELS)
			)
			_rots[i] = randf_range(-JITTER_ROT, JITTER_ROT)
			# Erratic brightness flicker, re-rolled on the same beat as the shake.
			_glyphs[i].add_theme_color_override("font_color", EVIL_RED * randf_range(0.9, 1.0))

	# Apply the held shake every frame so the glyphs sit still between re-rolls.
	for i in _glyphs.size():
		var g := _glyphs[i]
		g.position = Vector2(g.get_meta("base_x"), 0.0) + _offsets[i]
		g.rotation = _rots[i]

	# Cycle the unit, jolting on each flip.
	var idx := int(_elapsed / UNIT_PERIOD) % Stats.DUCK_UNITS.size()
	if idx != _unit_idx:
		_unit_idx = idx
		_unit_label.text = _unit_name(idx)
		_jolt = 1.0
	_jolt = maxf(_jolt - delta / JOLT_TIME, 0.0)
	# Ease the decay and drive a small pop: nudge left/up and swell briefly, then settle.
	var j := _jolt * _jolt
	_unit_label.position = Vector2(_unit_base_x - 5.0 * j, -4.0 * j)
	_unit_label.scale = Vector2.ONE * (1.0 + 0.3 * j)

func _make_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	return l

## Rendered width of a string at the current font/size, for overlap-free layout.
func _measure(text: String) -> float:
	if _font != null:
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return font_size * 0.7 * text.length()

## Width of the widest unit label, so the control reserves enough room as they cycle.
func _widest_unit() -> float:
	var widest := 0.0
	for u in Stats.DUCK_UNITS:
		widest = maxf(widest, _measure(u))
	return widest

func _unit_name(idx: int) -> String:
	return Stats.DUCK_UNITS[idx % Stats.DUCK_UNITS.size()]
