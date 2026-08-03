extends SceneTree

# One-shot bootstrap: gives every room a starter set of sight-blocking occluders so the
# GPU fog has geometry to march against, then re-saves the scene.
#
# The fog no longer derives occlusion from the wall sprites' silhouettes; it marches the
# authored occluder polygons instead (see BlockerField.add_polygon). This emits a first
# pass of those polygons — one full-cell rectangle per maximal block of wall cells — under
# an "Occluders" child. Full cells guarantee no seams out of the box: neighbouring rooms
# share their boundary wall cells, so their rectangles overlap and union into one barrier.
#
# It is a starting point, not the finished art. Full cells occlude a wall's inward face
# too, so shadows start a touch early there; open the rooms in the editor and pull those
# interior edges back by hand where you want sight to reach the near face. Re-running is
# safe — it replaces any Occluders node it finds.
#
# Run headless:
#   godot --headless -s tools/generate_occluders.gd

const ROOMS_DIR := "res://scenes/rooms"
const TILE := 16
const OCCLUDERS_NODE := "Occluders"

func _initialize() -> void:
	var dir := DirAccess.open(ROOMS_DIR)
	if dir == null:
		push_error("generate_occluders: cannot open %s" % ROOMS_DIR)
		quit(1)
		return
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			_process_room(ROOMS_DIR.path_join(file))
	quit()

func _process_room(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("skip (not a scene): ", path)
		return
	var room := scene.instantiate()
	if not (room is Room):
		print("skip (not a Room): ", path)
		room.free()
		return

	var walls := (room as Room).get_walls_layer()
	if walls == null:
		print("skip (no Walls layer): ", path)
		room.free()
		return

	# Replace any prior Occluders node so re-runs are idempotent.
	var existing := room.get_node_or_null(OCCLUDERS_NODE)
	if existing != null:
		room.remove_child(existing)
		existing.free()

	var container := Node2D.new()
	container.name = OCCLUDERS_NODE
	room.add_child(container)

	var rects := _rectangles(walls.get_used_cells())
	for r: Rect2i in rects:
		container.add_child(_make_occluder(r))

	_set_owner_recursive(room, room)

	var packed := PackedScene.new()
	packed.pack(room)
	var err := ResourceSaver.save(packed, path)
	print("occluders %d -> %s  (err %d)" % [rects.size(), path, err])
	room.free()

## One LightOccluder2D covering a rectangular block of wall cells, its polygon in
## room-local pixels. Points at the origin: the polygon already carries the position.
func _make_occluder(r: Rect2i) -> LightOccluder2D:
	var poly := OccluderPolygon2D.new()
	var tl := Vector2(r.position * TILE)
	var size := Vector2(r.size * TILE)
	poly.polygon = PackedVector2Array([
		tl,
		tl + Vector2(size.x, 0.0),
		tl + size,
		tl + Vector2(0.0, size.y),
	])
	var occ := LightOccluder2D.new()
	occ.name = "Occ_%d_%d" % [r.position.x, r.position.y]
	occ.occluder = poly
	return occ

## Greedy maximal-rectangle cover of a set of wall cells: repeatedly take the top-left
## remaining cell, grow the widest row it can, then the tallest full-width block, and
## remove it. Produces a handful of big rectangles for a room's walls instead of one per
## cell, which is far easier to hand-edit afterwards.
func _rectangles(cells: Array[Vector2i]) -> Array[Rect2i]:
	var remaining: Dictionary = {}
	for c in cells:
		remaining[c] = true

	var order := remaining.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)

	var rects: Array[Rect2i] = []
	for start: Vector2i in order:
		if not remaining.has(start):
			continue
		var w := 1
		while remaining.has(start + Vector2i(w, 0)):
			w += 1
		var h := 1
		while _row_present(remaining, start + Vector2i(0, h), w):
			h += 1
		for dy in h:
			for dx in w:
				remaining.erase(start + Vector2i(dx, dy))
		rects.append(Rect2i(start, Vector2i(w, h)))
	return rects

func _row_present(remaining: Dictionary, row_start: Vector2i, w: int) -> bool:
	for dx in w:
		if not remaining.has(row_start + Vector2i(dx, 0)):
			return false
	return true

func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child != owner_node:
			child.owner = owner_node
		_set_owner_recursive(child, owner_node)
