class_name Placement
extends RefCounted

## One room the generator has committed to the layout: which template, where its
## origin sits in world tile coordinates, and which of its doors ended up
## connected (indices line up with [member RoomTemplate.doors] and, once
## instantiated, with [method Room.get_doors]).

var template: RoomTemplate
var origin: Vector2i
var connected: Array[bool] = []

func _init(p_template: RoomTemplate = null, p_origin: Vector2i = Vector2i.ZERO) -> void:
	template = p_template
	origin = p_origin
	if p_template != null:
		connected.resize(p_template.doors.size())
		connected.fill(false)
