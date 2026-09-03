extends Node

const SETTINGS_SCENE_PATH: String = "res://scenes/ui/settings_screen.tscn"
const COMPENDIUM_SCENE_PATH: String = "res://scenes/ui/compendium.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_settings_screen()
	await _check_compendium()
	_finish()


func _check_settings_screen() -> void:
	var settings_scene: PackedScene = load(SETTINGS_SCENE_PATH) as PackedScene
	_expect_true(settings_scene != null, "The settings scene must load.")
	if settings_scene == null:
		return
	var original_audio: bool = SettingsService.is_audio_enabled()
	var original_fullscreen: bool = SettingsService.is_fullscreen_enabled()
	var settings: Control = settings_scene.instantiate() as Control
	add_child(settings)
	await get_tree().process_frame
	var backdrop: SeaBackdrop = settings.get_node("SeaBackdrop") as SeaBackdrop
	var options: VBoxContainer = settings.get_node("OptionsColumn") as VBoxContainer
	var audio_button: Button = settings.get_node("OptionsColumn/AudioButton") as Button
	var fullscreen_button: Button = settings.get_node(
		"OptionsColumn/FullscreenButton"
	) as Button
	var back_button: Button = settings.get_node("OptionsColumn/BackButton") as Button
	var buttons: Array[Button] = [audio_button, fullscreen_button, back_button]
	_expect_true(backdrop != null, "Settings must retain the shared sea backdrop.")
	_expect_true(options.position.x > 640.0, "Settings controls must remain on the right side.")
	for button: Button in buttons:
		_expect_true(
			button.custom_minimum_size.y > 0.0
			and is_equal_approx(
				button.custom_minimum_size.y,
				audio_button.custom_minimum_size.y
			),
			"Settings actions must retain matching button heights."
		)
		_expect_true(not button.has_focus(), "Settings buttons must start without focus.")
	_expect_true(
		audio_button.text.begins_with("音量："),
		"The audio setting must be presented as a labeled button."
	)
	_expect_true(
		fullscreen_button.text.begins_with("全屏："),
		"The fullscreen setting must be presented as a labeled button."
	)
	var down_event: InputEventAction = InputEventAction.new()
	down_event.action = &"ui_down"
	down_event.pressed = true
	settings.call(&"_unhandled_input", down_event)
	_expect_true(audio_button.has_focus(), "The first down input must focus the audio option.")
	audio_button.pressed.emit()
	_expect_true(
		SettingsService.is_audio_enabled() != original_audio,
		"The audio button must toggle the saved audio state."
	)
	fullscreen_button.pressed.emit()
	_expect_true(
		SettingsService.is_fullscreen_enabled() != original_fullscreen,
		"The fullscreen button must toggle the saved fullscreen state."
	)
	SettingsService.set_audio_enabled(original_audio)
	SettingsService.set_fullscreen_enabled(original_fullscreen)
	settings.queue_free()
	await get_tree().process_frame


func _check_compendium() -> void:
	var compendium_scene: PackedScene = load(COMPENDIUM_SCENE_PATH) as PackedScene
	_expect_true(compendium_scene != null, "The compendium scene must load.")
	if compendium_scene == null:
		return
	var compendium: Control = compendium_scene.instantiate() as Control
	add_child(compendium)
	await get_tree().process_frame
	var backdrop: SeaBackdrop = compendium.get_node("SeaBackdrop") as SeaBackdrop
	var right_column: VBoxContainer = compendium.get_node("RightColumn") as VBoxContainer
	var scroll: ScrollContainer = compendium.get_node("RightColumn/Scroll") as ScrollContainer
	var achievement_list: GridContainer = compendium.get_node(
		"RightColumn/Scroll/AchievementList"
	) as GridContainer
	var back_button: Button = compendium.get_node("RightColumn/BackButton") as Button
	var definitions: Array[AchievementDefinition] = AchievementService.get_definitions()
	_expect_true(backdrop != null, "Compendium must retain the shared sea backdrop.")
	_expect_true(
		right_column.position.x > 640.0,
		"Achievement entries must replace the main-menu buttons on the right."
	)
	_expect_true(
		achievement_list.get_child_count() == definitions.size(),
		"Compendium must render exactly the planned achievement definitions."
	)
	_expect_true(achievement_list.columns == 2, "The compendium must use two card columns.")
	for index: int in range(definitions.size()):
		var card: AchievementCard = achievement_list.get_child(index) as AchievementCard
		_expect_true(card != null, "Every compendium entry must use AchievementCard.")
		if card == null:
			continue
		_expect_true(
			card.title_label.text == definitions[index].display_name,
			"Compendium card names must follow the planning document."
		)
		_expect_true(
			card.icon_rect.texture == definitions[index].icon,
			"Compendium cards must use the supplied achievement artwork."
		)
		_expect_true(
			card.get_node_or_null("%StatusLabel") == null,
			"Compendium cards must not show unlock-status text."
		)
	var scroll_bar: VScrollBar = scroll.get_v_scroll_bar()
	_expect_true(
		scroll_bar.max_value > scroll_bar.page,
		"The right-side achievement list must overflow vertically and scroll."
	)
	_expect_true(not back_button.has_focus(), "Compendium must not start highlighted.")
	compendium.queue_free()
	await get_tree().process_frame


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SETTINGS_COMPENDIUM_LAYOUT_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
