extends ProgressBar

func _ready() -> void:
	max_value = 4
	update_pillar_count()

func _process(_delta: float) -> void:
	update_pillar_count()

func update_pillar_count() -> void:
	var pillar_count: int = GameState.player.pillar_inventory.size()
	value = pillar_count
	$Label.text = str(pillar_count) + "/4 Pillars Collected"
	
	if pillar_count == 4:
		$Label.text = "All pillars collected! Find the exit."
