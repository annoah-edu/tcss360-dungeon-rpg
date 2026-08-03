class_name Room
extends Node2D

## A self-contained, reusable dungeon room. It is a passive template: it never
## decides where it goes. The map assembler positions it, then calls method setup
## with the generator's connection result so the room can seal its unused doorways
## and register its spawn points.
##
## Expected child structure:
##   Room (this)
##   ├─ Floor        : TileMapLayer
##   ├─ Walls        : TileMapLayer   (carries collision; drawn with door gaps)
##   ├─ Doors        : holds Door children
##   ├─ Occluders    : holds LightOccluder2D children (optional; sight-blocking outline)
##   ├─ Pillars      : holds LightOccluder2D children (optional; directional-shading regions)
##   └─ SpawnPoints  : holds SpawnPoint children

const TILE_SIZE := 16
## Child node holding authored pillar regions (see get_pillar_polygons).
const PILLARS_NODE := "Pillars"

@export var room_id: StringName = &""
## Roles this room can fill during generation, e.g. &"start", &"combat", &"boss".
@export var tags: Array[StringName] = []
## Relative selection weight; higher rooms are chosen more often by the generator.
@export var weight: float = 1.0
## Uncheck to keep a scene out of the generation catalog (drafts, work-in-progress
## test rooms). The map assembler skips any room whose `in_catalog` is false.
@export var in_catalog: bool = true

func get_floor_layer() -> TileMapLayer:
	return get_node_or_null("Floor") as TileMapLayer

func get_walls_layer() -> TileMapLayer:
	return get_node_or_null("Walls") as TileMapLayer

## Doors in a stable order that matches the template and the placement's
## `connected` array.
func get_doors() -> Array[Door]:
	var result: Array[Door] = []
	var container := get_node_or_null("Doors")
	if container != null:
		for child in container.get_children():
			if child is Door:
				result.append(child)
	return result

## Cells the Walls layer actually paints, in room-local tile coordinates. These are
## the sight-blockers the field of view reasons about. Doorway gaps are absent by
## construction — the author draws walls with holes where doors go — so a connected
## doorway lets sight through and a sealed one does not, because sealing stamps a wall
## tile into the gap (see method Door._stamp_wall).
##
## Safe on an un-parented instance, so it can be read during catalog extraction.
func get_wall_cells() -> Array[Vector2i]:
	var walls := get_walls_layer()
	if walls == null:
		return []
	return walls.get_used_cells()

## Manually authored sight-blocking outlines, in room-local pixel coordinates.
##
## The GPU fog occludes on these polygons rather than on the wall sprites' silhouettes:
## an author draws exactly where sight should stop, which removes the fragile per-tile
## silhouette trimming and the corner/seam leaks it produced where two rooms met.
##
## Authored as LightOccluder2D nodes, by convention under an "Occluders" child — Godot
## ships a polygon editing tool for their OccluderPolygon2D resource and the nodes render
## nothing, so they serve purely as data (the project does not use Godot's own 2D
## lighting). Any LightOccluder2D anywhere under the room counts, so a door can carry its
## own seal occluder as a child (see Door): the author draws where the closed door blocks
## sight, and the door toggles it on only when it seals.
##
## A hidden occluder is skipped. That is what lets a door's authored seal occluder sit in
## the scene — visible to the author in the editor — yet contribute nothing while the
## door is open; the door hides it unless sealed (see Door._set_authored_occluders_active).
##
## Each occluder's points are baked through the transform chain up to this Room, so the
## result is room-local pixels no matter where — or how deep — the node sits.
##
## Pillar regions (see get_pillar_polygons) live under a "Pillars" child and are excluded
## here: a pillar's tall body is a shading marker, not a sight barrier — only its base,
## authored as an ordinary occluder, stops sight.
##
## Safe on an un-parented instance, so it can be read during catalog extraction.
func get_occluder_polygons() -> Array[PackedVector2Array]:
	return _collect_occluders(self, true)

## Manually authored pillar regions, in room-local pixels. A pillar's tall body is drawn
## north of its base, so a southern viewer's line of sight to it is blocked by the base
## even though it is the face they look at. The fog shades a green region directionally —
## lit from the front, dark from behind — instead of self-shadowing or blanket-exempting
## it (see BlockerField). Draw one polygon over the whole pillar sprite, base included, so
## the shader's downward march exits at the floor just south of the base.
##
## Authored as LightOccluder2D nodes under a "Pillars" child, reusing the polygon editor;
## they never block sight, so they are kept out of get_occluder_polygons.
func get_pillar_polygons() -> Array[PackedVector2Array]:
	var container := get_node_or_null(PILLARS_NODE)
	if container == null:
		return []
	return _collect_occluders(container, false)

## Collect the polygons of every visible LightOccluder2D under `root`, baked to room-local
## pixels. When `skip_pillars` is set, the room's "Pillars" subtree is not descended into,
## so seal/wall occluders are gathered without the pillar markers.
func _collect_occluders(root: Node, skip_pillars: bool) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if skip_pillars and node == self and child.name == PILLARS_NODE:
				continue
			stack.append(child)
		if not (node is LightOccluder2D):
			continue
		var occ := node as LightOccluder2D
		if occ.occluder == null or not occ.visible:
			continue
		var points := occ.occluder.polygon
		if points.size() < 3:
			continue
		var xform := _transform_to_room(occ)
		var baked := PackedVector2Array()
		baked.resize(points.size())
		for i in points.size():
			baked[i] = xform * points[i]
		result.append(baked)
	return result

## Transform mapping a descendant's local coordinates into this Room's local space, by
## accumulating node transforms up the parent chain. Used to bake occluder points to
## room-local pixels; works on an un-parented Room, since it never leaves the subtree.
func _transform_to_room(node: Node2D) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		n = n.get_parent()
	return xform

func get_spawn_points() -> Array[SpawnPoint]:
	var result: Array[SpawnPoint] = []
	var container := get_node_or_null("SpawnPoints")
	if container != null:
		for child in container.get_children():
			if child is SpawnPoint:
				result.append(child)
	return result

## Full footprint (floor merged with walls) in room-local tile coordinates.
## Works on an un-parented instance, so it is safe to call during template
## extraction before the room is added to the tree.
func get_bounds() -> Rect2i:
	var floor_layer := get_floor_layer()
	var walls_layer := get_walls_layer()
	var fr := floor_layer.get_used_rect() if floor_layer != null else Rect2i()
	var wr := walls_layer.get_used_rect() if walls_layer != null else Rect2i()
	if fr.size == Vector2i.ZERO:
		return wr
	if wr.size == Vector2i.ZERO:
		return fr
	return fr.merge(wr)

## Build the generator's pure-data view of this room. `source_scene` is the
## PackedScene this instance came from; it is stored on the template so the
## assembler can re-instantiate the room during layout. Safe to call on an
## un-parented instance, so the catalog loader can extract without adding to the tree.
func to_template(source_scene: PackedScene) -> RoomTemplate:
	var t := RoomTemplate.new()
	t.scene = source_scene
	t.id = room_id
	t.tags = tags.duplicate()
	t.weight = weight
	t.bounds = get_bounds()
	for d in get_doors():
		t.doors.append(d.to_room_door())
	return t

## Finalize this room after placement. `connected[i]` says whether door i was
## joined to a neighbour; connected doors open, the rest seal themselves off.
func setup(connected: Array[bool]) -> void:
	var doors := get_doors()
	for i in doors.size():
		var is_connected: bool = i < connected.size() and connected[i]
		var key: StringName = &"open" if is_connected else &"sealed"
		var state: Array[StringName] = [key]
		doors[i].set_states(state)
	_register_spawn_points()

func _register_spawn_points() -> void:
	var director := get_node_or_null("/root/SpawnDirector")
	if director == null:
		return
	for sp in get_spawn_points():
		director.register(sp)
