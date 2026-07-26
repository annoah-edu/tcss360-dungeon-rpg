class_name MapGenerator
extends RefCounted

## Pure, deterministic dungeon layout via door-matching organic growth. Given a
## set of [RoomTemplate]s and an integer seed it returns an ordered list of
## [Placement]s and touches no scene nodes, which keeps it fully unit-testable.
##
## Algorithm:
##   1. Place a `start`-tagged room at the origin; push its doors to a frontier.
##   2. Repeatedly pop a random open door, pick a weighted-random compatible room,
##      align it door-to-door, and reject it if its interior overlaps any placed
##      room. On success, add the new room's remaining doors to the frontier.
##   3. Stop when the frontier empties or `target_rooms` is reached.

var target_rooms: int = 8

var _rng := RandomNumberGenerator.new()

## Origin (in world tile coords) at which a room carrying `new_door` must be
## placed so that door lines up gap-to-gap with `host_door` on a room at
## `host_origin`. Pure and side-effect free, so it is unit-tested directly.
static func aligned_origin(host_origin: Vector2i, host_door: RoomDoor, new_door: RoomDoor) -> Vector2i:
	return host_origin + host_door.cell + Door.direction_vector(host_door.direction) - new_door.cell

func generate(templates: Array[RoomTemplate], p_seed: int) -> Array[Placement]:
	_rng.seed = p_seed
	var placements: Array[Placement] = []
	if templates.is_empty():
		return placements

	var start := _pick_start(templates)
	placements.append(Placement.new(start, Vector2i.ZERO))

	# Rooms eligible to grow the dungeon: everything except unique start rooms.
	var growth := _growth_templates(templates)

	# Frontier of open doors, each stored as [placement_index, door_index].
	var frontier: Array = []
	_push_doors(frontier, 0, start)

	while not frontier.is_empty() and placements.size() < target_rooms:
		var pick := _rng.randi_range(0, frontier.size() - 1)
		var entry: Array = frontier[pick]
		frontier.remove_at(pick)
		var host_index: int = entry[0]
		var door_index: int = entry[1]
		if placements[host_index].connected[door_index]:
			continue
		var new_index := _try_attach(growth, placements, host_index, door_index)
		if new_index >= 0:
			_push_doors(frontier, new_index, placements[new_index].template)

	return placements

## Align a compatible room to the given open door and place it if it fits.
## Returns the new placement index, or -1 if nothing could attach.
func _try_attach(templates: Array[RoomTemplate], placements: Array[Placement], host_index: int, door_index: int) -> int:
	var host := placements[host_index]
	var a: RoomDoor = host.template.doors[door_index]

	for cand in _weighted_order(templates):
		for bi in cand.doors.size():
			var b: RoomDoor = cand.doors[bi]
			if not a.is_compatible(b):
				continue
			# Put b's threshold one tile outward from a's, so the gaps line up.
			var origin_b: Vector2i = aligned_origin(host.origin, a, b)
			if _overlaps(cand, origin_b, placements):
				continue
			var pl := Placement.new(cand, origin_b)
			pl.connected[bi] = true
			placements.append(pl)
			host.connected[door_index] = true
			return placements.size() - 1
	return -1

func _overlaps(cand: RoomTemplate, origin: Vector2i, placements: Array[Placement]) -> bool:
	var rect := cand.interior(origin)
	for pl in placements:
		if rect.intersects(pl.template.interior(pl.origin)):
			return true
	return false

func _pick_start(templates: Array[RoomTemplate]) -> RoomTemplate:
	for t in templates:
		if t.has_tag(&"start"):
			return t
	return templates[0]

## Templates usable to grow the dungeon: excludes unique start rooms so they are
## never duplicated. Falls back to all templates if nothing else is available.
func _growth_templates(templates: Array[RoomTemplate]) -> Array[RoomTemplate]:
	var result: Array[RoomTemplate] = []
	for t in templates:
		if not t.has_tag(&"start"):
			result.append(t)
	if result.is_empty():
		return templates
	return result

func _push_doors(frontier: Array, placement_index: int, template: RoomTemplate) -> void:
	for i in template.doors.size():
		frontier.append([placement_index, i])

## Weighted random ordering (sampling without replacement) of the templates.
func _weighted_order(templates: Array[RoomTemplate]) -> Array[RoomTemplate]:
	var pool := templates.duplicate()
	var result: Array[RoomTemplate] = []
	while not pool.is_empty():
		var total := 0.0
		for t in pool:
			total += maxf(t.weight, 0.0001)
		var r := _rng.randf() * total
		var acc := 0.0
		var chosen := 0
		for i in pool.size():
			acc += maxf(pool[i].weight, 0.0001)
			if r <= acc:
				chosen = i
				break
		result.append(pool[chosen])
		pool.remove_at(chosen)
	return result
