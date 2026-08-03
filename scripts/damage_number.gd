extends Control
class_name DamageNumber

@export var popup_text: String = "1"

var alpha: float = 1.1
var x_velocity: float
var y_velocity: float = -45.0

func _ready() -> void:
	$Damage.text = str(popup_text)
	x_velocity = randf_range(-10.0, 10.0)

func _process(delta: float) -> void:
	position += Vector2(x_velocity, y_velocity) * delta
	y_velocity += delta * 120
	alpha -= delta * 1.5
	modulate.a = clamp(alpha, 0.0, 1.0)
	if modulate.a <= 0.1:
		queue_free()
