class_name RayProbe
extends RefCounted

## A CPU replica of the march the field-of-view shader performs, so a ray that lands in
## shadow can be inspected.
##
## The shading itself runs per fragment on the GPU: ~92,000 rays are marched and
## discarded every frame, and none of them exists as an object anything can draw. This
## reproduces that march exactly — same step length, same blocker silhouettes, same
## short-circuit near the destination — for a handful of rays chosen by hand, and
## reports where each one stopped.
##
## Because it mirrors the shader rather than approximating it, a disagreement between
## what this reports and what renders is itself the finding: it means the shader is
## seeing different geometry than BlockerField holds.

## Outcome of a single marched ray.
class Hit:
	extends RefCounted
	## Where the ray started (the player) and where it was headed, in world pixels.
	var origin: Vector2
	var target: Vector2
	## True when masonry stopped the ray before it reached `target`.
	var blocked: bool = false
	## True when the ray simply ran past the sight radius. Kept apart from `blocked`
	## because it is not an occlusion, and conflating the two makes every ray on the
	## rim look like it hit something.
	var out_of_range: bool = false
	## First world position found to be solid. Only meaningful when `blocked`.
	var hit_position: Vector2
	## Tile containing that position, and the pixel within it — the "collider", as far
	## as this system has one. Walls are a bitmask, not a body, so the cell plus local
	## offset is the most specific thing there is to name.
	var hit_cell: Vector2i
	var hit_local: Vector2i
	## Distance from origin to the first solid pixel.
	var hit_distance: float = 0.0
	## Distance the ray would have travelled unobstructed.
	var target_distance: float = 0.0
	## Steps taken before stopping, for spotting step-length artifacts.
	var steps_taken: int = 0

	func describe() -> String:
		if out_of_range:
			return "OUT OF RANGE  origin %s -> target %s  dist %.1f" % [
				origin, target, target_distance]
		if not blocked:
			return "clear  origin %s -> target %s  dist %.1f" % [origin, target, target_distance]
		return "BLOCKED origin %s -> target %s  hit %s  cell %s local %s  dist %.1f of %.1f  steps %d" % [
			origin, target, hit_position, hit_cell, hit_local,
			hit_distance, target_distance, steps_taken]

var _field: BlockerField
var _tile_size: float = 16.0
var _radius_px: float = 144.0
var _step_scale: float = 0.25

func _init(field: BlockerField, tile_size: int, sight_radius: int, step_scale: float = 0.25) -> void:
	_field = field
	_tile_size = float(tile_size)
	_radius_px = float(sight_radius * tile_size)
	_step_scale = step_scale

## March one ray, mirroring fov_fog.gdshader's raw_visibility().
func cast(origin: Vector2, target: Vector2) -> Hit:
	var hit := Hit.new()
	hit.origin = origin
	hit.target = target

	# The shader quantises to whole art pixels before testing anything, so this must
	# too or the two will disagree along shadow edges.
	var world := (target.floor()) + Vector2(0.5, 0.5)
	var delta := world - origin
	var dist := delta.length()
	hit.target_distance = dist
	if dist > _radius_px:
		hit.out_of_range = true
		hit.hit_position = world
		hit.hit_distance = dist
		hit.hit_cell = _cell_of(world)
		hit.hit_local = _local_of(world)
		return hit

	var dir := delta / maxf(dist, 0.0001)
	var step_len := _tile_size * _step_scale
	var steps := int(dist / step_len)
	for i in range(1, steps):
		var p: Vector2 = origin + dir * (float(i) * step_len)
		# Stop short of the destination so a pixel on masonry is lit by its own surface.
		if p.distance_to(world) < step_len:
			break
		hit.steps_taken = i
		if _occludes(p):
			hit.blocked = true
			hit.hit_position = p
			hit.hit_cell = _cell_of(p)
			hit.hit_local = _local_of(p)
			hit.hit_distance = origin.distance_to(p)
			return hit
	return hit

## Cast a fan of rays and return only those that were stopped, which is usually what
## you want when a shadow looks wrong.
func blocked_rays(origin: Vector2, targets: Array[Vector2]) -> Array:
	var out: Array = []
	for t in targets:
		var hit := cast(origin, t)
		if hit.blocked:
			out.append(hit)
	return out

## Ray targets on a ring around `origin`, `count` of them evenly spaced. A quick way to
## sample the pool's boundary.
##
## Defaults to just inside the sight radius rather than exactly on it: a target sitting
## on the boundary trips the range check before any marching happens, which would report
## every rim ray as a hit and drown out the real occlusions.
func ring_targets(origin: Vector2, count: int, radius: float = -1.0) -> Array[Vector2]:
	var r: float = (_radius_px - 1.0) if radius < 0.0 else radius
	var out: Array[Vector2] = []
	for i in count:
		var a: float = TAU * float(i) / float(count)
		out.append(origin + Vector2(cos(a), sin(a)) * r)
	return out

func _occludes(p: Vector2) -> bool:
	return _field != null and _field.is_solid_at(_cell_of(p), _local_of(p))

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _tile_size), floori(p.y / _tile_size))

func _local_of(p: Vector2) -> Vector2i:
	var cell := _cell_of(p)
	return Vector2i(floori(p.x) - cell.x * int(_tile_size), floori(p.y) - cell.y * int(_tile_size))
