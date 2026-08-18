extends Resource
class_name EnemyData

## SQL owns scalar gameplay tuning. This resource remains the presentation and
## behavior template because scripts and SpriteFrames are Godot-native assets.

@export var id: StringName = &"goblin"
@export var name: String = "Goblin"
@export var enemy_behavior: Script = preload("res://scripts/enemies/enemy.gd")
@export var max_health: int = 100
@export var speed: float = 80.0
@export var atk_dmg: int = 35
@export var atk_rate: float = 1.0
@export var los_radius: int = 75
@export var knockback_recovery_spd: int = 500
@export var wander_radius: float = 300.0
@export var min_wait: float = 2.0
@export var max_wait: float = 3.0
@export var sprite_frames: SpriteFrames


func is_valid() -> bool:
	return (
		id != &""
		and not name.strip_edges().is_empty()
		and enemy_behavior != null
		and sprite_frames != null
		and max_health > 0
		and speed >= 0.0
		and atk_dmg >= 0
		and atk_rate > 0.0
		and los_radius >= 0
		and knockback_recovery_spd >= 0
		and wander_radius >= 0.0
		and min_wait >= 0.0
		and max_wait >= min_wait
	)
