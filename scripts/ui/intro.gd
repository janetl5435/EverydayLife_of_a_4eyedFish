extends Control

@onready var intro_sequence: FullScreenSequence = %IntroSequence

var _transitioning: bool = false


func _ready() -> void:
	intro_sequence.sequence_finished.connect(_on_intro_sequence_finished)
	if intro_sequence.has_finished():
		_on_intro_sequence_finished()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or not intro_sequence.is_playing():
		return
	if _is_skip_event(event):
		get_viewport().set_input_as_handled()
		intro_sequence.skip_to_end()


func _is_skip_event(event: InputEvent) -> bool:
	return (
		event.is_action_pressed(&"ui_accept")
		or event.is_action_pressed(&"ui_cancel")
		or (event is InputEventMouseButton and event.pressed)
	)


func _on_intro_sequence_finished() -> void:
	if _transitioning:
		return
	_transitioning = true
	AppFlow.open_main_menu()
