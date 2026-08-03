class_name BlockerField
extends RefCounted

## The dungeon's sight-blocking geometry packed into a texture the field-of-view shader
## marches through — at **art-pixel** resolution, not one pixel per tile.
##
## The texture answers three questions per pixel, one per channel:
##   red   — does this pixel stop sight? The authored occluder outline.
##   green — is this pixel a pillar face? The authored directional-shading region.
##   blue  — is this pixel drawn masonry? The wall sprite's silhouette.
##
## Occlusion (red) and masonry (blue) are deliberately different data. What stops sight is
## authored by hand as occluder polygons (see add_polygon); what is *drawn* is the sprite,
## read straight from the tiles (see add_from_layer). Separating them is what removes the
## old per-tile silhouette trimming: an author draws the sight barrier exactly where it
## belongs — through corners, flush across shared walls — so the seam and corner leaks
## that trimming produced where two rooms met simply cannot happen. Blue stays the sprite
## so the shader can still keep the veil off masonry it did not author.
##
## Green marks *pillar* regions (see add_pillar_polygon). A free-standing pillar's tall
## body is drawn north of its base, so a southern viewer's sightline to it is blocked by
## the pillar's own base — geometrically it is behind the occluder even though it is the
## face the player looks at. The fog shades a green region directionally: it inherits the
## sightline to the region's near (south) foot, so the pillar lights from the front and
## darkens from behind rather than being either self-shadowed or blanket-exempt.
##
## Rebuilt only when the dungeon is rebuilt; the player moving changes nothing here.

## World tile the texture's (0,0) corresponds to.
var origin: Vector2i = Vector2i.ZERO
## Texture dimensions in tiles.
var size: Vector2i = Vector2i.ZERO
## World pixels per tile, so callers can map between the two.
var tile_size: int = 16
var texture: ImageTexture

## cell -> masonry silhouette (blue), a 16x16 bitmask stored as an Array[bool] in
## row-major order. Populated from the wall sprites, purely for the drawn-masonry mask.
var _cells: Dictionary = {}
## World-pixel occluders (red), a Dictionary used as a set (Vector2i -> true). Filled by
## rasterizing authored polygons, so overlapping outlines from neighbouring rooms union
## for free — the whole reason seams between rooms stop leaking.
var _occluders: Dictionary = {}
## World-pixel pillar regions (green), a Dictionary used as a set (Vector2i -> true).
## Filled by rasterizing authored pillar polygons; marks where the fog shades directionally.
var _pillars: Dictionary = {}
## Cached silhouettes keyed by "source:atlas_x,atlas_y", so each distinct tile is only
## scanned out of its atlas once.
var _silhouettes: Dictionary = {}

## Record a wall cell as fully solid, in both masonry and occlusion. Kept for tests and
## for callers with no authored polygons: a solid cell stops sight across its whole
## footprint and is drawn as masonry across it too, so it stays self-consistent.
func add(cell: Vector2i) -> void:
	_cells[cell] = _solid_mask()
	var base := cell * tile_size
	for y in tile_size:
		for x in tile_size:
			_occluders[Vector2i(base.x + x, base.y + y)] = true

func add_all(cells: Array[Vector2i]) -> void:
	for c in cells:
		add(c)

## Record a wall cell's *drawn* silhouette (blue channel) from the tile actually placed
## there. This never touches occlusion — sight-blocking comes from authored polygons — it
## only tells the shader which pixels are masonry so the veil can skip them.
##
## `layer` supplies the tile, `cell` is its coordinate in that layer, and `world_cell` is
## where it lands in the shared world grid. Rooms share wall lines, so a cell may already
## carry a silhouette; the two are unioned so neither room's masonry is lost.
func add_from_layer(layer: TileMapLayer, cell: Vector2i, world_cell: Vector2i) -> void:
	var mask := _mask_for(layer, cell)
	if mask.is_empty():
		return
	var existing: Array = _cells.get(world_cell, [])
	if existing.is_empty():
		_cells[world_cell] = mask
	else:
		var merged: Array[bool] = []
		merged.resize(tile_size * tile_size)
		for i in merged.size():
			merged[i] = bool(existing[i]) or bool(mask[i])
		_cells[world_cell] = merged

## Rasterize an authored occluder outline into the red channel.
##
## `points` are polygon vertices in some node's local pixel space; `world_offset` shifts
## them into the shared world grid (a room's origin in world pixels). Filling into a
## shared pixel set is what makes connecting rooms robust: two rooms whose boundary
## occluders overlap by even a pixel union into one continuous barrier, so there is no
## edge-to-edge alignment to get wrong and no gap for a ray to thread.
##
## Even-odd scanline fill, sampling pixel centres (x+0.5), which is exactly where the fog
## shader samples the texture — so a pixel occludes here iff the shader will read it as
## solid.
func add_polygon(points: PackedVector2Array, world_offset: Vector2 = Vector2.ZERO) -> void:
	_fill_polygon(points, world_offset, _occluders)

## Rasterize an authored pillar region into the green channel. Same fill as add_polygon;
## marks the pixels the fog shades directionally (see the class docs). A pillar polygon
## should cover the whole sprite, base included, so the shader's downward march exits at
## the floor just south of the base — the near foot whose visibility the face inherits.
func add_pillar_polygon(points: PackedVector2Array, world_offset: Vector2 = Vector2.ZERO) -> void:
	_fill_polygon(points, world_offset, _pillars)

func clear() -> void:
	_cells.clear()
	_occluders.clear()
	_pillars.clear()
	_silhouettes.clear()
	texture = null
	origin = Vector2i.ZERO
	size = Vector2i.ZERO

## Rasterize `points` (plus `world_offset`) into `target`, a Vector2i->true pixel set.
func _fill_polygon(points: PackedVector2Array, world_offset: Vector2, target: Dictionary) -> void:
	if points.size() < 3:
		return
	var world: PackedVector2Array = PackedVector2Array()
	world.resize(points.size())
	var min_y := INF
	var max_y := -INF
	for i in points.size():
		var p := points[i] + world_offset
		world[i] = p
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)

	var n := world.size()
	var row0 := floori(min_y)
	var row1 := ceili(max_y)
	var xs: Array[float] = []
	for py in range(row0, row1):
		var yc := float(py) + 0.5
		xs.clear()
		for i in n:
			var a := world[i]
			var b := world[(i + 1) % n]
			# Half-open edge test (one endpoint inclusive) so a vertex exactly on the
			# scanline is counted once, not zero or twice.
			if (a.y <= yc and b.y > yc) or (b.y <= yc and a.y > yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			# Pixel px is inside when its centre px+0.5 falls in [xs[k], xs[k+1]].
			var px_start := ceili(xs[k] - 0.5)
			var px_end := floori(xs[k + 1] - 0.5)
			for px in range(px_start, px_end + 1):
				target[Vector2i(px, py)] = true
			k += 2

func wall_count() -> int:
	return _cells.size()

func has_wall(cell: Vector2i) -> bool:
	return _cells.has(cell)

## Does the given pixel occlude? `cell` and `local` (0..tile_size-1) together name a world
## pixel; reports whether an authored occluder covers it, matching what the texture holds.
func is_solid_at(cell: Vector2i, local: Vector2i) -> bool:
	if local.x < 0 or local.y < 0 or local.x >= tile_size or local.y >= tile_size:
		return false
	return _occluders.has(cell * tile_size + local)

## Does the given pixel fall in an authored pillar region (the green channel)?
func is_pillar_at(cell: Vector2i, local: Vector2i) -> bool:
	if local.x < 0 or local.y < 0 or local.x >= tile_size or local.y >= tile_size:
		return false
	return _pillars.has(cell * tile_size + local)

## Build the texture from everything registered so far. Returns false when there is
## nothing to pack, leaving `texture` null so callers can skip the shader entirely.
##
## `margin` pads the grid in tiles. The shader treats out-of-bounds samples as open
## floor, so without a border a wall on the very edge would let sight leak around it.
func commit(margin: int = 2) -> bool:
	if _cells.is_empty() and _occluders.is_empty():
		texture = null
		size = Vector2i.ZERO
		return false

	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483648, -2147483648)
	for c: Vector2i in _cells:
		min_cell.x = mini(min_cell.x, c.x)
		min_cell.y = mini(min_cell.y, c.y)
		max_cell.x = maxi(max_cell.x, c.x)
		max_cell.y = maxi(max_cell.y, c.y)
	# Occluders and pillar regions can sit anywhere in world pixels, including a hair past
	# the wall cells they were authored against, so fold their cells into the bounds too.
	for set: Dictionary in [_occluders, _pillars]:
		for px: Vector2i in set:
			var c := _pixel_to_cell(px)
			min_cell.x = mini(min_cell.x, c.x)
			min_cell.y = mini(min_cell.y, c.y)
			max_cell.x = maxi(max_cell.x, c.x)
			max_cell.y = maxi(max_cell.y, c.y)
	min_cell -= Vector2i.ONE * margin
	max_cell += Vector2i.ONE * margin

	origin = min_cell
	size = max_cell - min_cell + Vector2i.ONE

	# Blue marks drawn masonry; red (occluders) and green (pillar regions) are stamped in
	# later passes from their pixel sets. Blue is the receiver mask the fog uses to keep the
	# veil off masonry, and must stay the sprite; red and green are authored, so they differ
	# from it wherever the author drew the barrier or a pillar away from the sprite outline.
	var image := Image.create(size.x * tile_size, size.y * tile_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	for cell: Vector2i in _cells:
		var art: Array = _cells[cell]
		var base: Vector2i = (cell - origin) * tile_size
		for y in tile_size:
			for x in tile_size:
				var i: int = y * tile_size + x
				image.set_pixel(base.x + x, base.y + y, Color(
					0.0,
					0.0,
					1.0 if bool(art[i]) else 0.0,
					1.0))

	var origin_px := origin * tile_size
	var field_w := size.x * tile_size
	var field_h := size.y * tile_size
	for px: Vector2i in _occluders:
		_set_channel(image, px - origin_px, field_w, field_h, 0)
	for px: Vector2i in _pillars:
		_set_channel(image, px - origin_px, field_w, field_h, 1)

	texture = ImageTexture.create_from_image(image)
	return true

## Set one colour channel (0 = red, 1 = green) to 1.0 at image pixel `at`, if in bounds.
func _set_channel(image: Image, at: Vector2i, field_w: int, field_h: int, channel: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= field_w or at.y >= field_h:
		return
	var c := image.get_pixel(at.x, at.y)
	c[channel] = 1.0
	image.set_pixel(at.x, at.y, c)

## World-pixel rect the grid covers, for sizing the memory field to match.
func world_rect(p_tile_size: int) -> Rect2i:
	return Rect2i(origin * p_tile_size, size * p_tile_size)

# --- Silhouettes -----------------------------------------------------------------

func _pixel_to_cell(px: Vector2i) -> Vector2i:
	return Vector2i(floori(px.x / float(tile_size)), floori(px.y / float(tile_size)))

func _solid_mask() -> Array[bool]:
	var mask: Array[bool] = []
	mask.resize(tile_size * tile_size)
	mask.fill(true)
	return mask

## Opaque pixels of the tile at `cell`, in cell-local coordinates.
##
## Tall wall art is 16x32 drawn with its lower 16 rows filling the cell and the upper
## 16 overhanging into the cell above, so only the lower half is read here — the
## overhang is the wall's visible face, not something standing in that cell.
func _mask_for(layer: TileMapLayer, cell: Vector2i) -> Array[bool]:
	var ts := layer.tile_set
	if ts == null:
		return []
	var sid := layer.get_cell_source_id(cell)
	if sid < 0:
		return []
	var coords := layer.get_cell_atlas_coords(cell)
	var key := "%d:%d,%d" % [sid, coords.x, coords.y]
	if _silhouettes.has(key):
		return _silhouettes[key]

	var atlas := ts.get_source(sid) as TileSetAtlasSource
	if atlas == null or atlas.texture == null:
		return []
	var region := atlas.texture_region_size
	var image := atlas.texture.get_image()
	if image == null:
		return []

	var mask: Array[bool] = []
	mask.resize(tile_size * tile_size)
	mask.fill(false)
	var ox: int = coords.x * region.x
	var oy: int = coords.y * region.y
	# Rows of the sprite that land inside the cell.
	var cell_top: int = maxi(region.y - tile_size, 0)
	for y in tile_size:
		var sy: int = oy + cell_top + y
		if sy >= image.get_height():
			continue
		for x in tile_size:
			var sx: int = ox + x
			if sx >= image.get_width():
				continue
			if image.get_pixel(sx, sy).a > 0.5:
				mask[y * tile_size + x] = true
	_silhouettes[key] = mask
	return mask
