class_name TutorialOverlay extends Control

signal closed

@onready var close_button: Button = %CloseButton


func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false


func open() -> void:
	visible = true
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel", false):
		return
	close()
	get_viewport().set_input_as_handled()
