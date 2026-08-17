extends Sprite2D
class_name Pillar

const amplitude: int = 3

@onready var collider: Area2D = $Area2D
@onready var particles: GPUParticles2D = $Particles

var my_position: Vector2
var float_timer: float = 0.0
var pillar_name: String

func _ready() -> void:
	my_position = global_position
	collider.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	float_timer += delta * 2
	global_position = my_position + Vector2(0, roundi(sin(float_timer) * amplitude))

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		collider.body_entered.disconnect(_on_body_entered)
		
		GameState.player.pillar_inventory.append(pillar_name)
		self_modulate = Color(0.0, 0.0, 0.0, 0.0)
		particles.emitting = true
		particles.finished.connect(func(): queue_free())
