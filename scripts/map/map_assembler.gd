class_name MapAssembler
extends Node2D

## Turns the generator's abstract Placement list into real room instances in the
## scene tree: instantiates each room, positions it, tells it to finalize
## (seal unused doors + register spawns), then drops the player at the start room.

const SEEN_MASK_SHADER := "res://scripts/fov/seen_mask.gdshader"
## How often to sweep the scene for newly spawned entities to track. Walking the tree
## every frame is wasteful when spawns are occasional.
const TRACK_INTERVAL := 0.5

## Authored one-tile corridor slices, tiled along a connector's length instead of painting
## its cells by hand. Each slice is a Room carrying its floor, side walls, under-wall filler
## and edge occluders, so a placed slice registers through the exact pipeline the rooms use.
## The vertical slice serves NORTH/SOUTH runs, the horizontal one EAST/WEST; both are 3 wide,
## matching every door, so no width variants are needed. Each slice's node origin sits on its
## far side wall (east on the vertical slice, south on the horizontal one).
const CONNECTOR_VERTICAL_SCENE := preload("res://scenes/rooms/connector_south_north.tscn")
const CONNECTOR_HORIZONTAL_SCENE := preload("res://scenes/rooms/connector_east_west.tscn")

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
## Dropped into the room furthest from the start so the sole way out sits at a layout
## edge. Reaching it ends the run and opens the statistics summary.
@export var exit_scene: PackedScene

@export_group("Visibility")
## Master switch: off leaves the whole dungeon lit, which is handy while authoring
## rooms or debugging generation.
@export var fog_enabled: bool = true
## How far the player sees, in tiles. Sight is blocked by walls, so this is an upper
## bound rather than a guaranteed radius.
@export var sight_radius: int = 9
## How dark remembered, currently-unseen ground is drawn.
@export_range(0.0, 1.0, 0.05) var remembered_darkness: float = 0.55
## Opacity of never-seen space. Left at 0 so the starfield backdrop reads through it.
@export_range(0.0, 1.0, 0.05) var unseen_opacity: float = 0.0
## Ray-march step as a fraction of a tile, for the fog shader. Smaller is more precise
## around corners; measured free well past this, so tune for artifacts not speed.
@export_range(0.05, 1.0, 0.05) var fov_step_scale: float = 0.25
## Draw the rays behind the shadowing: origin, path, first solid pixel, the cell that
## stopped it, and the hit distance. Diagnostic only — the real shading runs per
## fragment on the GPU, so these are a CPU replica of the same march.
@export var debug_rays: bool = false:
	set(value):
		debug_rays = value
		if _ray_overlay != null:
			_ray_overlay.enabled = value
		_refresh_debug_rays()
## How many rays to fan out from the player when `debug_rays` is on.
@export_range(4, 256, 4) var debug_ray_count: int = 64
## Show rays that reached their target as well as those that were stopped.
@export var debug_show_clear_rays: bool = false:
	set(value):
		debug_show_clear_rays = value
		if _ray_overlay != null:
			_ray_overlay.show_clear_rays = value

## Seconds an entity stays fully drawn after leaving sight, so the player registers
## where it actually was before it fades.
@export var entity_linger_time: float = 1.0
## Seconds the pixel-scatter dissolve takes once the linger expires.
@export var entity_fade_time: float = 0.9

@export_group("Background")
## Draw the drifting star-map backdrop behind the dungeon.
@export var starfield_enabled: bool = true
## Camera zoom the backdrop matches so its lines land at the same pixel density as the
## tile art. Keep in step with the player camera's zoom.
@export var starfield_pixel_scale: int = 5

@export_group("Minimap")
## Draw the bottom-right minimap of explored rooms and corridors.
@export var minimap_enabled: bool = true
## Minimap square side, in screen pixels (rounded to a whole number of minimap pixels).
@export var minimap_size: float = 200.0
## Screen pixels per minimap pixel. Match the player camera's zoom (5) so the minimap
## renders on the same pixel grid as the game rather than as hairline lines.
@export var minimap_pixel_size: int = 5
## Minimap pixels per world pixel. Below 1 so a whole room shrinks into the square; held
## fixed so the drawn density stays uniform instead of jumping between rooms.
@export_range(0.01, 1.0, 0.01) var minimap_scale: float = 0.05
## Gap from the bottom-right corner, in screen pixels.
@export var minimap_margin: float = 12.0

## Field-of-view state for the assembled dungeon: which tiles are lit now and which
## are remembered. Built during method build() and read by the fog overlay.
var visibility := VisibilityMap.new()

var _fov: FovRenderer
## Walls packed for the GPU. Rebuilt with the dungeon, not with player movement.
var _blockers := BlockerField.new()
## Room tile layers clipped to the seen memory, so the mask can be toggled with the fog.
var _masked_layers: Array[ShaderMaterial] = []
var _starfield: Starfield
var _minimap: Minimap
## Minimap feature data, accumulated as rooms, corridors and chests are placed, then
## handed to the minimap once the build finishes.
var _mm_rooms: Array[Dictionary] = []
var _mm_connectors: Array[Dictionary] = []
var _mm_chests: Array[Dictionary] = []
## Diagnostic ray drawing. Null unless `debug_rays` has been on since the last build.
var _ray_overlay: RayDebugOverlay
var _ray_probe: RayProbe
var _player: Node2D
## Drives the linger-then-dissolve effect for entities leaving the player's sight.
var _vaporizer := Vaporizer.new()
var _track_accumulator := 0.0
## Tile the fog was last rebuilt for; visibility only changes when the player crosses
## into a new tile, so this gates the per-frame work down to roughly six updates a
## second at walking speed.
var _last_tile := Vector2i(2147483647, 2147483647)
## Room-exploration tracking, independent of the fog so it works with fog disabled.
## `_visited_rooms` holds the minimap-room indices already counted this run.
var _explore_last_tile := Vector2i(2147483647, 2147483647)
var _visited_rooms: Dictionary = {}

func _ready() -> void:
	# When launched from the start screen, take the seed it staged and open a tracked run.
	# Run standalone in the editor there is no request, so the exported seed is used and
	# no statistics are recorded.
	if Stats.run_requested:
		Stats.run_requested = false
		randomize_seed = Stats.pending_randomize
		map_seed = Stats.pending_seed
		Stats.begin_run()
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

	visibility.reset()
	_blockers.clear()
	_masked_layers.clear()
	_visited_rooms.clear()
	_explore_last_tile = Vector2i(2147483647, 2147483647)
	_mm_rooms.clear()
	_mm_connectors.clear()
	_mm_chests.clear()

	var start_room: Room = null
	# Room whose origin sits furthest (Chebyshev) from the start at the origin — the
	# layout edge where the single exit goes.
	var exit_room: Room = null
	var exit_dist := -1
	for pl in placements:
		if pl.template.scene == null:
			continue
		var room: Room = pl.template.scene.instantiate()
		room.position = Vector2(pl.origin * Room.TILE_SIZE)
		add_child(room)
		room.setup(pl.connected)
		# Registering after setup() matters: sealing an unconnected door stamps a wall
		# tile into its gap, so the blockers read here already include doors that
		# closed. A connected doorway keeps its gap and stays see-through.
		_register_blockers(room, pl.origin)
		_record_minimap_room(room, pl.origin)
		if start_room == null and pl.template.has_tag(&"start"):
			start_room = room
		elif not pl.template.has_tag(&"start"):
			var dist := maxi(absi(pl.origin.x), absi(pl.origin.y))
			if dist > exit_dist:
				exit_dist = dist
				exit_room = room

	# Corridors joining the rooms. Built after the rooms so a connector never registers
	# blockers a room then overwrites; each is its own Room node, so the fog and seen-mask
	# passes pick it up exactly like an authored room.
	for conn in gen.connectors:
		_build_connector(conn)

	_spawn_player(start_room)
	_spawn_chests()
	# Fall back to the start room if the layout produced no other room, so there is
	# always exactly one exit.
	_spawn_exit(exit_room if exit_room != null else start_room)
	if director != null:
		director.populate()
	# The enemy spawner is an autoload, so it can't spawn itself onto a map that only
	# exists now; drive it from here once the ENEMY spawn points are registered.
	var enemy_spawner := get_node_or_null("/root/EnemySpawner")
	if enemy_spawner != null:
		enemy_spawner.populate_map()
	# The pillar spawner is an autoload too.
	var pillar_spawner := get_node_or_null("/root/PillarSpawner")
	if pillar_spawner != null:
		pillar_spawner.populate_map()
	_setup_fog()
	_setup_starfield()
	_setup_minimap()

## Add the star-map backdrop. Rebuilt alongside everything else, since build() frees
## all children; it holds no dungeon state, so recreating it costs nothing.
func _setup_starfield() -> void:
	_starfield = null
	if not starfield_enabled:
		return
	_starfield = Starfield.new()
	_starfield.name = "Starfield"
	_starfield.pixel_scale = starfield_pixel_scale
	add_child(_starfield)

## Create the GPU fog renderer and prime it around the player's start, so the first
## frame is already correct rather than flashing a fully-lit dungeon.
func _setup_fog() -> void:
	_fov = null
	_last_tile = Vector2i(2147483647, 2147483647)
	_vaporizer.forget_all()
	_vaporizer.linger_time = entity_linger_time
	_vaporizer.fade_time = entity_fade_time
	if not fog_enabled or _player == null:
		return
	if not _blockers.commit():
		push_warning("MapAssembler: no walls to build a blocker field from")
		return

	_fov = FovRenderer.new()
	_fov.name = "FovRenderer"
	_fov.remembered_darkness = remembered_darkness
	_fov.unseen_opacity = unseen_opacity
	_fov.step_scale = fov_step_scale
	add_child(_fov)
	_fov.setup(_blockers, Room.TILE_SIZE, sight_radius)
	_setup_ray_debug()
	_apply_seen_mask()
	_refresh_visibility(true)
	# The memory target only exists once setup() has run, so the room clip materials are
	# pointed at it afterwards.
	_bind_memory_to_masks()

## Build the ray diagnostic. The probe mirrors the shader's march on the CPU, so what
## it reports is what the shader saw — a disagreement between the two is itself the
## finding.
func _setup_ray_debug() -> void:
	_ray_probe = RayProbe.new(_blockers, Room.TILE_SIZE, sight_radius, fov_step_scale)
	_ray_overlay = RayDebugOverlay.new()
	_ray_overlay.name = "RayDebugOverlay"
	_ray_overlay.tile_size = Room.TILE_SIZE
	_ray_overlay.show_clear_rays = debug_show_clear_rays
	_ray_overlay.enabled = debug_rays
	add_child(_ray_overlay)

## Re-cast the diagnostic fan from the player's current position.
func _refresh_debug_rays() -> void:
	if _ray_overlay == null or _ray_probe == null:
		return
	if not debug_rays or _player == null or not is_instance_valid(_player):
		_ray_overlay.clear_hits()
		return
	var origin: Vector2 = _player.global_position
	var targets := _ray_probe.ring_targets(origin, debug_ray_count)
	var hits: Array = []
	for t in targets:
		hits.append(_ray_probe.cast(origin, t))
	_ray_overlay.show_hits(hits)

## Report the blocked rays from the player's position, for logging rather than drawing.
func debug_blocked_rays() -> Array:
	if _ray_probe == null or _player == null:
		return []
	var origin: Vector2 = _player.global_position
	return _ray_probe.blocked_rays(origin, _ray_probe.ring_targets(origin, debug_ray_count))

## Hand the accumulated-memory texture to every room's clipping material. Re-pointed
## whenever the ping-pong swaps, since each step writes a different target.
func _bind_memory_to_masks() -> void:
	if _fov == null:
		return
	var tex := _fov.memory_texture()
	if tex == null:
		return
	for mat in _masked_layers:
		mat.set_shader_parameter(&"memory", tex)

## Clip every room to the pixels the player has actually seen.
##
## The fog draws never-seen ground transparent so the starfield reads through it;
## without this, that transparency would also reveal the whole unexplored dungeon
## sitting underneath. Each room's tile layers sample the same per-pixel memory the fog
## uses and discard fragments that have never been lit.
func _apply_seen_mask() -> void:
	var shader := load(SEEN_MASK_SHADER) as Shader
	if shader == null:
		push_warning("MapAssembler: seen-mask shader missing at %s" % SEEN_MASK_SHADER)
		return
	var rect := _blockers.world_rect(Room.TILE_SIZE)
	for child in get_children():
		if not (child is Room):
			continue
		for layer in (child as Room).get_tile_layers():
			if layer == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter(&"field_origin", Vector2(rect.position))
			mat.set_shader_parameter(&"field_size", Vector2(rect.size))
			mat.set_shader_parameter(&"mask_enabled", true)
			layer.material = mat
			_masked_layers.append(mat)

func _process(delta: float) -> void:
	_refresh_visibility(false)
	_update_exploration()
	# The dissolve runs on wall-clock time, so it has to tick every frame — unlike the
	# CPU field of view, which only changes when the player crosses a tile boundary.
	if _fov != null:
		# Entities are spawned over time rather than all at build(), so the sweep for
		# newcomers runs periodically instead of only on a tile change.
		_track_accumulator += delta
		if _track_accumulator >= TRACK_INTERVAL:
			_track_accumulator = 0.0
			_update_entity_visibility()
		_vaporizer.update(delta, _entity_in_sight)

## Advance both fields of view.
##
## The GPU pass follows the player's exact pixel position, so it runs every frame and
## the light pool slides smoothly. The CPU cast is per tile and only answers gameplay
## queries, so it is recomputed just when the player crosses a tile boundary — the
## expensive half stays gated exactly as before.
func _refresh_visibility(force: bool) -> void:
	if _fov == null or _player == null or not is_instance_valid(_player):
		return
	_fov.update_from(_player.global_position)
	# update_from flips the ping-pong, so the room clip materials have to follow it to
	# the newly written target.
	_bind_memory_to_masks()
	if debug_rays:
		_refresh_debug_rays()

	var tile := world_to_tile(_player.global_position)
	if not force and tile == _last_tile:
		return
	_last_tile = tile
	visibility.update_from(tile, sight_radius)
	_update_entity_visibility()

## Bring every entity under the vaporizer's management, so leaving sight fades it out
## instead of hiding it instantly.
##
## Enemies are parented to the current scene by the EnemySpawner autoload rather than
## to this node, so the sweep walks the whole scene rather than just our children.
func _update_entity_visibility() -> void:
	for node in _entities():
		_vaporizer.track(node)

## World-space entities subject to the fog: everything except the rooms, the player,
## the fog layer and the backdrop.
func _entities() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var scene_root: Node = get_tree().current_scene if get_tree() != null else self
	if scene_root == null:
		scene_root = self
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			# Rooms hold only tiles and markers, and are masked by the shader instead.
			if c is Room or c == _fov or c == _starfield or c == _player:
				continue
			stack.append(c)
		if n == scene_root or n is Room or n == _player:
			continue
		var node := n as Node2D
		# Only things that stand somewhere in the world can be tested against a tile;
		# nested sprites are handled by their owner, so only direct bodies count.
		if node != null and (node is CharacterBody2D or node is StaticBody2D or node is Area2D):
			result.append(node)
	return result

## Whether the player can currently see the tile this entity stands on.
func _entity_in_sight(node: Node2D) -> bool:
	return visibility.is_visible_cell(world_to_tile(node.global_position))

## Feed one placed room's wall cells into the field of view, converting the room's
## local tile coordinates into the shared world grid. Neighbouring rooms share a wall
## line and so register the same cells twice; VisibilityMap treats blockers as a set,
## which makes that harmless.
##
## Three consumers of this room at different resolutions. The CPU cast works per tile and
## answers gameplay queries; the packed field's blue channel stores each tile's sprite
## outline so the fog can keep its veil off masonry; and its red channel is filled from
## the room's *authored* occluder polygons, so the fog stops sight exactly where the
## author drew rather than on the sprite silhouette. Occluders arrive in room-local
## pixels, shifted here into the shared world grid — where a neighbour's overlapping
## boundary occluder unions with this one, closing the seam.
func _register_blockers(room: Room, origin: Vector2i) -> void:
	var walls := room.get_walls_layer()
	for cell in room.get_wall_cells():
		var world_cell: Vector2i = origin + cell
		visibility.set_blocker(world_cell)
		if walls != null:
			_blockers.add_from_layer(walls, cell, world_cell)
		else:
			_blockers.add(world_cell)

	var world_offset := Vector2(origin * Room.TILE_SIZE)
	for polygon in room.get_occluder_polygons():
		_blockers.add_polygon(polygon, world_offset)
	# Pillar regions mark where the fog shades directionally (a tall body lit from the
	# front, dark from behind); they never block sight, so they go to the green channel.
	for polygon in room.get_pillar_polygons():
		_blockers.add_pillar_polygon(polygon, world_offset)

## Build one corridor by tiling an authored slice scene along its length: one slice per
## step, each positioned so its far-wall origin lands on that step's far-wall world cell,
## which aligns every floor and wall tile of the slice to the corridor grid. Each slice is
## its own Room, so its occlusion, seen-mask clipping and collision all fall out of the Room
## pipeline with no special casing — the same path the placed rooms take.
func _build_connector(conn: Connector) -> void:
	var scene := CONNECTOR_VERTICAL_SCENE if conn.is_vertical() else CONNECTOR_HORIZONTAL_SCENE
	var step := conn.step()
	# The slice's node origin sits on its far side wall, `width - 1` cells across from the
	# near wall; offsetting the placement by that lands the slice's local cells (which run
	# back toward the near wall) on the corridor's world cells.
	var far := conn.across() * (conn.width - 1)
	for s in range(1, conn.length + 1):
		var slice: Room = scene.instantiate()
		slice.name = "Connector"
		var cell := conn.origin + step * s + far
		slice.position = Vector2(cell * Room.TILE_SIZE)
		add_child(slice)
		_register_blockers(slice, cell)
	_record_minimap_connector(conn)

## Capture a placed room's silhouette for the minimap: its world-tile footprint (for
## deciding which room the player is in), its centre in world pixels (the view target),
## and the outline of its floor traced into world-pixel line segments.
func _record_minimap_room(room: Room, origin: Vector2i) -> void:
	var floor_layer := room.get_floor_layer()
	var cells: Array[Vector2i] = []
	if floor_layer != null:
		for cell in floor_layer.get_used_cells():
			cells.append(origin + cell)
	var local := room.get_bounds()
	var world_bounds := Rect2i(origin + local.position, local.size)
	var center := (Vector2(world_bounds.position) + Vector2(world_bounds.size) * 0.5) * Room.TILE_SIZE
	_mm_rooms.append({
		"bounds": world_bounds,
		"center": center,
		"edges": Minimap.trace_outline(cells),
	})

## Capture a corridor's outline for the minimap and resolve which placed rooms it joins,
## so entering either room reveals the corridor. A connector's mouth (origin) sits in the
## host room's wall and its far opening in the neighbour's; both fall inside the matching
## room's footprint rect.
func _record_minimap_connector(conn: Connector) -> void:
	var step := conn.step()
	var across := conn.across()
	var far := conn.origin + step * (conn.length + 1)
	var probes: Array[Vector2i] = [
		conn.origin, conn.origin + across * (conn.width - 1),
		far, far + across * (conn.width - 1),
	]
	var rooms: Array[int] = []
	for i in _mm_rooms.size():
		var bounds: Rect2i = _mm_rooms[i]["bounds"]
		for p in probes:
			if bounds.has_point(p):
				rooms.append(i)
				break
	_mm_connectors.append({
		"edges": _connector_side_walls(conn),
		"rooms": rooms,
	})

## The corridor's two long side walls only, as world-pixel segments — no end caps. Tracing
## the full floor outline would draw a closed rectangle whose near cap sits on the room's
## doorway and pokes into it; keeping just the runs parallel to the corridor leaves the
## ends open, so it reads as a passage that stops short of the rooms.
func _connector_side_walls(conn: Connector) -> PackedVector2Array:
	var outline := Minimap.trace_outline(conn.floor_cells())
	var vertical := conn.is_vertical()
	var sides := PackedVector2Array()
	var i := 0
	while i + 1 < outline.size():
		var a := outline[i]
		var b := outline[i + 1]
		var seg_horizontal := is_equal_approx(a.y, b.y)
		if seg_horizontal != vertical:
			sides.append(a)
			sides.append(b)
		i += 2
	return sides

## Create the minimap and hand it the assembled feature data. Rebuilt with everything
## else, since build() frees all children.
func _setup_minimap() -> void:
	_minimap = null
	if not minimap_enabled or _player == null:
		return
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.view_size = minimap_size
	_minimap.pixel_size = minimap_pixel_size
	_minimap.world_scale = minimap_scale
	_minimap.margin = minimap_margin
	add_child(_minimap)
	_minimap.setup(_mm_rooms, _mm_connectors, _mm_chests, _player)

## Count each room the first time the player steps into its footprint. Runs off the
## player's tile independently of the fog, so exploration is tracked even with fog off.
## The delegated add_room() is a no-op when no run is active, so this is harmless in the
## editor's standalone map.
func _update_exploration() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var tile := world_to_tile(_player.global_position)
	if tile == _explore_last_tile:
		return
	_explore_last_tile = tile
	for i in _mm_rooms.size():
		if _visited_rooms.has(i):
			continue
		var bounds: Rect2i = _mm_rooms[i]["bounds"]
		if bounds.has_point(tile):
			_visited_rooms[i] = true
			Stats.add_room()

## Place the single dungeon exit at the given room's centre.
func _spawn_exit(room: Room) -> void:
	if exit_scene == null or room == null:
		if exit_scene == null:
			push_warning("MapAssembler: no exit scene assigned")
		return
	var local := room.get_bounds()
	var center_tiles := Vector2(local.position) + Vector2(local.size) * 0.5
	var center := room.global_position + center_tiles * Room.TILE_SIZE
	var exit := exit_scene.instantiate()
	add_child(exit)
	exit.global_position = center

## World tile the given point falls in, for driving the field of view from a node's
## position.
static func world_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / Room.TILE_SIZE), floori(world_position.y / Room.TILE_SIZE))

## Recompute visibility around a world position. Called as the player moves.
func update_visibility(world_position: Vector2) -> void:
	visibility.update_from(world_to_tile(world_position), sight_radius)

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
	_player = null
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
	# Remembered so the fog can follow the player without searching the tree each frame.
	_player = player as Node2D

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
		_mm_chests.append({
			"pos": point.global_position,
			"tile": world_to_tile(point.global_position),
			"revealed": false,
		})
