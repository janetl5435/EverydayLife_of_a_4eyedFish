extends Node

const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu_scene: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	_expect_true(menu_scene != null, "The main menu scene must load.")
	if menu_scene == null:
		_finish()
		return
	var menu: Control = menu_scene.instantiate() as Control
	_expect_true(menu != null, "The main menu root must be a Control.")
	if menu == null:
		_finish()
		return
	add_child(menu)
	await get_tree().process_frame
	var backdrop: SeaBackdrop = menu.get_node("SeaBackdrop") as SeaBackdrop
	var menu_column: VBoxContainer = menu.get_node("MenuColumn") as VBoxContainer
	var journey_button: Button = menu.get_node("MenuColumn/JourneyButton") as Button
	var compendium_button: Button = menu.get_node("MenuColumn/CompendiumButton") as Button
	var settings_button: Button = menu.get_node("MenuColumn/SettingsButton") as Button
	var tutorial_button: Button = menu.get_node("MenuColumn/TutorialButton") as Button
	var quit_button: TextureButton = menu.get_node("QuitButton") as TextureButton
	var tutorial_overlay: TutorialOverlay = menu.get_node("TutorialOverlay") as TutorialOverlay
	var map_track: Node2D = backdrop.get_node("World/MapTrack") as Node2D
	var repeated_map: Sprite2D = backdrop.get_node("World/MapTrack/MapRepeat") as Sprite2D
	var buttons: Array[Button] = [
		journey_button,
		compendium_button,
		settings_button,
		tutorial_button,
	]
	_expect_true(backdrop != null, "The main menu must use the shared sea backdrop.")
	_expect_true(backdrop.animate_map, "The main menu must enable the looping map motion.")
	_expect_true(
		is_equal_approx(backdrop.map_scroll_speed, 60.0),
		"The main menu must use the intended calm map-scroll speed."
	)
	_expect_true(repeated_map.visible, "The looping main-menu backdrop must show its repeated map.")
	var initial_map_x: float = map_track.position.x
	backdrop.call(&"_process", 1.0)
	_expect_true(
		map_track.position.x < initial_map_x,
		"The main-menu map must move left while the fish remains in place."
	)
	_expect_true(menu.theme.default_font != null, "The shared UI theme must provide a bundled Chinese font.")
	if menu.theme.default_font != null:
		_expect_true(
			menu.theme.default_font.resource_path == "res://assets/fonts/huiwenmingchaoti.otf",
			"The shared UI theme must use huiwenmingchaoti.otf."
		)
	_expect_true(menu.get_node_or_null("Center") == null, "The old centered panel must be removed.")
	_expect_true(menu_column.position.x > 640.0, "Primary menu content must remain on the right side.")
	_expect_true(buttons.size() == 4, "The main menu must expose journey, compendium, settings and tutorial entries.")
	_expect_true(journey_button.text == "开始旅程", "The only gameplay entry must be labelled 开始旅程.")
	_expect_true(tutorial_button.text == "玩法说明", "The tutorial entry must be labelled 玩法说明.")
	_expect_true(tutorial_overlay != null and not tutorial_overlay.visible, "The tutorial overlay must start hidden.")
	_expect_true(AppFlow.get_mode_label(AppFlow.GameMode.FORAGE) == "旅程", "The unified internal mode must use the journey label.")
	for button: Button in buttons:
		_expect_true(
			is_equal_approx(button.custom_minimum_size.y, 150.0),
			"All four primary menu buttons must use the same size."
		)
		_expect_true(not button.has_focus(), "Primary buttons must start without keyboard focus.")
	var down_event: InputEventAction = InputEventAction.new()
	down_event.action = &"ui_down"
	down_event.pressed = true
	menu.call(&"_unhandled_input", down_event)
	_expect_true(journey_button.has_focus(), "The first down input must focus the journey entry.")
	_expect_true(
		journey_button.focus_neighbor_bottom == journey_button.get_path_to(compendium_button),
		"Keyboard focus must move from journey to compendium."
	)
	_expect_true(
		settings_button.focus_neighbor_bottom == settings_button.get_path_to(tutorial_button),
		"Keyboard focus must move from settings to tutorial."
	)
	_expect_true(
		tutorial_button.focus_neighbor_bottom == tutorial_button.get_path_to(journey_button),
		"Primary button focus must wrap from tutorial back to journey."
	)
	_expect_true(quit_button.focus_mode == Control.FOCUS_NONE, "Quit must remain a secondary mouse action.")
	_expect_true(
		quit_button.texture_normal != quit_button.texture_hover,
		"Quit must use distinct idle and selected textures."
	)
	_expect_true(
		journey_button.pressed.is_connected(Callable(menu, "_on_journey_pressed")),
		"The unified journey routing must remain connected."
	)
	_expect_true(
		compendium_button.pressed.is_connected(Callable(menu, "_on_compendium_pressed")),
		"Compendium routing must remain connected."
	)
	_expect_true(
		settings_button.pressed.is_connected(Callable(menu, "_on_settings_pressed")),
		"Settings routing must remain connected."
	)
	_expect_true(
		tutorial_button.pressed.is_connected(Callable(menu, "_on_tutorial_pressed")),
		"Tutorial routing must remain connected."
	)
	tutorial_button.pressed.emit()
	_expect_true(tutorial_overlay.visible, "Pressing 玩法说明 must open the tutorial overlay.")
	for button: Button in buttons:
		_expect_true(button.disabled, "Primary menu buttons must be disabled while the tutorial is open.")
	var cards: HBoxContainer = tutorial_overlay.get_node("Center/Panel/Margin/Content/Cards") as HBoxContainer
	_expect_true(cards != null and cards.get_child_count() == 3, "The tutorial must contain three concise instruction cards.")
	var close_button: Button = tutorial_overlay.get_node("Center/Panel/Margin/Content/Header/CloseButton") as Button
	_expect_true(close_button.has_focus(), "Opening the tutorial must focus its return button.")
	close_button.pressed.emit()
	_expect_true(not tutorial_overlay.visible, "The return button must close the tutorial overlay.")
	for button: Button in buttons:
		_expect_true(not button.disabled, "Primary menu buttons must be re-enabled after closing the tutorial.")
		_expect_true(
			not button.has_focus(),
			"Closing the tutorial must leave primary menu buttons without keyboard focus."
		)
	menu.queue_free()
	await get_tree().process_frame
	_finish()


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MAIN_MENU_LAYOUT_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
