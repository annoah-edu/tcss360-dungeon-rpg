class_name Starfield
extends CanvasLayer

## Animated backdrop behind the dungeon: horizontal lines that drift left to right and
## fade in and out, like stars in a star map. Purely decorative — the fog never touches
## it, and it sits at a negative layer so every room draws on top.
##
## The whole reason this is a CanvasLayer wrapping a SubViewport, rather than a plain
## ColorRect with a shader, is pixel density. The camera runs at `pixel_scale` zoom, so
## a shader drawn straight to the screen would resolve `pixel_scale` times finer than
## the 16px tile art and read as smooth modern gradients against crisp pixel art.
## Rendering into a buffer at 1/pixel_scale resolution and upscaling it with
## nearest-neighbour filtering makes one starfield pixel exactly one art pixel.

const SHADER_PATH := "res://scripts/background/starfield.gdshader"

## Must match the game camera's zoom for the density trick to line up.
@export var pixel_scale: int = 5:
	set(value):
		pixel_scale = maxi(value, 1)
		if is_inside_tree():
			_resize()

@export_group("Lines")
@export_range(1, 64) var line_count: int = 22:
	set(value):
		line_count = value
		_push_param(&"line_count", value)
## Drift speed in art pixels per second.
@export var drift_speed: float = 3.0:
	set(value):
		drift_speed = value
		_push_param(&"drift_speed", value)
## Seconds for one fade cycle, before per-line variation. A period, so larger is slower.
@export var twinkle_period: float = 14.0:
	set(value):
		twinkle_period = value
		_push_param(&"twinkle_period", value)
## Line length as a fraction of screen width.
@export_range(0.02, 1.0) var min_length: float = 0.15:
	set(value):
		min_length = value
		_push_param(&"min_length", value)
@export_range(0.02, 1.0) var max_length: float = 0.40:
	set(value):
		max_length = value
		_push_param(&"max_length", value)
@export_range(0.0, 1.0) var brightness: float = 0.55:
	set(value):
		brightness = value
		_push_param(&"brightness", value)
## Discrete brightness levels in a line's gradient. Keeps the taper reading as
## individual pixels rather than a smooth ramp; raise it toward 32 to soften.
@export_range(2, 32) var shade_steps: int = 5:
	set(value):
		shade_steps = value
		_push_param(&"shade_steps", value)
## Hue the lines lean toward. They are derived from `noise_color` first, so recolouring
## the haze carries the lines with it; this only sets where they drift from that.
@export var line_color: Color = Color(0.78, 0.62, 0.95):
	set(value):
		line_color = value
		_push_param(&"line_color", value)
## How far the lines shift from the haze hue toward `line_color`. 0 keeps them a plain
## bright version of the background; 1 uses `line_color` outright.
@export_range(0.0, 1.0) var line_tint: float = 0.55:
	set(value):
		line_tint = value
		_push_param(&"line_tint", value)

@export_group("Haze")
## Strength of the grey noise field behind the lines. Keeps the void from reading as
## flat black — a faded, cluttered memory rather than empty space.
@export_range(0.0, 1.0, 0.01) var noise_strength: float = 0.10:
	set(value):
		noise_strength = value
		_push_param(&"noise_strength", value)
## Base colour of the haze — a muddy deep purple. The lines are derived from this, so
## changing it recolours the whole backdrop as one family.
@export var noise_color: Color = Color(0.42, 0.33, 0.55):
	set(value):
		noise_color = value
		_push_param(&"noise_color", value)
## Size of the coarse patches in art pixels; larger means broader blotches.
@export_range(1.0, 64.0) var noise_scale: float = 9.0:
	set(value):
		noise_scale = value
		_push_param(&"noise_scale", value)
## Weight of the finer second octave against the coarse one.
@export_range(0.0, 1.0) var noise_detail: float = 0.45:
	set(value):
		noise_detail = value
		_push_param(&"noise_detail", value)
## Discrete grey levels in the haze, matching the lines' banded look.
@export_range(2, 16) var noise_steps: int = 4:
	set(value):
		noise_steps = value
		_push_param(&"noise_steps", value)
## Seconds for the haze to drift one cycle. Long enough that it breathes rather than
## flickers; around 3% of pixels shift per second at this value.
@export var noise_drift: float = 16.0:
	set(value):
		noise_drift = value
		_push_param(&"noise_drift", value)
## Lifts the darkest patches off pure black.
@export_range(0.0, 1.0) var noise_floor: float = 0.18:
	set(value):
		noise_floor = value
		_push_param(&"noise_floor", value)

var _viewport: SubViewport
var _rect: ColorRect
var _display: TextureRect

func _ready() -> void:
	# Behind every room, and fixed to the screen rather than scrolling with the world.
	layer = -100
	follow_viewport_enabled = false
	_build()
	get_viewport().size_changed.connect(_resize)

func _build() -> void:
	# The low-resolution buffer the shader draws into.
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var shader := load(SHADER_PATH) as Shader
	_rect = ColorRect.new()
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_rect.material = mat
	_viewport.add_child(_rect)

	# Blown back up to full size with no smoothing, which is what keeps the lines at
	# the same pixel density as the tile art.
	_display = TextureRect.new()
	_display.texture = _viewport.get_texture()
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	# Anchored to fill the screen; the explicit size in _resize() is deferred so it
	# does not fight the anchor layout that runs right after _ready().
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Purely decorative, so it must never eat clicks meant for the game.
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)

	_resize()
	_push_all()

## Size the buffer to the screen divided by the camera zoom, so one buffer pixel
## covers exactly one art pixel once upscaled.
func _resize() -> void:
	if _viewport == null:
		return
	var screen := Vector2(get_viewport().get_visible_rect().size)
	var buffer := (screen / float(pixel_scale)).ceil()
	buffer = buffer.max(Vector2.ONE)
	_viewport.size = Vector2i(buffer)
	if _rect != null:
		_rect.size = buffer
		_push_param(&"buffer_size", buffer)
	if _display != null:
		# Deferred: setting size directly during _ready() is overridden by the anchor
		# pass and warns about it.
		_display.set_deferred(&"size", screen)

func _push_all() -> void:
	_push_param(&"line_count", line_count)
	_push_param(&"drift_speed", drift_speed)
	_push_param(&"twinkle_period", twinkle_period)
	_push_param(&"min_length", min_length)
	_push_param(&"max_length", max_length)
	_push_param(&"brightness", brightness)
	_push_param(&"shade_steps", shade_steps)
	_push_param(&"line_color", line_color)
	_push_param(&"line_tint", line_tint)
	_push_param(&"noise_strength", noise_strength)
	_push_param(&"noise_color", noise_color)
	_push_param(&"noise_scale", noise_scale)
	_push_param(&"noise_detail", noise_detail)
	_push_param(&"noise_steps", noise_steps)
	_push_param(&"noise_drift", noise_drift)
	_push_param(&"noise_floor", noise_floor)

func _push_param(name: StringName, value: Variant) -> void:
	if _rect == null:
		return
	var mat := _rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(name, value)
