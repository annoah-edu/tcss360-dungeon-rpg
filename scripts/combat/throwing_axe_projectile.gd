class_name ThrowingAxeProjectile
extends LinearWeaponProjectile

## Presents a spinning single-use axe while shared linear-projectile logic owns travel and hits.

@export var spin_radians_per_second: float = TAU * 3.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	rotation += spin_radians_per_second * delta
