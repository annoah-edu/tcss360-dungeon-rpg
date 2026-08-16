class_name WeaponHitSource
extends Node2D

## Defines a detached attack source that can report hits after its behavior has finished.
## The weapon controller owns damage; implementations own movement, collision, and lifetime.

## Requests damage for a snapshot of targets from this source's world-space position.
signal hit_requested(targets: Array[Enemy], source_position: Vector2)
