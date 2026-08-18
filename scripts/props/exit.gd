extends Area2D
class_name DungeonExit

## The single way out of the dungeon, dropped by MapAssembler in the room furthest from
## the start (so it sits at an edge of the layout). Walking the player into it ends the
## run: it snapshots the stats and hands off to the run-summary screen.
##
## Builds its own collision shape and a small pulsing portal marker in code, so the scene
## is just an Area2D carrying this script.

const SUMMARY_SCENE := "res://scenes/ui/run_summary.tscn"
const PORTAL_COLOR := Color(0.4, 0.85, 0.55)
## Half-extents of the trigger / marker, in pixels (a bit under one tile).
const HALF_SIZE := 7.0

var _triggered := false
var _elapsed := 0.0
var _marker: Polygon2D

func _ready() -> void:
	# Match the player's physics layer the way the chest's interaction area does (mask 2).
	collision_mask = 2
	monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(HALF_SIZE, HALF_SIZE) * 2.0
	shape.shape = rect
	add_child(shape)

	# A green diamond so the way out reads clearly once the player's sight reaches it.
	_marker = Polygon2D.new()
	_marker.polygon = PackedVector2Array([
		Vector2(0, -HALF_SIZE), Vector2(HALF_SIZE, 0),
		Vector2(0, HALF_SIZE), Vector2(-HALF_SIZE, 0),
	])
	_marker.color = PORTAL_COLOR
	add_child(_marker)

	var label := Label.new()
	label.text = "EXIT"
	label.add_theme_font_size_override("font_size", 8)
	var font := load("res://resources/fonts/Minecraft.ttf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", PORTAL_COLOR)
	label.position = Vector2(-9, -HALF_SIZE - 14)
	add_child(label)

	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Gentle breathing pulse so the portal looks active.
	_elapsed += delta
	if _marker != null:
		_marker.scale = Vector2.ONE * (1.0 + 0.12 * sin(_elapsed * 3.0))
	
	if GameState.player.pillar_inventory.size() < 4:
		modulate = Color.RED
	else:
		modulate = Color.WHITE

func _on_body_entered(body: Node2D) -> void:
	if _triggered or not (body is Player):
		return
	if GameState.player.pillar_inventory.size() < 4:
		return
	_triggered = true
	Stats.end_run()
	get_tree().change_scene_to_file(SUMMARY_SCENE)
