extends ProgressBar

## Displays the current pillar count once MapAssembler assigns GameState.player.
## Standalone player scenes and tests remain at zero until that owner is available.

@onready var count_label: Label = $Label


func _ready() -> void:
	max_value = 4
	update_pillar_count()


func _process(_delta: float) -> void:
	update_pillar_count()


func update_pillar_count() -> void:
	var player := GameState.player
	if player == null or not is_instance_valid(player):
		value = 0
		count_label.text = "0/4 Pillars Collected"
		return
	var pillar_count := player.pillar_inventory.size()
	value = pillar_count
	count_label.text = str(pillar_count) + "/4 Pillars Collected"

	if pillar_count == 4:
		count_label.text = "All pillars collected! Find the exit."
