class_name DoorStateStyle
extends Resource

## How one door state presents itself. The hybrid split:
##   OPEN      – clear the door's cells on the Walls layer (a passable gap).
##   WALL_TILE – stamp a wall tile into those cells (chosen by the door's orientation,
##               horizontal vs vertical wall); blocking comes from the tile's own
##               collision. The floor beneath is patched too — see the Floor fields.
##   ENTITY    – spawn a node child (a real `scene`, or a flat `color` placeholder)
##               plus a collision barrier if `blocks`. For interactive doors that a
##               static tile can't be — boss gates, locked doors, animated opens.
enum Presentation { OPEN, WALL_TILE, ENTITY }

@export var presentation: Presentation = Presentation.ENTITY
## Highest priority among a door's active states wins.
@export var priority: int = 0
## Whether this state blocks movement. For WALL_TILE the tile's own collision does the
## blocking, so this flag is only informational; for ENTITY it decides whether a
## collision barrier is built.
@export var blocks: bool = true

@export_group("WALL_TILE")
## Wall tile used when sealing a door on a horizontal wall — a NORTH or SOUTH
## door, whose wall runs east–west. Source id + atlas coords into the room's tileset.
@export var wall_h_source_id: int = 1
@export var wall_h_atlas_coords: Vector2i = Vector2i(2, 3)
## Wall tile used when sealing a door on a vertical wall — an EAST or WEST door,
## whose wall runs north–south. Point this at a different tile than the horizontal one
## to use direction-specific wall art; leave the two equal for a uniform wall.
@export var wall_v_source_id: int = 1
@export var wall_v_atlas_coords: Vector2i = Vector2i(0, 1)
@export_subgroup("Floor")
## Floor tile laid under a sealed EAST or WEST door, where the floor beside the wall
## stays visible (WEST reuses this tile flipped horizontally, mirroring an east wall).
## NORTH doors erase their floor (the tall wall hides it); SOUTH doors keep the authored
## floor but clear the tile just south of the doorway — so this tile is E/W only.
@export var floor_source_id: int = 0
@export var floor_atlas_coords: Vector2i = Vector2i(5, 5)

@export_group("ENTITY")
@export var color: Color = Color(0.3, 0.24, 0.2)
@export var scene: PackedScene
