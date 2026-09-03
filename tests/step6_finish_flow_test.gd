extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveService.erase_section(AchievementService.SAVE_SECTION)
	AchievementService.reload_from_save()
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.run_finish_distance = 30.0
	test_config.wet_eye_duration = 120.0
	test_config.normal_energy_drain_per_second = 0.0
	test_config.boosted_energy_drain_per_second = 0.0
	gameplay.world_config = test_config
	get_tree().root.add_child(gameplay)
	get_tree().current_scene = gameplay
	var result_scene_path: String = await AppFlow.scene_changed
	_expect_string(result_scene_path, AppFlow.RESULT_SCENE, "Automatic endpoint should open the result scene.")
	for _frame: int in range(3):
		await get_tree().process_frame
		if get_tree().current_scene != null:
			break
	var result_screen: Node = get_tree().current_scene
	if result_screen == null:
		_fail("Result scene did not become current.")
		_finish()
		return
	var distance_label: Label = result_screen.get_node(
		"StatsPanel/DistanceLabel"
	) as Label
	var replay_button: Button = result_screen.get_node(
		"ButtonsColumn/ReplayButton"
	) as Button
	_expect_true(distance_label.text.begins_with("前进距离："), "Result scene should display the settled distance.")
	if AppFlow.last_run_result == null:
		_fail("AppFlow should retain the settled run result.")
	else:
		_expect_true(AppFlow.last_run_result.is_natural_finish(), "Automatic endpoint should be a natural finish.")
		_expect_equal(AppFlow.last_run_result.energy, 20, "Journey result should carry the initial energy when drain is disabled for this routing test.")
	replay_button.pressed.emit()
	for _frame: int in range(3):
		await get_tree().process_frame
		if get_tree().current_scene is GameplayRoot:
			break
	var replay_gameplay: GameplayRoot = get_tree().current_scene as GameplayRoot
	if replay_gameplay == null:
		_fail("Replay did not create GameplayRoot.")
		_finish()
		return
	var progress: RunProgressController = replay_gameplay.get_node("Systems/RunProgressController") as RunProgressController
	var forage: ForageModeController = replay_gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var wet_eye: WetEyeController = replay_gameplay.get_node("Systems/WetEyeController") as WetEyeController
	_expect_true(progress.get_travelled_distance() < 20.0, "Replay should reset run distance.")
	_expect_equal(forage.get_energy(), 20, "Replay should reset journey energy to twenty.")
	_expect_true(
		wet_eye.get_remaining_time() > wet_eye.get_maximum_time() - 0.1,
		"Replay should reset the wet-eye timer."
	)
	_finish()


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _expect_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_fail("%s Expected %d, received %d." % [message, expected, actual])


func _expect_string(actual: String, expected: String, message: String) -> void:
	if actual != expected:
		_fail("%s Expected '%s', received '%s'." % [message, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("STEP6_FINISH_FLOW_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
