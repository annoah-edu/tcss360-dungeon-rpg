# tcss360-dungeon-rpg

Project repo for TCSS 360. A top-down 2D dungeon RPG built in **Godot 4.6**.

## Procedural room/map system

The map is assembled at runtime from reusable **room** scenes that carry
**attachment points (doors)** and **spawn points**. A seeded generator connects
rooms door-to-door into an organic dungeon; gameplay systems that don't exist yet
(enemies, loot, NPCs) plug in later through the spawn layer without touching the
rooms.

### Architecture

Pure logic is separated from scene work so the interesting parts are unit-testable
without a running scene tree:

```
RoomTemplate (RefCounted) ── id, bounds:Rect2i, doors[], tags, weight
       ▲ Room.to_template() extracts this straight off each room scene
Room (scene) ────────────── self-describing: geometry + doors + tags + weight
       │  (the assembler scans scenes/rooms/ — no separate catalog resource)
MapGenerator (RefCounted) ── PURE: (templates, seed) -> Array[Placement]
       │  door matching · alignment math · overlap rejection · seeded RNG
       ▼
MapAssembler (map.tscn) ──── instantiates rooms at placement origins, seals
                             unused doors, registers spawns, drops in the player
```

Rooms are **passive**: they never decide where they go. The assembler positions a
room, then calls `Room.setup(connected)` so the room can seal doors that weren't
connected and register its spawn points.

**Doorway strategy — author-open, engine-seal:** room scenes are drawn with each
doorway already opened (floor laid + wall gap), so the author owns how a connection
looks — including any tileset quirks like tall-wall overhang. The engine only touches
tiles on doors that end up *unconnected*: it seals them by stamping wall across the
gap and floor beneath it, both sampled from the room's own tiles so the patch blends
in. Connected doors are left exactly as authored.

### Layout

```
scenes/
  player/player.tscn          extracted player
  rooms/room_*.tscn           room templates (start, hall, junction)
  map/map.tscn                dungeon root (MapAssembler) — the main scene
scripts/
  map/                        door, spawn_point, room, room_door, room_template,
                              placement, map_generator, map_assembler
  autoload/spawn_director.gd  SpawnDirector autoload
resources/
  tilesets/dungeon_tileset.tres   shared TileSet (extracted from the old main.tscn)
tools/author_rooms.gd         regenerates the room_*.tscn block-outs
tests/map/                    GdUnit4 unit tests
```

Everything is on a **16×16 tile grid**. Legacy `main.tscn` is kept for reference
but is no longer the entry scene.

### Adding a room

1. Create a scene in `scenes/rooms/` whose root uses `room.gd` (`class_name Room`)
   with `Floor` + `Walls` `TileMapLayer`s (shared tileset), a `Doors` node holding
   `Door`s, and a `SpawnPoints` node holding `SpawnPoint`s. Draw each doorway *already
   opened* — a gap in the `Walls` layer with `Floor` laid across it — because
   connected doors are shown exactly as authored; the engine only seals the ones that
   end up unconnected.
2. Place each `Door` marker on its gap cell and set its `direction`.
3. On the root `Room` node set `tags` (e.g. `start`, `combat`, `treasure`) and a
   selection `weight`. The assembler scans `scenes/rooms/` and auto-discovers any
   `Room` with `in_catalog` enabled (the default) — no catalog resource to maintain.
   (`start`-tagged rooms are placed once, at the origin, and never reused for growth;
   uncheck `in_catalog` to keep a draft scene out of generation.)

Or edit `tools/author_rooms.gd` and re-run it (see below) to regenerate block-outs.

### Door states (forward-compatible)

A `Door` holds an extensible **set of state tags** (`states: Array[StringName]`)
queried with `door.has_state(&"boss")`. A `DoorStateLibrary` resolves the
highest-**priority** active state into a presentation, flippable at runtime.

Presentation is **hybrid** — each state renders one of three ways
(`DoorStateStyle.presentation`):
- `OPEN` — leaves the authored tiles untouched (a connected doorway the author
  already drew as a passable gap).
- `WALL_TILE` — overrides the tiles to seal an unconnected doorway: stamps wall
  across the gap plus floor beneath, both sampled from the room's own tiles (with the
  style's `tile_source_id`/`atlas` as fallback), so blocking comes from the tile's own
  collision and the patch blends in (used for `sealed`).
- `ENTITY` — spawns a node child (a real `scene`, or a flat `color` placeholder)
  plus a collision barrier if `blocks`. For interactive doors a static tile can't
  be: `boss`, `locked`, animated opens.

Built-in states (see `DoorStateLibrary.create_default`): `open`/`sealed` are
tile-based; `closed`/`locked`/`boss` are entities. Adding a state is **data only**.
`Room.setup()` sets `open` on connected doors and `sealed` on the rest.

Two axes stay separate on purpose: **which states affect connection** must ride in
the pure `RoomDoor` mirror (so the generator can match on them); everything else is
look/gameplay and lives only on the node. Note a connection has two Door nodes (one
per room) — syncing a *locked* connecting door across both sides is a future step.

### Spawn points (forward-compatible)

`SpawnPoint`s are declarative markers with a `category`
(`PLAYER_START/ENEMY/NPC/LOOT/TREASURE/BOSS/PROP`), `tags`, `spawn_chance`, and
`max_count`. Rooms register them with the `SpawnDirector` autoload. Future systems
call `SpawnDirector.get_points(category)` and instantiate real content — no room
changes needed. For now `SpawnDirector.populate()` just logs coverage.

## Running

Requires Godot 4.6. Open the project and press F5, or:

```sh
godot --path . scenes/map/map.tscn
```

The seed is fixed on `map.tscn` (`map_seed`, `randomize_seed = false`) for
reproducible layouts; flip `randomize_seed` on for a fresh dungeon each run.

## Tests

Unit tests use [GdUnit4](https://github.com/MikeSchulze/gdUnit4) (`addons/gdUnit4`)
and cover the generator's pure logic (door compatibility, alignment, overlap,
seed determinism, start-room uniqueness). Run headless:

```sh
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/map
```

## Regenerating room block-outs

```sh
godot --headless --path . -s res://tools/author_rooms.gd
```
