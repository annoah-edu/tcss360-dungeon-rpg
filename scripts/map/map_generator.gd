class_name MapGenerator
extends RefCounted

## Pure, deterministic dungeon layout via door-matching organic growth. Given a
## set of RoomTemplates and an integer seed it returns an ordered list of
## Placements and touches no scene nodes, which keeps it fully unit-testable.
##
## Algorithm:
##   1. Place a `start`-tagged room at the origin; push its doors to a frontier.
##   2. Repeatedly pop an open door (biased by `compactness`), pick a weighted-random
##      compatible room, align it door-to-door, and reject it if its interior overlaps
##      any placed room. On success, add the new room's remaining doors to the frontier.
##   3. Stop when the frontier empties or `target_rooms` is reached.

var target_rooms: int = 16

## How tightly the layout clusters around the start room, from 0.0 (sprawling: long
## rambling arms that wander far out) to 1.0 (compact: a dense blob that fills in
## close to the origin before reaching outward). 0.5 is the neutral middle.
##
## It steers two independent choices, both of which stay fully deterministic:
##   * which open door is expanded next — high compactness prefers doors near the
##     origin, low compactness prefers the ones furthest out;
##   * where a candidate room is allowed to land — high compactness also favours
##     placements that hug already-placed rooms rather than striking out.
var compactness: float = 0.5

## Frontier doors sampled when picking where to grow next. Larger values make the
## compactness bias more decisive (and cost a little more time per room); the pool
## is capped by the frontier size, so small frontiers are unaffected.
var selection_pool: int = 4

## Corridors joining the placed rooms, one per connection. Populated by generate()
## alongside the returned placements, then read by MapAssembler to build the geometry.
var connectors: Array[Connector] = []

var _rng := RandomNumberGenerator.new()

## Origin (in world tile coords) at which a room carrying `new_door` must be
## placed so that door lines up gap-to-gap with `host_door` on a room at
## `host_origin`. `gap` is the number of tiles between the two door thresholds — 1 for
## rooms placed flush, or connector_length + 1 when a corridor sits between them. Pure and
## side-effect free, so it is unit-tested directly.
static func aligned_origin(host_origin: Vector2i, host_door: RoomDoor, new_door: RoomDoor, gap: int = 1) -> Vector2i:
	return host_origin + host_door.cell + Door.direction_vector(host_door.direction) * gap - new_door.cell

## Build a dungeon layout from `templates` using `p_seed`. Returns the placed rooms
## in the order they were added (the start room is always first), or an empty array
## if no templates are given. Deterministic: the same templates and seed always
## produce the same layout.
func generate(templates: Array[RoomTemplate], p_seed: int) -> Array[Placement]:
	_rng.seed = p_seed
	connectors = []
	var placements: Array[Placement] = []
	if templates.is_empty():
		return placements

	var start := _pick_start(templates)
	placements.append(Placement.new(start, Vector2i.ZERO))

	# Rooms eligible to grow the dungeon: everything except unique start rooms.
	var growth := _growth_templates(templates)

	# Frontier of open doors, each stored as placement_index, door_index.
	var frontier: Array = []
	_push_doors(frontier, 0, start)

	while not frontier.is_empty() and placements.size() < target_rooms:
		var pick := _pick_frontier_index(frontier, placements)
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

## Choose which open door to grow from next. Sampling a few candidates and keeping
## the best by distance from the origin — rather than scanning the whole frontier —
## leaves the choice random at heart, so the bias shapes the layout without
## collapsing it into the same predictable spiral every run.
##
## At compactness 0.5 the sampled doors are equally acceptable and this degrades to
## the uniform random pick the generator used before the knob existed.
func _pick_frontier_index(frontier: Array, placements: Array[Placement]) -> int:
	var best := _rng.randi_range(0, frontier.size() - 1)
	if is_equal_approx(compactness, 0.5):
		return best

	# Above 0.5 we want the nearest door (fill in close), below it the furthest
	# (push arms outward). Strength scales with the distance from neutral.
	var prefer_near := compactness > 0.5
	var samples := mini(_sample_count(), frontier.size())
	var best_score := _frontier_distance(frontier[best], placements)
	for _i in samples - 1:
		var idx := _rng.randi_range(0, frontier.size() - 1)
		var score := _frontier_distance(frontier[idx], placements)
		if (score < best_score) == prefer_near and score != best_score:
			best = idx
			best_score = score
	return best

## Number of frontier doors to sample per pick: 1 at neutral compactness (a plain
## uniform choice) rising to `selection_pool` at either extreme.
func _sample_count() -> int:
	var strength := absf(compactness - 0.5) * 2.0
	return maxi(1, int(round(lerpf(1.0, float(maxi(selection_pool, 1)), strength))))

## Chebyshev distance from the origin to an open door's outward threshold. Chebyshev
## rather than Euclidean because rooms tile the plane in a grid: it treats a diagonal
## step as one step, which matches how the layout actually spreads.
func _frontier_distance(entry: Array, placements: Array[Placement]) -> int:
	var host: Placement = placements[entry[0]]
	var door: RoomDoor = host.template.doors[entry[1]]
	var cell := host.origin + door.cell + Door.direction_vector(door.direction)
	return maxi(absi(cell.x), absi(cell.y))

## Align a compatible room to the given open door and place it if it fits.
## Returns the new placement index, or -1 if nothing could attach.
##
## Candidates are tried in weighted-random order, but when compactness is high the
## first fitting option is not taken blindly: a few fitting options are compared and
## the one that packs closest to the existing rooms wins.
func _try_attach(templates: Array[RoomTemplate], placements: Array[Placement], host_index: int, door_index: int) -> int:
	var host := placements[host_index]
	var a: RoomDoor = host.template.doors[door_index]

	var best_cand: RoomTemplate = null
	var best_door := -1
	var best_origin := Vector2i.ZERO
	var best_conn: Connector = null
	var best_score := 0.0
	var considered := 0
	var limit := _placement_choices()

	for cand in _weighted_order(templates):
		for bi in cand.doors.size():
			var b: RoomDoor = cand.doors[bi]
			if not a.is_compatible(b):
				continue
			# A corridor sits between the two rooms, so b's threshold lands connector +
			# 1 tiles out. Try lengths until one leaves both the corridor and the room
			# clear; a fit is not guaranteed, so this can come back empty.
			var fit := _fit_connector(host, a, cand, b, placements)
			if fit.is_empty():
				continue
			var origin_b: Vector2i = fit["origin"]
			var conn: Connector = fit["connector"]
			var score := _placement_score(cand, origin_b, placements)
			if best_cand == null or score > best_score:
				best_cand = cand
				best_door = bi
				best_origin = origin_b
				best_conn = conn
				best_score = score
			considered += 1
			# At low compactness `limit` is 1, so this keeps the original behaviour of
			# committing to the first room that fits.
			if considered >= limit:
				return _commit(placements, host, door_index, best_cand, best_door, best_origin, best_conn)

	if best_cand == null:
		return -1
	return _commit(placements, host, door_index, best_cand, best_door, best_origin, best_conn)

## Find a corridor length that lets both the connector and the attached room sit clear of
## everything placed. Tries a weighted-random length first (so 3 dominates and 2/4 vary),
## then the remaining lengths as fallbacks so a tight spot still connects when it can.
## Returns {origin, connector} or {} if no length fits.
func _fit_connector(host: Placement, a: RoomDoor, cand: RoomTemplate, b: RoomDoor, placements: Array[Placement]) -> Dictionary:
	var door_world := host.origin + a.cell
	for length in _connector_lengths():
		var origin_b := aligned_origin(host.origin, a, b, length + 1)
		var conn := Connector.new(door_world, a.direction, length, a.width)
		if _placement_fits(cand, origin_b, conn, placements):
			return {"origin": origin_b, "connector": conn}
	return {}

## Candidate corridor lengths, the weighted-random pick first then the rest. Weighted 2:3:4
## as 1:2:1, so 3 is the default look with 2 and 4 as variation.
func _connector_lengths() -> Array[int]:
	var roll := _rng.randf()
	var first := 3
	if roll < 0.25:
		first = 2
	elif roll >= 0.75:
		first = 4
	var rest: Array[int] = [3, 2, 4]
	rest.erase(first)
	var order: Array[int] = [first]
	order.append_array(rest)
	return order

## Whether an attached room (its interior) and its connector (its footprint) both clear
## every placed room's interior and every placed corridor.
func _placement_fits(cand: RoomTemplate, origin_b: Vector2i, conn: Connector, placements: Array[Placement]) -> bool:
	var room_rect := cand.interior(origin_b)
	var conn_rect := conn.footprint()
	for pl in placements:
		var pl_in := pl.template.interior(pl.origin)
		if room_rect.intersects(pl_in) or conn_rect.intersects(pl_in):
			return false
	for other in connectors:
		var other_rect := other.footprint()
		if room_rect.intersects(other_rect) or conn_rect.intersects(other_rect):
			return false
	return true

## How many fitting candidates to weigh against each other before committing. Only
## compactness above neutral looks past the first fit; sprawling layouts gain nothing
## from packing rooms tightly, so they keep the cheaper first-fit path.
func _placement_choices() -> int:
	if compactness <= 0.5:
		return 1
	var strength := (compactness - 0.5) * 2.0
	return maxi(1, int(round(lerpf(1.0, float(maxi(selection_pool, 1)), strength))))

## Rate a candidate placement: higher is better. Compact layouts prefer rooms whose
## centre stays near the origin and whose footprint shares edges with what is already
## placed, which is what turns a rambling arm into a filled-in blob.
func _placement_score(cand: RoomTemplate, origin: Vector2i, placements: Array[Placement]) -> float:
	var rect := cand.footprint(origin)
	var centre := rect.position + rect.size / 2
	var distance := float(maxi(absi(centre.x), absi(centre.y)))
	# Rooms touching this one on a shared wall line: grown by a tile, an adjacent
	# footprint starts to intersect, which is exactly the contact we want to reward.
	var touching := 0
	var probe := rect.grow(1)
	for pl in placements:
		if probe.intersects(pl.template.footprint(pl.origin)):
			touching += 1
	return float(touching) * 10.0 - distance

func _commit(placements: Array[Placement], host: Placement, door_index: int, cand: RoomTemplate, cand_door: int, origin: Vector2i, conn: Connector) -> int:
	var pl := Placement.new(cand, origin)
	pl.connected[cand_door] = true
	placements.append(pl)
	host.connected[door_index] = true
	connectors.append(conn)
	return placements.size() - 1

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

## Return the templates in a weighted-random order: higher-weight rooms tend to come
## first, and each template appears exactly once.
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
