extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"
const RESULT_SCENE_PATH: String = "res://scenes/ui/result_screen.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_gameplay_hud(AppFlow.GameMode.FORAGE)
	await _check_gameplay_hud(AppFlow.GameMode.PATROL)
	await _check_result_screen()
	_finish()


func _check_gameplay_hud(mode: AppFlow.GameMode) -> void:
	AppFlow.current_mode = mode
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.run_finish_distance = 100000.0
	test_config.wet_eye_duration = 10.0
	gameplay.world_config = test_config
	gameplay.route_scenes_after_settlement = false
	add_child(gameplay)
	await get_tree().process_frame
	var hud: Control = gameplay.get_node("Interface/HUD") as Control
	var region_guide: RegionGuide = gameplay.get_node("World/RegionGuide") as RegionGuide
	var energy_panel: PanelContainer = gameplay.get_node(
		"Interface/HUD/EnergyPanel"
	) as PanelContainer
	var energy_label: Label = gameplay.get_node(
		"Interface/HUD/EnergyPanel/Margin/Content/EnergyLabel"
	) as Label
	var wet_eye_panel: PanelContainer = gameplay.get_node(
		"Interface/HUD/WetEyePanel"
	) as PanelContainer
	var warning_overlay: CenterContainer = gameplay.get_node(
		"Interface/HUD/WetEyePanel/WetEyeWarningOverlay"
	) as CenterContainer
	var debug_buttons: HBoxContainer = gameplay.get_node(
		"Interface/HUD/DebugButtons"
	) as HBoxContainer
	var hint_label: Label = gameplay.get_node(
		"Interface/HUD/HintPanel/ActionHintLabel"
	) as Label
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect_true(viewport_rect.encloses(hud.get_global_rect()), "HUD must fit the viewport.")
	_expect_true(not region_guide.visible, "White-box region guides must stay hidden in gameplay.")
	_expect_true(
		wet_eye_panel.position.x > 640.0 and wet_eye_panel.position.y > 360.0,
		"Wet-eye timing must occupy the lower-right HUD area."
	)
	_expect_true(not debug_buttons.visible, "Development controls must not appear in the player HUD.")
	_expect_true(not hint_label.text.contains("相机"), "Player hints must not expose camera debug details.")
	for telemetry_name: String in ["ModeLabel", "ViewLabel", "RegionLabel", "DistanceLabel"]:
		var telemetry: Label = gameplay.get_node(
			"Interface/HUD/EnergyPanel/Margin/Content/%s" % telemetry_name
		) as Label
		_expect_true(not telemetry.visible, "Development telemetry must remain hidden.")
	if mode == AppFlow.GameMode.FORAGE:
		_expect_true(energy_panel.visible, "Forage HUD must show the energy meter.")
		_expect_true(energy_panel.position.x < 320.0, "Energy must occupy the upper-left HUD area.")
		_expect_true(energy_label.text == "能量：20", "Journey energy must start at twenty.")
		var forage: ForageModeController = gameplay.get_node(
			"ModeHost/ForageModeController"
		) as ForageModeController
		forage.energy_changed.emit(17)
		_expect_true(energy_label.text == "能量：17", "Energy changes must update the HUD.")
		gameplay.call(
			&"_on_forage_profile_changed",
			RegionLayout.ViewProfile.FORAGE_DEEP
		)
		_expect_true(not wet_eye_panel.visible, "Deep forage must hide the wet-eye HUD.")
	else:
		_expect_true(not energy_panel.visible, "Patrol HUD must not show forage energy.")
		_expect_true(wet_eye_panel.visible, "Patrol HUD must retain wet-eye timing.")
	var wet_eye: WetEyeController = gameplay.get_node(
		"Systems/WetEyeController"
	) as WetEyeController
	wet_eye.set_process(false)
	if mode == AppFlow.GameMode.PATROL:
		wet_eye.advance_time(7.1)
		_expect_true(warning_overlay.visible, "The final three seconds must show the HUD warning.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_result_screen() -> void:
	var result: RunResult = RunResult.new()
	result.mode = AppFlow.GameMode.FORAGE
	result.outcome = RunResult.Outcome.NATURAL_FINISH
	result.success = true
	result.travelled_distance = 5000.0
	result.energy = 14
	result.streak_count = 2
	result.add_new_unlock(AchievementService.ACHIEVEMENT_DELICIOUS_SHELLFISH)
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	AppFlow.store_run_result(result)
	var result_scene: PackedScene = load(RESULT_SCENE_PATH) as PackedScene
	var result_screen: Control = result_scene.instantiate() as Control
	add_child(result_screen)
	await get_tree().process_frame
	var backdrop: SeaBackdrop = result_screen.get_node("SeaBackdrop") as SeaBackdrop
	var success_animation: AnimatedSprite2D = result_screen.get_node(
		"SuccessAnimation"
	) as AnimatedSprite2D
	var stats_panel: Control = result_screen.get_node("StatsPanel") as Control
	var buttons: VBoxContainer = result_screen.get_node("ButtonsColumn") as VBoxContainer
	var achievements: VBoxContainer = result_screen.get_node(
		"NewAchievementsArea"
	) as VBoxContainer
	var achievement_scroll: ScrollContainer = result_screen.get_node(
		"NewAchievementsArea/NewAchievementsScroll"
	) as ScrollContainer
	var cards: VBoxContainer = result_screen.get_node(
		"NewAchievementsArea/NewAchievementsScroll/NewAchievements"
	) as VBoxContainer
	var energy_texture: TextureRect = result_screen.get_node(
		"StatsPanel/ResultEnergyTexture"
	) as TextureRect
	var energy_label: Label = result_screen.get_node(
		"StatsPanel/EnergyLabel"
	) as Label
	var replay_button: Button = result_screen.get_node(
		"ButtonsColumn/ReplayButton"
	) as Button
	var menu_button: Button = result_screen.get_node("ButtonsColumn/MenuButton") as Button
	_expect_true(
		is_equal_approx(backdrop.fish_position.x, 640.0),
		"The result fish must remain centered between the result controls."
	)
	_expect_true(success_animation.position.y < 260.0, "Success feedback must stay at the top.")
	_expect_true(
		success_animation.sprite_frames.get_frame_count(&"congrats") == 6,
		"Success feedback must use all six supplied congratulations frames."
	)
	_expect_true(stats_panel.position.x < 420.0, "Run totals must appear on the left.")
	_expect_true(buttons.position.x > 640.0, "Replay and menu actions must appear on the right.")
	_expect_true(
		achievements.position.x < 640.0 and achievements.position.y < 480.0,
		"New achievements must occupy the scrollable upper-left column."
	)
	_expect_true(
		achievement_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"Result achievement cards must use vertical scrolling only."
	)
	_expect_true(
		energy_texture.texture != null
		and energy_texture.texture.resource_path.ends_with("exp_button.png"),
		"Forage results must use the supplied EXP card."
	)
	_expect_true(energy_label.text == "14", "Forage results must show energy inside the EXP card.")
	_expect_true(cards.get_child_count() == 1, "Newly unlocked achievements must render dynamically.")
	_expect_true(
		cards.get_child(0) is AchievementCard,
		"Result unlocks must use the shared achievement-card layout."
	)
	_expect_true(
		is_equal_approx(
			replay_button.custom_minimum_size.y,
			menu_button.custom_minimum_size.y
		),
		"Result actions must retain matching heights."
	)
	_expect_true(
		not replay_button.has_focus() and not menu_button.has_focus(),
		"Result actions must not start yellow."
	)
	result_screen.queue_free()
	await get_tree().process_frame


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("HUD_RESULT_LAYOUT_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
