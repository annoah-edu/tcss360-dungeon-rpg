extends Node

var pillar_names: Array[String] = [
	"Abstraction", "Encapsulation", "Inheritance", "Polymorphism"
]
var pillar_textures: Array[Texture2D] = [
	preload("res://resources/sprites/abstraction.png"),
	preload("res://resources/sprites/encapsulation.png"),
	preload("res://resources/sprites/inheritance.png"),
	preload("res://resources/sprites/polymorphism.png")
]
var pillar_scene: PackedScene = preload("res://scenes/props/pillar.tscn")

func populate_map() -> void:
	call_deferred("spawn_pillars")

## Re-place a single saved pillar at an exact position, looking up its texture by name.
## Used by MapAssembler on load instead of the random spawn_pillars() pass.
func spawn_saved(pillar_name: String, pos: Vector2) -> void:
	var index := pillar_names.find(pillar_name)
	var pillar: Pillar = pillar_scene.instantiate()
	pillar.pillar_name = pillar_name
	if index >= 0:
		pillar.texture = pillar_textures[index]
	pillar.global_position = pos
	get_tree().current_scene.add_child(pillar)

func spawn_pillars() -> void:
	var director := get_node("/root/SpawnDirector")
	var points: Array = director.get_points(SpawnPoint.Category.ENEMY)
	if points.is_empty():
		return
	var sp: SpawnPoint
	for i in range(0, 4): # Pick four spawn areas
		sp = points.pop_at(randi() % points.size())
		var pillar: Pillar = pillar_scene.instantiate()
		pillar.pillar_name = pillar_names[i]
		pillar.texture = pillar_textures[i]
		pillar.global_position = sp.global_position
		get_tree().current_scene.add_child(pillar)
	
