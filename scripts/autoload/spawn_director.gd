extends Node

## Autoload registry that decouples rooms from gameplay systems. Rooms register
## their SpawnPoints here; enemy, loot, and future NPC systems query points by
## category and instantiate their own content.

var _points: Dictionary = {}  # Category -> Array[SpawnPoint]

func register(point: SpawnPoint) -> void:
	if not _points.has(point.category):
		_points[point.category] = []
	_points[point.category].append(point)

## Query surface for future spawn systems.
func get_points(category: SpawnPoint.Category) -> Array:
	return _points.get(category, [])

func clear() -> void:
	_points.clear()

## Debug pass until real spawn systems exist: log what was registered so we can
## see spawn coverage across the generated dungeon.
func populate() -> void:
	var total := 0
	for cat in _points:
		total += _points[cat].size()
	print("[SpawnDirector] %d spawn points registered:" % total)
	for cat in _points:
		print("  %s: %d" % [_category_name(cat), _points[cat].size()])

func _category_name(category: int) -> String:
	var names := SpawnPoint.Category.keys()
	if category >= 0 and category < names.size():
		return names[category]
	return str(category)
