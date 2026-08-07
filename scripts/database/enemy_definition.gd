class_name EnemyDefinition
extends RefCounted

## Typed runtime view of one enemy_archetypes row. The database owns these
## values; Enemy copies them before entering the scene tree.

var id: StringName
var scene: PackedScene
var max_health: int
var movement_speed: float
var sight_radius: int
var knockback_recovery_speed: int
var wander_radius: float
var minimum_wait: float
var maximum_wait: float

func is_valid() -> bool:
	return (
		id != &""
		and scene != null
		and max_health > 0
		and movement_speed >= 0.0
		and sight_radius >= 0
		and knockback_recovery_speed >= 0
		and wander_radius >= 0.0
		and minimum_wait >= 0.0
		and maximum_wait >= minimum_wait
	)
