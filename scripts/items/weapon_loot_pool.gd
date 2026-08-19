class_name WeaponLootPool
extends Resource

## Immutable collection of weapon definitions available to randomized loot generation.
## SQLite owns pool membership and weights. Selection uses the caller-owned RNG
## so chest seeds remain reproducible.

@export var pool_id: StringName = &""

var _cached_entries: Array[Dictionary] = []
var _cache_initialized := false


func all_weapons() -> Array[WeaponData]:
	var weapons: Array[WeaponData] = []
	for entry in _entries():
		weapons.append(entry["weapon"] as WeaponData)
	return weapons


## Returns one weighted shared weapon definition, or null for an empty pool.
func random_weapon(random_number_generator: RandomNumberGenerator) -> WeaponData:
	var entries := _entries()
	if random_number_generator == null or entries.is_empty():
		return null
	var total_weight := 0.0
	for entry in entries:
		total_weight += float(entry["weight"])
	var roll := random_number_generator.randf_range(0.0, total_weight)
	for entry in entries:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return entry["weapon"] as WeaponData
	return entries.back()["weapon"] as WeaponData


## Reports invalid or duplicate weapon definitions without mutating the pool.
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var weapons := all_weapons()
	var weapon_ids: Dictionary[StringName, bool] = {}
	for index in weapons.size():
		var weapon := weapons[index]
		if weapon == null:
			errors.append("weapons[%d] must not be null" % index)
			continue
		if weapon_ids.has(weapon.id):
			errors.append("weapon id '%s' must not be duplicated" % weapon.id)
		weapon_ids[weapon.id] = true
		for weapon_error in weapon.validation_errors():
			errors.append("weapons[%d]: %s" % [index, weapon_error])
	if weapons.is_empty():
		errors.append("weapons must not be empty")
	return errors


func _entries() -> Array[Dictionary]:
	if pool_id == &"" or not GameDatabase.is_available():
		return []
	if not _cache_initialized:
		_cached_entries = GameDatabase.get_weapon_loot_pool_entries(pool_id)
		_cache_initialized = true
	return _cached_entries
