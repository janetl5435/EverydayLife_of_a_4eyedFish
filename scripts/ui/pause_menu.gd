class_name PauseMenu extends Control

signal resumed
signal abandon_requested

@onready var resume_button: Button = %ResumeButton
@onready var abandon_button: Button = %AbandonButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(close_menu)
	abandon_button.pressed.connect(_on_abandon_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause", false):
		close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	resumed.emit()


func close_without_resume_signal() -> void:
	visible = false
	get_tree().paused = false


func _on_abandon_pressed() -> void:
	close_without_resume_signal()
	abandon_requested.emit()
