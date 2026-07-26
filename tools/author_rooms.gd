extends SceneTree

# One-shot builder: generates the authored room template scenes via code (reliable
# set_cell instead of hand-written tile data), with catalog metadata (tags/weight)
# baked onto the Room node so the scenes are self-describing.
# Run headless, then delete. Rooms are intentionally plain block-outs meant to be
# redecorated in the editor later; the door/spawn wiring is what matters.

const TILE := 16
const FLOOR_SOURCE := 0
const FLOOR_ATLAS := Vector2i(1, 1)
const WALL_SOURCE := 1
const WALL_ATLAS := Vector2i(2, 0)

var tileset: TileSet

func _initialize() -> void:
	tileset = load("res://resources/tilesets/dungeon_tileset.tres")

	# id, w, h, doors:[ [dir, cell], ... ], spawns:[ [category, cell, tags], ... ], tags, weight
	_make_room("start", 9, 9,
		[[Door.Direction.NORTH, Vector2i(4, -1)], [Door.Direction.SOUTH, Vector2i(4, 9)],
		 [Door.Direction.EAST, Vector2i(9, 4)], [Door.Direction.WEST, Vector2i(-1, 4)]],
		[[SpawnPoint.Category.PLAYER_START, Vector2i(4, 4), []],
		 [SpawnPoint.Category.ENEMY, Vector2i(2, 2), []],
		 [SpawnPoint.Category.LOOT, Vector2i(6, 6), []]],
		[&"start"], 1.0)

	_make_room("hall", 11, 5,
		[[Door.Direction.WEST, Vector2i(-1, 2)], [Door.Direction.EAST, Vector2i(11, 2)]],
		[[SpawnPoint.Category.ENEMY, Vector2i(5, 2), []]],
		[&"combat"], 2.0)

	_make_room("junction", 9, 9,
		[[Door.Direction.NORTH, Vector2i(4, -1)], [Door.Direction.SOUTH, Vector2i(4, 9)],
		 [Door.Direction.EAST, Vector2i(9, 4)]],
		[[SpawnPoint.Category.LOOT, Vector2i(4, 4), []],
		 [SpawnPoint.Category.ENEMY, Vector2i(2, 6), []]],
		[&"combat"], 1.5)

	quit()

func _make_room(id: String, w: int, h: int, doors: Array, spawns: Array, tags: Array, weight: float) -> void:
	var room := Room.new()
	room.name = "Room"
	room.room_id = StringName(id)
	room.y_sort_enabled = true
	var typed_tags: Array[StringName] = []
	for tag in tags:
		typed_tags.append(StringName(tag))
	room.tags = typed_tags
	room.weight = weight

	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = tileset
	floor_layer.z_index = -1
	room.add_child(floor_layer)

	var walls_layer := TileMapLayer.new()
	walls_layer.name = "Walls"
	walls_layer.tile_set = tileset
	walls_layer.y_sort_enabled = true
	room.add_child(walls_layer)

	for y in range(h):
		for x in range(w):
			floor_layer.set_cell(Vector2i(x, y), FLOOR_SOURCE, FLOOR_ATLAS, 0)

	for x in range(-1, w + 1):
		walls_layer.set_cell(Vector2i(x, -1), WALL_SOURCE, WALL_ATLAS, 0)
		walls_layer.set_cell(Vector2i(x, h), WALL_SOURCE, WALL_ATLAS, 0)
	for y in range(0, h):
		walls_layer.set_cell(Vector2i(-1, y), WALL_SOURCE, WALL_ATLAS, 0)
		walls_layer.set_cell(Vector2i(w, y), WALL_SOURCE, WALL_ATLAS, 0)

	var doors_node := Node2D.new()
	doors_node.name = "Doors"
	room.add_child(doors_node)
	for entry in doors:
		var dir: int = entry[0]
		var cell: Vector2i = entry[1]
		# Draw the doorway already open — gap in the walls, floor laid across it — so
		# connected doors are passable without the engine touching tiles at runtime.
		walls_layer.erase_cell(cell)
		floor_layer.set_cell(cell, FLOOR_SOURCE, FLOOR_ATLAS, 0)
		var door := Door.new()
		door.name = "Door_" + _dir_name(dir)
		door.direction = dir
		door.position = Vector2(cell * TILE) + Vector2(TILE / 2.0, TILE / 2.0)
		doors_node.add_child(door)

	var spawns_node := Node2D.new()
	spawns_node.name = "SpawnPoints"
	room.add_child(spawns_node)
	for entry in spawns:
		var sp := SpawnPoint.new()
		sp.category = entry[0]
		sp.position = Vector2(entry[1] * TILE) + Vector2(TILE / 2.0, TILE / 2.0)
		if entry.size() > 2 and entry[2] is Array:
			var t: Array[StringName] = []
			for tag in entry[2]:
				t.append(StringName(tag))
			sp.tags = t
		spawns_node.add_child(sp)

	_set_owner_recursive(room, room)

	var packed := PackedScene.new()
	packed.pack(room)
	var scene_path := "res://scenes/rooms/room_%s.tscn" % id
	var err := ResourceSaver.save(packed, scene_path)
	print("scene ", scene_path, " -> ", err)

	room.free()

func _dir_name(dir: int) -> String:
	match dir:
		Door.Direction.NORTH: return "N"
		Door.Direction.SOUTH: return "S"
		Door.Direction.EAST: return "E"
		Door.Direction.WEST: return "W"
	return "X"

func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child != owner:
			child.owner = owner
		_set_owner_recursive(child, owner)
