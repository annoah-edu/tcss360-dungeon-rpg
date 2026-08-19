extends GutTest

## Covers the save-system pieces that are awkward to exercise by playing: the SaveManager
## file round-trip / version gate, Stats run-state capture-restore, and VisibilityMap's
## new mark_seen(). The real user:// save is backed up and restored so running the suite
## never clobbers an actual save.

var _had_save: bool
var _backup: PackedByteArray

func before_each() -> void:
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)
	SaveManager.pending_save = {}

func after_each() -> void:
	if _had_save:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	else:
		SaveManager.delete_save()
	SaveManager.pending_save = {}

# --- SaveManager -------------------------------------------------------------

func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	f.store_var(data)
	f.close()

func test_load_rejects_wrong_version() -> void:
	_write_save({"version": SaveManager.SAVE_VERSION + 999})
	assert_false(SaveManager.load_into_pending())
	assert_true(SaveManager.pending_save.is_empty())

func test_load_current_version_stages_pending() -> void:
	_write_save({
		"version": SaveManager.SAVE_VERSION,
		"map_seed": 4242,
		"seen_cells": [Vector2i(1, 2), Vector2i(3, 4)],
		"player": {"pos": Vector2(10, 20), "health": 7},
	})
	assert_true(SaveManager.has_save())
	assert_true(SaveManager.load_into_pending())
	assert_eq(int(SaveManager.pending_save["map_seed"]), 4242)
	# Godot Variant types survive store_var/get_var intact.
	assert_eq(SaveManager.pending_save["seen_cells"][1], Vector2i(3, 4))
	assert_eq(SaveManager.pending_save["player"]["pos"], Vector2(10, 20))

func test_delete_removes_save() -> void:
	_write_save({"version": SaveManager.SAVE_VERSION})
	assert_true(SaveManager.has_save())
	SaveManager.delete_save()
	assert_false(SaveManager.has_save())

# --- Stats run-state ---------------------------------------------------------

func test_capture_run_state_snapshots_live_run() -> void:
	Stats.begin_run()
	Stats.add_kill()
	Stats.add_kill()
	Stats.add_chest()
	var snap := Stats.capture_run_state()
	assert_eq(snap["run"]["enemies_killed"], 2.0)
	assert_eq(snap["run"]["chests_opened"], 1.0)
	assert_true(snap["running"])
	# Reset without persisting to stats.cfg (no end_run call).
	Stats.restore_run_state({"run": {}, "counts": true, "running": false, "seed": 0, "randomize": true})

func test_restore_run_state_round_trips() -> void:
	Stats.restore_run_state({
		"run": {"enemies_killed": 5.0, "chests_opened": 3.0},
		"counts": false,
		"running": true,
		"seed": 99,
		"randomize": false,
	})
	var snap := Stats.capture_run_state()
	assert_eq(snap["run"]["enemies_killed"], 5.0)
	assert_eq(snap["run"]["chests_opened"], 3.0)
	assert_eq(snap["seed"], 99)
	assert_false(snap["counts"])
	assert_true(snap["running"])
	Stats.restore_run_state({"run": {}, "counts": true, "running": false, "seed": 0, "randomize": true})

# --- VisibilityMap.mark_seen -------------------------------------------------

func test_mark_seen_remembers_without_lighting() -> void:
	var vm := VisibilityMap.new()
	vm.mark_seen(Vector2i(3, 4))
	assert_true(vm.is_seen(Vector2i(3, 4)))
	assert_false(vm.is_visible_cell(Vector2i(3, 4)))
	assert_true(vm.seen_cells().has(Vector2i(3, 4)))
