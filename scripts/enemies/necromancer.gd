extends Enemy
class_name Necromancer

var summon_cooldown: float = 4
var summon_timer: float = 2

func _ready() -> void:
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	summon_timer -= delta

func _attack_loop(dist_to_player: float) -> void:
	super._attack_loop(dist_to_player)
	if summon_timer <= 0:
		summon_timer = summon_cooldown
		for i in range(0, randi_range(2, 3)):
			spawner.spawn_at_position(&"skeleton", global_position, 30)
		
