class_name FovRenderer
extends CanvasLayer

## Renders the field of view on the GPU at art-pixel resolution.
##
## Replaces the tile-based FogOverlay: instead of the CPU deciding each tile's state
## and painting a TileMapLayer, the whole dungeon's walls are handed to the shader as a
## small texture and every fragment marches its own ray back to the player. Sub-tile
## shadow edges come out for free, because the unit of work already is a pixel.
##
## Two passes:
##   1. Memory — a ping-pong pair of SubViewports accumulating `max(previous, lit)`, so
##      explored ground is remembered per pixel rather than per tile.
##   2. Fog — one full-screen rect compositing live visibility against that memory.
##
## The CPU VisibilityMap is deliberately still alive alongside this. It answers gameplay
## questions ("can this enemy be seen?") that need a synchronous per-tile boolean and a
## symmetry guarantee, neither of which a texture can provide without a readback stall.

const MEMORY_SHADER := "res://scripts/fov/fov_memory.gdshader"
const FOG_SHADER := "res://scripts/fov/fov_fog.gdshader"

## How dark remembered, currently-unlit ground is drawn.
@export_range(0.0, 1.0, 0.05) var remembered_darkness: float = 0.55:
	set(value):
		remembered_darkness = value
		_push(&"remembered_darkness", value, true)
## Opacity of never-seen space. Left at 0 so the starfield reads through it.
@export_range(0.0, 1.0, 0.05) var unseen_opacity: float = 0.0:
	set(value):
		unseen_opacity = value
		_push(&"unseen_opacity", value, true)
## Width of the outer ring, as a fraction of the sight radius. The edge of the pool is
## drawn as one flat dimmer band rather than a gradient, so it stays in the same
## limited palette as the pixel art. 0 gives a single hard edge.
@export_range(0.0, 0.9, 0.02) var rim_width: float = 0.22:
	set(value):
		rim_width = value
		_push(&"rim_width", value, true)
## How lit that ring is, between fully veiled and fully lit.
@export_range(0.0, 1.0, 0.05) var rim_level: float = 0.45:
	set(value):
		rim_level = value
		_push(&"rim_level", value, true)
## Keep the veil off wall cells. A ray stops at a wall's near surface, so the wall's own
## body counts as shadowed and would otherwise shade itself — showing up as seams
## between the tiles of a single wall run.
@export var shadow_ignores_walls: bool = true:
	set(value):
		shadow_ignores_walls = value
		_push(&"shadow_ignores_walls", value, true)
## Ray march step as a fraction of a tile. Smaller is more precise at corners.
@export_range(0.05, 1.0, 0.05) var step_scale: float = 0.25:
	set(value):
		step_scale = value
		_push(&"step_scale", value, true)
		_push(&"step_scale", value, false)
## How far a wall's art overhangs the cell above it, in world pixels. North/south wall
## tiles poke 4px up and that strip is the face the player looks at; east/west tiles do
## not overhang at all. 0 disables the handling.
@export_range(0.0, 16.0, 1.0) var overhang_px: float = 6.0:
	set(value):
		overhang_px = value
		_push(&"overhang_px", value, true)
		_push(&"overhang_px", value, false)

var _field: BlockerField
var _tile_size: float = 16.0
var _radius_px: float = 144.0
var _player_world := Vector2.ZERO

## Ping-pong memory targets. `_current` indexes the one holding the newest memory.
var _memory_vp: Array[SubViewport] = []
var _memory_mat: Array[ShaderMaterial] = []
var _current := 0
## Cleared on rebuild so the first pass does not inherit the previous dungeon's memory.
var _primed := false

var _fog_rect: ColorRect
var _fog_mat: ShaderMaterial

func _ready() -> void:
	# Above the world, below any UI. The fog is screen furniture, so it must not be
	# sorted against the rooms by y position.
	layer = 1
	_build_fog_rect()

func _process(_delta: float) -> void:
	# The camera can move between visibility updates — it follows the player smoothly
	# while the field of view only changes on tile crossings — so the screen-to-world
	# mapping is refreshed every frame or the fog would lag behind the view.
	_push_view()

## Point the renderer at a dungeon. Call once per build, after every wall is registered.
func setup(field: BlockerField, tile_size: int, sight_radius: int) -> void:
	_field = field
	_tile_size = float(tile_size)
	_radius_px = float(sight_radius * tile_size)
	_primed = false
	_build_memory_targets()
	_push_static()

## Recompute visibility and fold it into memory. Cheap enough to call on every player
## move; the accumulate pass measured free against a vsync-bound frame.
func update_from(world_position: Vector2) -> void:
	_player_world = world_position
	if _field == null or _field.texture == null:
		return
	_push(&"player_world", world_position, true)
	_push(&"player_world", world_position, false)
	_push_view()

	# Render the next memory step into the target that is *not* currently being read.
	var next := 1 - _current
	if next < _memory_mat.size():
		_memory_mat[next].set_shader_parameter(&"use_previous", _primed)
		_memory_vp[next].render_target_update_mode = SubViewport.UPDATE_ONCE
		_current = next
		_primed = true
		if _fog_mat != null:
			_fog_mat.set_shader_parameter(&"memory", _memory_vp[_current].get_texture())

## Drop all accumulated memory, for a fresh dungeon.
func clear_memory() -> void:
	_primed = false

func set_fog_enabled(enabled: bool) -> void:
	_push(&"fog_enabled", enabled, true)

## The texture holding accumulated memory, for tests and debugging.
func memory_texture() -> Texture2D:
	if _memory_vp.is_empty():
		return null
	return _memory_vp[_current].get_texture()

# --- Construction ----------------------------------------------------------------

func _build_fog_rect() -> void:
	if _fog_rect != null:
		return
	_fog_rect = ColorRect.new()
	_fog_rect.name = "FogRect"
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Purely presentational, so it must never swallow input meant for the game.
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := load(FOG_SHADER) as Shader
	if shader != null:
		_fog_mat = ShaderMaterial.new()
		_fog_mat.shader = shader
		_fog_rect.material = _fog_mat
	add_child(_fog_rect)

func _build_memory_targets() -> void:
	for vp in _memory_vp:
		if is_instance_valid(vp):
			vp.queue_free()
	_memory_vp.clear()
	_memory_mat.clear()
	_current = 0
	if _field == null or _field.texture == null:
		return

	var shader := load(MEMORY_SHADER) as Shader
	if shader == null:
		push_warning("FovRenderer: memory shader missing at %s" % MEMORY_SHADER)
		return

	var rect := _field.world_rect(int(_tile_size))
	for i in 2:
		var vp := SubViewport.new()
		vp.name = "Memory%d" % i
		vp.size = rect.size
		vp.disable_3d = true
		# Driven explicitly by update_from, so it does not redraw every frame.
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		add_child(vp)

		var quad := ColorRect.new()
		quad.size = Vector2(rect.size)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		quad.material = mat
		vp.add_child(quad)

		_memory_vp.append(vp)
		_memory_mat.append(mat)

	# Cross-wire the pair: each reads the other's output as `previous`.
	_memory_mat[0].set_shader_parameter(&"previous", _memory_vp[1].get_texture())
	_memory_mat[1].set_shader_parameter(&"previous", _memory_vp[0].get_texture())
	if _fog_mat != null:
		_fog_mat.set_shader_parameter(&"memory", _memory_vp[_current].get_texture())

## Push the values that only change when the dungeon does.
func _push_static() -> void:
	if _field == null:
		return
	var rect := _field.world_rect(int(_tile_size))
	for is_fog in [true, false]:
		_push(&"blockers", _field.texture, is_fog)
		_push(&"grid_origin", Vector2(_field.origin), is_fog)
		_push(&"grid_size", Vector2(_field.size), is_fog)
		_push(&"field_origin", Vector2(rect.position), is_fog)
		_push(&"field_size", Vector2(rect.size), is_fog)
		_push(&"tile_size", _tile_size, is_fog)
		_push(&"radius_px", _radius_px, is_fog)
		_push(&"step_scale", step_scale, is_fog)
		_push(&"overhang_px", overhang_px, is_fog)
	_push(&"remembered_darkness", remembered_darkness, true)
	_push(&"unseen_opacity", unseen_opacity, true)
	_push(&"rim_width", rim_width, true)
	_push(&"rim_level", rim_level, true)
	_push(&"shadow_ignores_walls", shadow_ignores_walls, true)

## Tell the fog shader how to turn its screen-space fragments back into world points.
##
## The fog rect lives on a CanvasLayer so it always covers the viewport, which means its
## vertices are screen pixels. The canvas transform carries the camera's pan and zoom,
## and inverting it recovers the world position each fragment stands on.
func _push_view() -> void:
	if _fog_mat == null or not is_inside_tree():
		return
	var canvas := get_viewport().get_canvas_transform()
	var inv := canvas.affine_inverse()
	_fog_mat.set_shader_parameter(&"view_origin", inv.origin)
	# The inverse's basis scales screen pixels to world pixels; both axes share the
	# camera's zoom, so the diagonal is all the shader needs.
	_fog_mat.set_shader_parameter(&"view_scale", Vector2(inv.x.x, inv.y.y))

## Set a parameter on the fog material, or on both memory materials.
func _push(name: StringName, value: Variant, on_fog: bool) -> void:
	if on_fog:
		if _fog_mat != null:
			_fog_mat.set_shader_parameter(name, value)
	else:
		for mat in _memory_mat:
			mat.set_shader_parameter(name, value)
