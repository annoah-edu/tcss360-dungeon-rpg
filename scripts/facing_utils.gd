class_name FacingUtils

static func get_facing(direction: Vector2) -> Dictionary:
	var angle: float = direction.angle()
	if abs(angle) > PI / 2:
		var clamped_angle: float = angle - PI if angle > 0 else angle + PI
		return {"rotation": clamped_angle, "flip": true}
	else:
		return {"rotation": angle, "flip": false}
