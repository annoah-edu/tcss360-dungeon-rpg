class_name Vaporizer
extends RefCounted

## Manages how entities leave the player's sight: they linger a moment at their real
## position, then scatter into drifting pixels before disappearing.
##
## Hiding an enemy the instant it leaves the light pool is both harsh to look at and
## slightly unfair — the player never sees where it went. Holding the sprite briefly
## lets them register the last known position, and the dissolve turns the removal into
## a deliberate "you are forgetting this" beat rather than a pop.
##
## Lifecycle per entity:
##   VISIBLE     — in sight, drawn normally, no shader work.
##   LINGERING   — just left sight; still drawn at its true position for `linger_time`.
##                 It keeps moving, so the image stays honest rather than freezing a
##                 stale frame.
##   VAPORIZING  — dissolving over `fade_time`; the shader scatters its pixels upward.
##   GONE        — hidden entirely.
##
## Re-entering sight at any point cancels the dissolve and snaps back to VISIBLE, so
## an enemy pacing along the edge of vision does not flicker through the whole
## sequence repeatedly.

const SHADER_PATH := "res://scripts/fov/vaporize.gdshader"

enum Phase { VISIBLE, LINGERING, VAPORIZING, GONE }

## Seconds an entity stays fully drawn after leaving sight.
var linger_time: float = 1.0
## Seconds the dissolve takes.
var fade_time: float = 0.9

var _shader: Shader
## Per-entity state, keyed by instance id so a freed node cannot keep it alive.
var _tracked: Dictionary = {}

func _init() -> void:
	_shader = load(SHADER_PATH) as Shader

## Per-entity bookkeeping.
class Entry:
	extends RefCounted
	var node: Node2D
	var sprite: CanvasItem
	var material: ShaderMaterial
	var phase: int = Phase.VISIBLE
	var timer: float = 0.0

	func _init(p_node: Node2D, p_sprite: CanvasItem, p_material: ShaderMaterial) -> void:
		node = p_node
		sprite = p_sprite
		material = p_material

## Bring `node` under management. Safe to call repeatedly; only the first call for a
## given node does any work.
func track(node: Node2D) -> void:
	var id := node.get_instance_id()
	if _tracked.has(id):
		return
	var sprite := _find_sprite(node)
	if sprite == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter(&"progress", 0.0)
	mat.set_shader_parameter(&"sprite_size", _sprite_size(sprite))
	sprite.material = mat
	_tracked[id] = Entry.new(node, sprite, mat)

## Advance every tracked entity. `is_visible_fn` is called with the entity's Node2D and
## must return whether the player can currently see it.
func update(delta: float, is_visible_fn: Callable) -> void:
	var dead: Array = []
	for id: int in _tracked:
		var e: Entry = _tracked[id]
		if not is_instance_valid(e.node) or not is_instance_valid(e.sprite):
			dead.append(id)
			continue
		_advance(e, delta, bool(is_visible_fn.call(e.node)))
	for id: int in dead:
		_tracked.erase(id)

func _advance(e: Entry, delta: float, in_sight: bool) -> void:
	if in_sight:
		# Seen again: abandon whatever stage the dissolve had reached.
		if e.phase != Phase.VISIBLE:
			e.phase = Phase.VISIBLE
			e.timer = 0.0
			e.material.set_shader_parameter(&"progress", 0.0)
		e.node.visible = true
		return

	match e.phase:
		Phase.VISIBLE:
			# Just lost sight — start the grace period rather than hiding at once.
			e.phase = Phase.LINGERING
			e.timer = 0.0
			e.node.visible = true
		Phase.LINGERING:
			e.timer += delta
			# Still drawn at its true position, so the player can see where it went.
			if e.timer >= linger_time:
				e.phase = Phase.VAPORIZING
				e.timer = 0.0
		Phase.VAPORIZING:
			e.timer += delta
			var t: float = clampf(e.timer / maxf(fade_time, 0.001), 0.0, 1.0)
			e.material.set_shader_parameter(&"progress", t)
			if t >= 1.0:
				e.phase = Phase.GONE
				e.node.visible = false
		Phase.GONE:
			e.node.visible = false

## Current phase for an entity, for tests and debugging.
func phase_of(node: Node2D) -> int:
	var e: Entry = _tracked.get(node.get_instance_id())
	return e.phase if e != null else Phase.VISIBLE

func tracked_count() -> int:
	return _tracked.size()

func forget_all() -> void:
	_tracked.clear()

## The drawable this entity presents. Enemies and the player use AnimatedSprite2D;
## props are plain Sprite2D. Falling back to the node itself covers anything that
## draws directly.
func _find_sprite(node: Node2D) -> CanvasItem:
	for child in node.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			return child as CanvasItem
	return node as CanvasItem

## Pixel dimensions of the sprite's current frame, so the shader can work in texels.
func _sprite_size(sprite: CanvasItem) -> Vector2:
	if sprite is Sprite2D:
		var s := sprite as Sprite2D
		if s.texture != null:
			return Vector2(s.texture.get_size())
	elif sprite is AnimatedSprite2D:
		var a := sprite as AnimatedSprite2D
		var frames := a.sprite_frames
		if frames != null and frames.has_animation(a.animation):
			var tex := frames.get_frame_texture(a.animation, a.frame)
			if tex != null:
				return Vector2(tex.get_size())
	return Vector2(16, 16)
