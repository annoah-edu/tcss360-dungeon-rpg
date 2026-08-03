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

## March one ray, mirroring fov_fog.gdshader's raw_visibility() — the same pixel-exact
## DDA, so what this reports is what the shader saw. A fixed-stride march would step over
## thin occluders; walking every pixel the ray enters cannot.
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

	var cur := Vector2i(floori(origin.x), floori(origin.y))
	var goal := Vector2i(floori(world.x), floori(world.y))
	if cur == goal:
		return hit

	# Amanatides–Woo: t_max is the ray parameter at the next pixel boundary per axis,
	# t_delta the parameter spent crossing one pixel. Advancing the smaller walks pixels.
	var stp := Vector2i.ZERO
	var t_max := Vector2(1e30, 1e30)
	var t_delta := Vector2(1e30, 1e30)
	if delta.x > 0.0:
		stp.x = 1
		t_max.x = (float(cur.x) + 1.0 - origin.x) / delta.x
		t_delta.x = 1.0 / delta.x
	elif delta.x < 0.0:
		stp.x = -1
		t_max.x = (origin.x - float(cur.x)) / -delta.x
		t_delta.x = -1.0 / delta.x
	if delta.y > 0.0:
		stp.y = 1
		t_max.y = (float(cur.y) + 1.0 - origin.y) / delta.y
		t_delta.y = 1.0 / delta.y
	elif delta.y < 0.0:
		stp.y = -1
		t_max.y = (origin.y - float(cur.y)) / -delta.y
		t_delta.y = -1.0 / delta.y

	var max_steps := int(_radius_px) * 2 + 2
	for i in max_steps:
		if t_max.x < t_max.y:
			cur.x += stp.x
			t_max.x += t_delta.x
		else:
			cur.y += stp.y
			t_max.y += t_delta.y
		# Stop at the destination pixel: it is lit by its own surface, not shadowed by it.
		if cur == goal:
			break
		hit.steps_taken = i + 1
		if _field != null and _field.is_solid_at(_cell_of_pixel(cur), _local_of_pixel(cur)):
			hit.blocked = true
			hit.hit_position = Vector2(cur) + Vector2(0.5, 0.5)
			hit.hit_cell = _cell_of_pixel(cur)
			hit.hit_local = _local_of_pixel(cur)
			hit.hit_distance = origin.distance_to(hit.hit_position)
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

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _tile_size), floori(p.y / _tile_size))

func _local_of(p: Vector2) -> Vector2i:
	var cell := _cell_of(p)
	return Vector2i(floori(p.x) - cell.x * int(_tile_size), floori(p.y) - cell.y * int(_tile_size))

## Cell containing a whole-numbered world pixel.
func _cell_of_pixel(pix: Vector2i) -> Vector2i:
	return Vector2i(floori(pix.x / _tile_size), floori(pix.y / _tile_size))

## Offset of a whole-numbered world pixel within its cell.
func _local_of_pixel(pix: Vector2i) -> Vector2i:
	var cell := _cell_of_pixel(pix)
	var ts := int(_tile_size)
	return Vector2i(pix.x - cell.x * ts, pix.y - cell.y * ts)
