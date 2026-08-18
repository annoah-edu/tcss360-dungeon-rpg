extends Enemy
class_name Zombie

func death_behavior() -> void:
	spawner.spawn_at_position(&"skeleton", global_position, 0)
