class_name BlockerField
extends RefCounted

## The dungeon's sight-blocking geometry packed into a texture the field-of-view shader
## marches through — at **art-pixel** resolution, not one pixel per tile.
##
## Per-tile would be simpler, but the wall art does not fill its cell. Measured across
## the tiles these rooms actually place:
##
##     x 5..10  y 0..15   a 6px pillar in a 16px cell   (east/west walls)
##     x 5..15  y 0..15   flush to one side             (corners)
##     x 0..15  y 7..15   only the lower half
##     x 0..15  y 0..15   the one tile that fills its cell
##
## Treating every wall cell as fully solid therefore blocks sight through space the
## player can plainly see past, and puts shadow edges a tile away from the masonry that
## is supposed to cast them. Storing the real silhouette costs 256x the pixels — still
## only ~360 KB for this dungeon — and makes occlusion match what is drawn.
##
## Rebuilt only when the dungeon is rebuilt; the player moving changes nothing here.

## World tile the texture's (0,0) corresponds to.
var origin: Vector2i = Vector2i.ZERO
## Texture dimensions in tiles.
var size: Vector2i = Vector2i.ZERO
## World pixels per tile, so callers can map between the two.
var tile_size: int = 16
## Pixels peeled off a wall's faces that front onto open floor, so sight stops at the
## far side of the masonry rather than the near side. 0 occludes the full silhouette.
var inner_skin: int = 4
var texture: ImageTexture

## cell -> silhouette, a 16x16 bitmask stored as an Array[bool] in row-major order.
var _cells: Dictionary = {}
## Cached silhouettes keyed by "source:atlas_x,atlas_y", so each distinct tile is only
## scanned out of its atlas once.
var _silhouettes: Dictionary = {}

## Record a wall cell as fully solid. Kept for tests and for callers with no tile data.
func add(cell: Vector2i) -> void:
	_cells[cell] = _solid_mask()

func add_all(cells: Array[Vector2i]) -> void:
	for c in cells:
		add(c)

## Record a wall cell using the actual silhouette of the tile drawn there.
##
## `layer` supplies the tile, `cell` is its coordinate in that layer, and `world_cell`
## is where it lands in the shared world grid. Falls back to a solid cell when the tile
## cannot be inspected, which is the safe direction: over-blocking looks wrong but
## under-blocking lets the player see through walls.
func add_from_layer(layer: TileMapLayer, cell: Vector2i, world_cell: Vector2i) -> void:
	var mask := _mask_for(layer, cell)
	if mask.is_empty():
		add(world_cell)
		return
	# Rooms share wall lines, so a cell may already carry a silhouette; union them so
	# neither room's geometry is lost.
	var existing: Array = _cells.get(world_cell, [])
	if existing.is_empty():
		_cells[world_cell] = mask
	else:
		var merged: Array[bool] = []
		merged.resize(tile_size * tile_size)
		for i in merged.size():
			merged[i] = bool(existing[i]) or bool(mask[i])
		_cells[world_cell] = merged

func clear() -> void:
	_cells.clear()
	_silhouettes.clear()
	texture = null
	origin = Vector2i.ZERO
	size = Vector2i.ZERO

func wall_count() -> int:
	return _cells.size()

func has_wall(cell: Vector2i) -> bool:
	return _cells.has(cell)

## Does the given pixel inside a wall cell occlude? `local` is 0..tile_size-1. Reports
## the trimmed silhouette, matching what the texture actually holds.
func is_solid_at(cell: Vector2i, local: Vector2i) -> bool:
	if not _cells.has(cell):
		return false
	if local.x < 0 or local.y < 0 or local.x >= tile_size or local.y >= tile_size:
		return false
	var mask: Array = _trimmed(cell)
	return bool(mask[local.y * tile_size + local.x])

## Build the texture from everything registered so far. Returns false when there is
## nothing to pack, leaving `texture` null so callers can skip the shader entirely.
##
## `margin` pads the grid in tiles. The shader treats out-of-bounds samples as open
## floor, so without a border a wall on the very edge would let sight leak around it.
func commit(margin: int = 2) -> bool:
	if _cells.is_empty():
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
	min_cell -= Vector2i.ONE * margin
	max_cell += Vector2i.ONE * margin

	origin = min_cell
	size = max_cell - min_cell + Vector2i.ONE

	# Three channels, because the fog asks three different questions:
	#   red   — does this pixel stop sight? The trimmed silhouette.
	#   green — is this pixel inside a wall cell? Cell occupancy.
	#   blue  — is this pixel drawn masonry? The untrimmed sprite.
	#
	# Red and blue differ by the inner skin: those pixels no longer occlude but are
	# still painted wall. Blue and green differ by everything the sprite leaves empty —
	# 30% of the occupied cells, measured — and using green as the no-shadow mask is
	# what left a bright halo around every wall, since empty pixels inside a cell can
	# never darken. Blue is the correct receiver mask.
	var image := Image.create(size.x * tile_size, size.y * tile_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	for cell: Vector2i in _cells:
		var trimmed: Array = _trimmed(cell)
		var art: Array = _cells[cell]
		var base: Vector2i = (cell - origin) * tile_size
		for y in tile_size:
			for x in tile_size:
				var i: int = y * tile_size + x
				image.set_pixel(base.x + x, base.y + y, Color(
					1.0 if bool(trimmed[i]) else 0.0,
					1.0,
					1.0 if bool(art[i]) else 0.0,
					1.0))
	texture = ImageTexture.create_from_image(image)
	return true

## A wall's silhouette with its inward-facing skin removed.
##
## Sight should stop at the far side of a wall, not the near side. Occluding the whole
## silhouette makes a wall read as thicker than it looks: standing against it, the face
## you can plainly see is already casting shadow, so the shadow starts a wall-thickness
## too early.
##
## The rule is static rather than per-viewer: a side of the cell is peeled back by
## `inner_skin` pixels when the neighbouring cell that way is *not* a wall, i.e. it is
## open floor someone could stand on. What survives is the core of the masonry, which
## is the part that genuinely sits between two spaces. Static keeps it stable — the
## occluder never changes as the player moves, so shadows do not crawl.
func _trimmed(cell: Vector2i) -> Array:
	var mask: Array = _cells[cell]
	if inner_skin <= 0:
		return mask

	var open_left := not _cells.has(cell + Vector2i(-1, 0))
	var open_right := not _cells.has(cell + Vector2i(1, 0))
	var open_up := not _cells.has(cell + Vector2i(0, -1))
	var open_down := not _cells.has(cell + Vector2i(0, 1))
	if not (open_left or open_right or open_up or open_down):
		return mask

	var out: Array[bool] = []
	out.resize(tile_size * tile_size)
	# Cap so opposing faces can never meet: peeling `skin` from both sides of a cell
	# must leave a core, or an isolated wall would stop occluding altogether.
	var skin: int = inner_skin
	if open_left and open_right:
		skin = mini(skin, (tile_size - 1) / 2)
	if open_up and open_down:
		skin = mini(skin, (tile_size - 1) / 2)
	skin = clampi(skin, 0, tile_size - 1)
	for y in tile_size:
		for x in tile_size:
			var solid: bool = bool(mask[y * tile_size + x])
			if solid:
				# Peel only the faces that front onto open space.
				if (open_left and x < skin) \
					or (open_right and x >= tile_size - skin) \
					or (open_up and y < skin) \
					or (open_down and y >= tile_size - skin):
					solid = false
			out[y * tile_size + x] = solid
	return out

## World-pixel rect the grid covers, for sizing the memory field to match.
func world_rect(p_tile_size: int) -> Rect2i:
	return Rect2i(origin * p_tile_size, size * p_tile_size)

# --- Silhouettes -----------------------------------------------------------------

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
