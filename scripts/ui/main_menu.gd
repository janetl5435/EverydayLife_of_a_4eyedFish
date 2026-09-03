extends Control

@onready var journey_button: Button = %JourneyButton
@onready var compendium_button: Button = %CompendiumButton
@onready var settings_button: Button = %SettingsButton
@onready var tutorial_button: Button = %TutorialButton
@onready var quit_button: TextureButton = %QuitButton
@onready var tutorial_overlay: TutorialOverlay = %TutorialOverlay


func _ready() -> void:
	journey_button.pressed.connect(_on_journey_pressed)
	compendium_button.pressed.connect(_on_compendium_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	tutorial_button.pressed.connect(_on_tutorial_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	tutorial_overlay.closed.connect(_on_tutorial_closed)
	_configure_primary_focus_chain()


func _unhandled_input(event: InputEvent) -> void:
	if tutorial_overlay.visible:
		return
	if _primary_button_has_focus():
		return
	if event.is_action_pressed(&"ui_down"):
		journey_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		settings_button.grab_focus()
		get_viewport().set_input_as_handled()


func _primary_button_has_focus() -> bool:
	return (
		journey_button.has_focus()
		or compendium_button.has_focus()
		or settings_button.has_focus()
		or tutorial_button.has_focus()
	)


func _configure_primary_focus_chain() -> void:
	var primary_buttons: Array[Button] = [
		journey_button,
		compendium_button,
		settings_button,
		tutorial_button,
	]
	for index: int in range(primary_buttons.size()):
		var button: Button = primary_buttons[index]
		var previous_button: Button = primary_buttons[
			(index - 1 + primary_buttons.size()) % primary_buttons.size()
		]
		var next_button: Button = primary_buttons[(index + 1) % primary_buttons.size()]
		button.focus_neighbor_top = button.get_path_to(previous_button)
		button.focus_neighbor_bottom = button.get_path_to(next_button)


func _on_journey_pressed() -> void:
	AppFlow.begin_journey()


func _on_compendium_pressed() -> void:
	AppFlow.open_compendium()


func _on_settings_pressed() -> void:
	AppFlow.open_settings()


func _on_tutorial_pressed() -> void:
	_set_primary_buttons_disabled(true)
	tutorial_overlay.open()


func _on_tutorial_closed() -> void:
	_set_primary_buttons_disabled(false)
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func _set_primary_buttons_disabled(disabled: bool) -> void:
	for button: Button in [journey_button, compendium_button, settings_button, tutorial_button]:
		button.disabled = disabled


func _on_quit_pressed() -> void:
	AppFlow.quit_game()
