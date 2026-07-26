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
##   └─ SpawnPoints  : holds SpawnPoint children

const TILE_SIZE := 16

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
