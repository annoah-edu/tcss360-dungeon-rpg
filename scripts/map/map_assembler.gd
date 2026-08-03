class_name MapAssembler
extends Node2D

## Turns the generator's abstract Placement list into real room instances in the
## scene tree: instantiates each room, positions it, tells it to finalize
## (seal unused doors + register spawns), then drops the player at the start room.

## Directory scanned for room scenes. Every Room scene here with `in_catalog`
## set is eligible for generation; its tags/weight/doors are read straight off the
## scene, so there is no separate catalog resource to keep in sync.
@export_dir var catalog_dir: String = "res://scenes/rooms"
@export var target_rooms: int = 8
## Layout shape: 0 sprawls into long wandering arms, 1 packs a dense blob around the
## start room, 0.5 is the neutral unbiased growth.
@export_range(0.0, 1.0, 0.05) var compactness: float = 0.5
@export var map_seed: int = 0
## When true a fresh seed is drawn each run; uncheck to reproduce a fixed layout.
@export var randomize_seed: bool = true
@export var player_scene: PackedScene
@export var chest_scene: PackedScene

func _ready() -> void:
	if randomize_seed:
		map_seed = randi()
	build()

## Generate and assemble a dungeon. Safe to call again to rebuild.
func build() -> void:
	for child in get_children():
		child.queue_free()
	var director := get_node_or_null("/root/SpawnDirector")
	if director != null:
		director.clear()

	var templates := _load_catalog()
	if templates.is_empty():
		push_warning("MapAssembler: no catalog rooms found in %s" % catalog_dir)
		return

	var gen := MapGenerator.new()
	gen.target_rooms = target_rooms
	gen.compactness = compactness
	var placements := gen.generate(templates, map_seed)
	print("[MapAssembler] seed %d -> %d rooms" % [map_seed, placements.size()])

	var start_room: Room = null
	for pl in placements:
		if pl.template.scene == null:
			continue
		var room: Room = pl.template.scene.instantiate()
		room.position = Vector2(pl.origin * Room.TILE_SIZE)
		add_child(room)
		room.setup(pl.connected)
		if start_room == null and pl.template.has_tag(&"start"):
			start_room = room

	_spawn_player(start_room)
	_spawn_chests()
	if director != null:
		director.populate()

func _load_catalog() -> Array[RoomTemplate]:
	var templates: Array[RoomTemplate] = []
	var dir := DirAccess.open(catalog_dir)
	if dir == null:
		return templates
	for file in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var scene := load(catalog_dir.path_join(file)) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		if inst is Room and (inst as Room).in_catalog:
			templates.append((inst as Room).to_template(scene))
		inst.free()
	return templates

func _spawn_player(start_room: Room) -> void:
	if player_scene == null or start_room == null:
		return
	var player := player_scene.instantiate()
	GameState.player = player # Set the game state's player reference to the player being spawned
	add_child(player)
	var start_marker := _find_player_start(start_room)
	if start_marker != null:
		player.global_position = start_marker.global_position
	else:
		player.global_position = start_room.global_position

func _find_player_start(room: Room) -> SpawnPoint:
	for sp in room.get_spawn_points():
		if sp.category == SpawnPoint.Category.PLAYER_START:
			return sp
	return null

func _spawn_chests() -> void:
	if chest_scene == null:
		push_warning("MapAssembler: no chest scene assigned")
		return

	var director := get_node_or_null("/root/SpawnDirector")
	if director == null:
		return

	var points: Array = director.get_points(SpawnPoint.Category.LOOT)

	for point: SpawnPoint in points:
		var chest := chest_scene.instantiate()
		add_child(chest)
		chest.global_position = point.global_position
