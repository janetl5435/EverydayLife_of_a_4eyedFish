extends Node

const INTRO_SCENE_PATH: String = "res://scenes/ui/intro.tscn"
const DEATH_SCENE_PATH: String = "res://scenes/ui/death_restart.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_intro_layout()
	await _check_death_restart_layout()
	_finish()


func _check_intro_layout() -> void:
	var intro_scene: PackedScene = load(INTRO_SCENE_PATH) as PackedScene
	var intro: Control = intro_scene.instantiate() as Control
	intro.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(intro)
	await get_tree().process_frame
	var sequence: FullScreenSequence = intro.get_node("IntroSequence") as FullScreenSequence
	var frame_view: TextureRect = sequence.get_node("FrameView") as TextureRect
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect_true(sequence.get_frame_count() == 8, "Intro must use all eight final frames.")
	_expect_true(frame_view.texture != null, "Intro must display its first frame immediately.")
	_expect_true(viewport_rect.encloses(sequence.get_global_rect()), "Intro frames must cover the viewport.")
	_expect_true(intro.find_child("ContinueButton", true, false) == null, "Intro must not retain the old continue panel.")
	intro.queue_free()
	await get_tree().process_frame


func _check_death_restart_layout() -> void:
	var result: RunResult = RunResult.new()
	result.mode = AppFlow.GameMode.FORAGE
	result.outcome = RunResult.Outcome.FAILURE
	result.failure_reason = AppFlow.FAILURE_DRY_EYES
	result.travelled_distance = 750.0
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	AppFlow.store_run_result(result)
	var death_scene: PackedScene = load(DEATH_SCENE_PATH) as PackedScene
	var death: Control = death_scene.instantiate() as Control
	death.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(death)
	await get_tree().process_frame
	var sequence: FullScreenSequence = death.get_node("FailureSequence") as FullScreenSequence
	var center: CenterContainer = death.get_node("Center") as CenterContainer
	var panel: PanelContainer = death.get_node("Center/Panel") as PanelContainer
	var backdrop: SeaBackdrop = death.get_node("SeaBackdrop") as SeaBackdrop
	var dead_fish: PlayerFish = backdrop.get_node("World/DecorativeFish") as PlayerFish
	var retry_button: Button = death.get_node(
		"Center/Panel/Margin/Content/RetryButton"
	) as Button
	var menu_button: Button = death.get_node(
		"Center/Panel/Margin/Content/MenuButton"
	) as Button
	_expect_true(sequence.get_frame_count() == 3, "Failure must use all three final frames.")
	_expect_true(is_equal_approx(dead_fish.rotation, PI), "The restart fish must remain belly-up and still.")
	_expect_true(center.position.x > 640.0, "Restart choices must stay on the right like the main menu.")
	for hidden_name: String in ["Title", "ModeLabel", "ReasonLabel", "DistanceLabel", "StreakLabel"]:
		var hidden_label: Label = death.get_node(
			"Center/Panel/Margin/Content/%s" % hidden_name
		) as Label
		_expect_true(not hidden_label.visible, "Restart should only display its two planned choices.")
	_expect_true(
		panel.custom_minimum_size.x >= 480.0
		and is_equal_approx(retry_button.custom_minimum_size.y, 150.0)
		and is_equal_approx(menu_button.custom_minimum_size.y, 150.0),
		"Restart choices must match the main-menu button size."
	)
	death.queue_free()
	await get_tree().process_frame


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FAILURE_INTRO_LAYOUT_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
