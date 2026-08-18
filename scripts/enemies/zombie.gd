extends Enemy
class_name Zombie

func death_behavior() -> void:
	spawner.spawn_at_position("Skeleton", global_position, 0)
