extends Node

## Single-slot save/load for a dungeon run. Autoloaded as `SaveManager`.
##
## The dungeon is regenerated deterministically from its seed on load, so the save stores
## only the seed plus the *dynamic* state that generation cannot reproduce: the player,
## chest contents/open-state, live enemies, remaining pillars, explored fog, and the
## in-progress run statistics. MapAssembler consumes `pending_save` when it builds.
##
## Items are stored as their resource_path (ItemData/WeaponData are .tres resources with
## stable paths) and reloaded with load(); an empty slot is the empty string.

const SAVE_PATH := "user://savegame.sav"
const SAVE_VERSION := 1

## Payload staged by load_into_pending() for the map scene to apply on its next build.
## Empty when there is nothing to restore. Mirrors how Stats stages its pending run config.
var pending_save: Dictionary = {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

## Gather the live run into a dictionary and write it. `assembler` is the MapAssembler whose
## children hold the chests, enemies and pillars, and whose `visibility`/`map_seed` describe
## the layout. Returns false if there is no player to save.
func save_game(assembler: Node) -> bool:
	var player: Player = GameState.player
	if player == null or not is_instance_valid(player):
		push_warning("SaveManager: no player to save")
		return false

	var data := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"map_seed": int(assembler.map_seed),
		"player": _capture_player(player),
		"chests": _capture_chests(assembler),
		"enemies": _capture_enemies(assembler),
		"pillars_remaining": _capture_pillars(assembler),
		"seen_cells": assembler.visibility.seen_cells(),
		"stats_run": Stats.capture_run_state(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open %s for writing" % SAVE_PATH)
		return false
	file.store_var(data)
	file.close()
	return true

## Read the save into `pending_save`. The caller then changes to the map scene, which
## applies it. Returns false when there is no valid save.
func load_into_pending() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = file.get_var()
	file.close()
	if not (data is Dictionary) or int((data as Dictionary).get("version", -1)) != SAVE_VERSION:
		push_warning("SaveManager: save missing or wrong version")
		return false
	pending_save = data
	return true

# --- Capture helpers ---------------------------------------------------------

func _capture_player(player: Player) -> Dictionary:
	var slots: Array[String] = []
	for item in player.inventory.slots:
		slots.append(item.resource_path if item != null else "")
	var equipped := player.weapon_equipment.equipped_weapon
	return {
		"pos": player.global_position,
		"health": player.health,
		"pillar_inventory": player.pillar_inventory.duplicate(),
		"inventory": slots,
		"equipped": equipped.resource_path if equipped != null else "",
	}

## Chests in spawn order (their child order under the assembler), so load can match them to
## the deterministically re-spawned chests one-for-one.
func _capture_chests(assembler: Node) -> Array:
	var result: Array = []
	for child in assembler.get_children():
		if child is Chest:
			var chest := child as Chest
			var items: Array[String] = []
			if chest.inventory != null:
				for item in chest.inventory.slots:
					items.append(item.resource_path if item != null else "")
			result.append({
				"pos": chest.global_position,
				"is_open": chest.is_open,
				"items": items,
			})
	return result

func _capture_enemies(assembler: Node) -> Array:
	var result: Array = []
	for child in assembler.get_tree().current_scene.get_children():
		if child is Enemy:
			var enemy := child as Enemy
			var type_name := enemy.data.name if enemy.data != null else ""
			if type_name.is_empty():
				continue
			result.append({
				"type": type_name,
				"pos": enemy.global_position,
				"health": enemy.health,
				"found_player": enemy.found_player,
			})
	return result

## Pillars still standing in the world (not yet collected), with their positions so load
## restores them exactly rather than re-rolling random spawn points.
func _capture_pillars(assembler: Node) -> Array:
	var result: Array = []
	for child in assembler.get_tree().current_scene.get_children():
		if child is Pillar:
			var pillar := child as Pillar
			result.append({"name": pillar.pillar_name, "pos": pillar.global_position})
	return result
