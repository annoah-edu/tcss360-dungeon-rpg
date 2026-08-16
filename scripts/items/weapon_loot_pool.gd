class_name WeaponLootPool
extends Resource

## Immutable collection of weapon definitions available to randomized loot generation.
## Selection uses the caller-owned RNG so chest seeds remain reproducible.

@export var weapons: Array[WeaponData] = []


## Returns one uniformly selected shared weapon definition, or null for an empty pool.
func random_weapon(random_number_generator: RandomNumberGenerator) -> WeaponData:
	if random_number_generator == null or weapons.is_empty():
		return null
	var selected_index := random_number_generator.randi_range(0, weapons.size() - 1)
	return weapons[selected_index]


## Reports invalid or duplicate weapon definitions without mutating the pool.
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
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
