extends Control
class_name DamageNumber

@export var text_label: String
@export var text_color: Color = Color.WHITE

var alpha: float = 1.1
var x_velocity: float
var y_velocity: float = -45.0

func _ready() -> void:
	$Label.text = text_label
	$Label.add_theme_color_override("font_color", text_color)
	x_velocity = randf_range(-10.0, 10.0)

func _process(delta: float) -> void:
	position += Vector2(x_velocity, y_velocity) * delta
	y_velocity += delta * 120
	alpha -= delta * 1.5
	modulate.a = clamp(alpha, 0.0, 1.0)
	if modulate.a <= 0.1:
		queue_free()
