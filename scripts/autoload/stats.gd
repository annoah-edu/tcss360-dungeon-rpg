extends Node

## Central statistics registry and run lifecycle. Autoloaded as `Stats`.
##
## Three jobs:
##   1. Hold the *pending run config* (seed + whether stats count) that the start
##      screen sets before loading the dungeon, so MapAssembler can read it.
##   2. Accumulate *lifetime totals* (persisted to user://) and *this-run deltas*,
##      exposing the deltas to the run-summary screen as "(+num)" changes.
##   3. Own all the human-readable formatting — the 1K/1M/1G number abbreviation,
##      the feet-then-miles distance scale, and the silly Duck-distance nonsense.
##
## Gameplay code just calls the add_* helpers; it never touches persistence or
## formatting, so hooking a new stat is a one-liner at the call site plus a key here.

const SAVE_PATH := "user://stats.cfg"
const SAVE_SECTION := "lifetime"

## World is drawn at 16px tiles; we treat one tile as 5 feet so distances read like
## a tabletop dungeon rather than as raw pixels.
const FEET_PER_TILE := 5.0
const FEET_PER_MILE := 5280.0

## Every tracked statistic in one place. Adding a key here and a matching add_* call
## is all a new stat needs; the start screen and run summary iterate this list, so
## they pick up newcomers automatically.
##   key   : storage key, also the ConfigFile key
##   label : shown to the player
##   kind  : how format_value renders it — "distance" (feet->miles), "time"
##           (h/m/s) or "count" (1K/1M/1G)
const STAT_DEFS := [
	{"key": "distance_feet", "label": "Distance traveled", "kind": "distance"},
	{"key": "rooms_explored", "label": "Rooms explored", "kind": "count"},
	{"key": "chests_opened", "label": "Chests opened", "kind": "count"},
	{"key": "enemies_killed", "label": "Enemies killed", "kind": "count"},
	{"key": "damage_done", "label": "Damage done", "kind": "count"},
	{"key": "time_seconds", "label": "Time in game", "kind": "time"},
]

## Shorthand units the Duck-distance nonsense cycles through (m / km / mi / ft / in).
const DUCK_UNITS := ["m", "km", "mi", "ft", "in"]

## Pending run config, written by the start screen and consumed by MapAssembler on load.
## `run_requested` distinguishes a run launched from the menu (track stats) from the
## map scene being run standalone in the editor (leave totals untouched).
var run_requested: bool = false
var pending_seed: int = 0
var pending_randomize: bool = true
## When false (a hand-entered seed) the run's numbers are shown but never folded into
## the lifetime totals — deterministic runs shouldn't inflate your records.
var pending_counts: bool = true

## Lifetime totals, loaded from disk. Floats so distance/damage/time accumulate smoothly.
var _totals: Dictionary = {}
## This run's contribution, reset by begin_run(). Same keys as _totals.
var _run: Dictionary = {}
## Snapshot of the just-finished run's deltas, read by the run-summary screen.
var last_run: Dictionary = {}
var last_run_counted: bool = false
## Whether the just-finished run ended in death (vs. walking out the exit), so the
## summary can title itself accordingly.
var last_run_died: bool = false
## Flavor value for the summary's "Distance from The Duck" line: random(0.01..1.0) *
## run_seconds, shown as "(-num m)" the Duck crept closer. Regenerated each end_run().
var last_run_drift: float = 0.0

## Whether a run is live. Gates time accrual and the add_* helpers so stray gameplay
## events between runs (or in the editor's standalone map) don't corrupt totals.
var _running: bool = false

func _ready() -> void:
	_load()

func _process(delta: float) -> void:
	if _running:
		_run["time_seconds"] += delta

# --- Run lifecycle -----------------------------------------------------------

## Stage the next run's seed. Called by the start screen before it loads the dungeon.
func configure_run(seed_value: int, randomize: bool) -> void:
	run_requested = true
	pending_randomize = randomize
	pending_seed = seed_value
	# A randomized run always counts; a hand-picked seed is reproducible, so it doesn't.
	pending_counts = randomize

## Open a run. Zeroes the per-run accumulators and starts the clock.
func begin_run() -> void:
	_run = _blank_totals()
	last_run = {}
	_running = true

## Close a run: snapshot the deltas, roll them into the lifetime totals when the run
## counts, compute the drift flavor value, and persist. `died` records how the run ended
## (death vs. reaching the exit) for the summary. Returns the delta snapshot.
func end_run(died: bool = false) -> Dictionary:
	if not _running:
		return last_run
	_running = false
	last_run = _run.duplicate()
	last_run_counted = pending_counts
	last_run_died = died
	last_run_drift = randf_range(0.01, 1.0) * _run["time_seconds"]
	if pending_counts:
		for key in _run:
			_totals[key] = _totals.get(key, 0.0) + _run[key]
		_save()
	return last_run

# --- Gameplay hooks ----------------------------------------------------------

## Accumulate travel from a world-pixel step (the player's per-frame displacement).
func add_distance_pixels(pixels: float) -> void:
	if not _running:
		return
	_run["distance_feet"] += (pixels / Room.TILE_SIZE) * FEET_PER_TILE

func add_room() -> void:
	if _running:
		_run["rooms_explored"] += 1

func add_chest() -> void:
	if _running:
		_run["chests_opened"] += 1

func add_kill() -> void:
	if _running:
		_run["enemies_killed"] += 1

func add_damage(amount: float) -> void:
	if _running:
		_run["damage_done"] += amount

# --- Queries -----------------------------------------------------------------

func lifetime(key: String) -> float:
	return _totals.get(key, 0.0)

func last_run_value(key: String) -> float:
	return last_run.get(key, 0.0)

## Wipe every lifetime total and persist. Backing the Settings > Clear statistics action.
func clear() -> void:
	_totals = _blank_totals()
	_save()

# --- Formatting --------------------------------------------------------------

## Render a value the way its stat kind wants: distance in feet/miles, time as
## h/m/s, everything else abbreviated 1K/1M/1G.
static func format_value(value: float, kind: String) -> String:
	match kind:
		"distance":
			return format_distance(value)
		"time":
			return format_time(value)
		_:
			return format_count(value)

## Abbreviate a magnitude once it crosses 1000: 1K, then 1M, then 1G. One decimal,
## trailing ".0" trimmed, so 1500 -> "1.5K" and 2000 -> "2K".
static func format_count(value: float) -> String:
	var n := absf(value)
	var sign_str := "-" if value < 0 else ""
	if n >= 1_000_000_000.0:
		return sign_str + _trim(n / 1_000_000_000.0) + "G"
	if n >= 1_000_000.0:
		return sign_str + _trim(n / 1_000_000.0) + "M"
	if n >= 1_000.0:
		return sign_str + _trim(n / 1_000.0) + "K"
	return sign_str + str(int(round(n)))

## Feet until a mile, then miles. Feet still get the K/M/G treatment so a long crawl
## reads "1.2K ft" rather than a wall of digits.
static func format_distance(feet: float) -> String:
	if feet >= FEET_PER_MILE:
		return _trim(feet / FEET_PER_MILE) + " mi"
	return format_count(feet) + " ft"

static func format_time(seconds: float) -> String:
	var total := int(round(seconds))
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%dh %dm %ds" % [h, m, s]
	if m > 0:
		return "%dm %ds" % [m, s]
	return "%ds" % s

## Signed "(+num)" / "(-num)" delta string for the run summary, formatted per kind.
static func format_delta(value: float, kind: String) -> String:
	var body := format_value(absf(value), kind)
	var sign_str := "+" if value >= 0 else "-"
	return "(%s%s)" % [sign_str, body]

## Trim a one-decimal float: 1.0 -> "1", 1.5 -> "1.5".
static func _trim(value: float) -> String:
	var s := "%.1f" % value
	if s.ends_with(".0"):
		return s.substr(0, s.length() - 2)
	return s

# --- Persistence -------------------------------------------------------------

func _blank_totals() -> Dictionary:
	var d: Dictionary = {}
	for def in STAT_DEFS:
		d[def["key"]] = 0.0
	return d

func _load() -> void:
	_totals = _blank_totals()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for def in STAT_DEFS:
		_totals[def["key"]] = float(cfg.get_value(SAVE_SECTION, def["key"], 0.0))

func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _totals:
		cfg.set_value(SAVE_SECTION, key, _totals[key])
	cfg.save(SAVE_PATH)
