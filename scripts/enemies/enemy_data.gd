extends Resource
class_name EnemyData

@export var name: String = "Goblin"
@export var enemy_behavior: Script = preload("res://scripts/enemies/enemy.gd")
@export var max_health: int = 100
@export var speed: float = 80.0
@export var atk_dmg: int = 35
@export var atk_rate: float = 1.0
@export var los_radius: int = 75
@export var knockback_recovery_spd: int = 500
@export var sprite_frames: SpriteFrames
