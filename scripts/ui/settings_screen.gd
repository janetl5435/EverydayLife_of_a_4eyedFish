extends Control

@onready var audio_button: Button = %AudioButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	audio_button.pressed.connect(_on_audio_pressed)
	fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	back_button.pressed.connect(AppFlow.open_main_menu)
	SettingsService.audio_enabled_changed.connect(_on_audio_enabled_changed)
	SettingsService.fullscreen_enabled_changed.connect(_on_fullscreen_enabled_changed)
	_configure_focus_chain()
	_refresh_button_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		AppFlow.open_main_menu()
		get_viewport().set_input_as_handled()
		return
	if _option_button_has_focus():
		return
	if event.is_action_pressed(&"ui_down"):
		audio_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		back_button.grab_focus()
		get_viewport().set_input_as_handled()


func _configure_focus_chain() -> void:
	var buttons: Array[Button] = [audio_button, fullscreen_button, back_button]
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		var previous_button: Button = buttons[(index - 1 + buttons.size()) % buttons.size()]
		var next_button: Button = buttons[(index + 1) % buttons.size()]
		button.focus_neighbor_top = button.get_path_to(previous_button)
		button.focus_neighbor_bottom = button.get_path_to(next_button)


func _option_button_has_focus() -> bool:
	return (
		audio_button.has_focus()
		or fullscreen_button.has_focus()
		or back_button.has_focus()
	)


func _refresh_button_text() -> void:
	audio_button.text = "音量：%s" % ("开" if SettingsService.is_audio_enabled() else "关")
	fullscreen_button.text = (
		"全屏：%s" % ("开" if SettingsService.is_fullscreen_enabled() else "关")
	)


func _on_audio_pressed() -> void:
	SettingsService.set_audio_enabled(not SettingsService.is_audio_enabled())


func _on_fullscreen_pressed() -> void:
	SettingsService.set_fullscreen_enabled(not SettingsService.is_fullscreen_enabled())


func _on_audio_enabled_changed(_enabled: bool) -> void:
	_refresh_button_text()


func _on_fullscreen_enabled_changed(_enabled: bool) -> void:
	_refresh_button_text()
