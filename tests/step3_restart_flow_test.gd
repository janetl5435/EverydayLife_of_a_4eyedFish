extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_fail("Could not load GameplayRoot for the restart flow test.")
		_finish()
		return
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.death_animation_duration = 0.0
	gameplay.world_config = test_config
	get_tree().root.add_child(gameplay)
	get_tree().current_scene = gameplay
	await get_tree().process_frame
	var wet_eye_controller: WetEyeController = gameplay.get_node("Systems/WetEyeController") as WetEyeController
	wet_eye_controller.set_process(false)
	wet_eye_controller.advance_time(10.0)
	var death_scene_path: String = await AppFlow.scene_changed
	_expect_string(death_scene_path, AppFlow.DEATH_SCENE, "Timeout should open the death/restart scene.")
	await get_tree().process_frame
	var death_screen: Node = get_tree().current_scene
	if death_screen == null:
		_fail("Death/restart scene did not become the current scene.")
		_finish()
		return
	var reason_label: Label = death_screen.get_node(
		"Center/Panel/Margin/Content/ReasonLabel"
	) as Label
	var failure_sequence: FullScreenSequence = death_screen.get_node(
		"FailureSequence"
	) as FullScreenSequence
	var restart_content: CenterContainer = death_screen.get_node("Center") as CenterContainer
	var backdrop: SeaBackdrop = death_screen.get_node("SeaBackdrop") as SeaBackdrop
	var dead_fish: PlayerFish = backdrop.get_node("World/DecorativeFish") as PlayerFish
	var retry_button: Button = death_screen.get_node(
		"Center/Panel/Margin/Content/RetryButton"
	) as Button
	var menu_button: Button = death_screen.get_node(
		"Center/Panel/Margin/Content/MenuButton"
	) as Button
	_expect_string(
		reason_label.text,
		AppFlow.get_failure_reason_label(AppFlow.FAILURE_DRY_EYES),
		"The death scene should report the dry-eye reason."
	)
	_expect_true(failure_sequence.get_frame_count() == 3, "Failure should use all three final frames.")
	_expect_true(not restart_content.visible, "Restart choices should wait until the failure sequence ends.")
	_expect_true(is_equal_approx(dead_fish.rotation, PI), "The restart screen fish must stay belly-up.")
	await failure_sequence.sequence_finished
	await get_tree().process_frame
	_expect_true(restart_content.visible, "Restart choices should appear after the failure sequence.")
	_expect_true(
		retry_button.size.x >= 480.0
		and is_equal_approx(retry_button.custom_minimum_size.y, 78.0)
		and is_equal_approx(menu_button.custom_minimum_size.y, 78.0),
		"Restart choices should use the main-menu button size."
	)
	_expect_true(
		not retry_button.has_focus() and not menu_button.has_focus(),
		"Restart choices must not start in the yellow highlighted state."
	)
	_emit_retry.call_deferred(retry_button)
	var retry_scene_path: String = await AppFlow.scene_changed
	_expect_string(retry_scene_path, AppFlow.GAMEPLAY_SCENE, "Retry should reopen the selected gameplay mode.")
	await get_tree().process_frame
	var retried_gameplay: GameplayRoot = get_tree().current_scene as GameplayRoot
	if retried_gameplay == null:
		_fail("Retry did not create a new GameplayRoot.")
		_finish()
		return
	var retried_wet_eye: WetEyeController = retried_gameplay.get_node(
		"Systems/WetEyeController"
	) as WetEyeController
	_expect_float(retried_wet_eye.get_maximum_time(), 10.0, "Retry should restore the 10-second maximum.")
	_expect_true(retried_wet_eye.get_remaining_time() > 9.8, "Retry should start with a full wet-eye timer.")
	_expect_true(retried_wet_eye.is_exposed(), "Forage retry should restart exposed in surface region 5.")
	_expect_string(
		String(AppFlow.last_failure_reason),
		String(AppFlow.FAILURE_UNKNOWN),
		"Retry should clear the previous failure reason."
	)
	_finish()


func _emit_retry(retry_button: Button) -> void:
	retry_button.pressed.emit()


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s Expected %.3f, received %.3f." % [message, expected, actual])


func _expect_string(actual: String, expected: String, message: String) -> void:
	if actual != expected:
		_fail("%s Expected '%s', received '%s'." % [message, expected, actual])


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("STEP3_RESTART_FLOW_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
