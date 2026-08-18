class_name WeaponAttackBehavior
extends Node2D

## Defines the presentation and hit-detection contract for an equipped attack style.
## Implementations own attack-specific scene behavior but never authoritative weapon statistics.

## Requests that the controller damage a snapshot of targets from this world-space source.
signal hit_requested(targets: Array[Enemy], source_position: Vector2)
## Announces a detached attack source whose later hits retain this attack's weapon data.
signal hit_source_spawned(source: WeaponHitSource)
## Announces that an attack produced its gameplay effect and may consume a single-use weapon.
signal attack_committed


## Applies immutable weapon presentation and timing data to this behavior instance.
func configure(_data: WeaponData) -> void:
	pass


## Faces this behavior along a direction expressed in its parent's coordinate space.
func aim(_direction: Vector2) -> void:
	pass


## Starts this behavior's configured attack presentation and hit sequence.
func start_attack() -> void:
	pass
