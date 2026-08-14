class_name WeaponAttackBehavior
extends Node2D

## Presentation and hit-detection contract implemented by each attack style.

signal hit_requested(targets: Array[Enemy], source_position: Vector2)


func configure(_data: WeaponData) -> void:
	pass


func aim(_direction: Vector2) -> void:
	pass


func start_attack() -> void:
	pass
