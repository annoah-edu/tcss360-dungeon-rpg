class_name DoorStateStyle
extends Resource

## How one door state presents itself. The hybrid split:
##   OPEN      – clear the door's cells on the Walls layer (a passable gap).
##   WALL_TILE – stamp a wall tile into those cells; blocking comes from the
##               tile's own collision, and it blends with the surrounding walls.
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
@export var tile_source_id: int = 1
@export var tile_atlas_coords: Vector2i = Vector2i(2, 0)

@export_group("ENTITY")
@export var color: Color = Color(0.3, 0.24, 0.2)
@export var scene: PackedScene
