extends GutTest

var start_screen
var _previous_invincibility: bool


func before_each() -> void:
	_previous_invincibility = GameState.invincibility_enabled
	GameState.invincibility_enabled = true
	start_screen = preload("res://scenes/ui/start_screen.tscn").instantiate()
	add_child_autofree(start_screen)


func after_each() -> void:
	GameState.invincibility_enabled = _previous_invincibility


func test_invincibility_button_reflects_and_toggles_game_state() -> void:
	var button: Button = start_screen._invincibility_button
	assert_eq(button.text, "Invincibility: ON")

	button.pressed.emit()

	assert_false(GameState.invincibility_enabled)
	assert_eq(button.text, "Invincibility: OFF")
