extends Node2D

@export var closed_texture: Texture2D
@export var open_texture: Texture2D

@onready var sprite: Sprite2D = $Sprite2D

var is_open := false

func _ready() -> void:
	sprite.texture = closed_texture

func open() -> void:
	if is_open:
		return

	is_open = true
	sprite.texture = open_texture

func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		open()
