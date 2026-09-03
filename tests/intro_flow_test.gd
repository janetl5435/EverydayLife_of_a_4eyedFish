extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var disposable_current_scene: Node = Node.new()
	get_tree().root.add_child(disposable_current_scene)
	get_tree().current_scene = disposable_current_scene
	AppFlow.open_intro.call_deferred()
	var intro_path: String = await AppFlow.scene_changed
	_expect_string(intro_path, AppFlow.INTRO_SCENE, "Bootstrap routing should open the intro scene.")
	var intro: Control
	for _frame: int in range(4):
		await get_tree().process_frame
		intro = get_tree().current_scene as Control
		if intro != null and intro.name == &"Intro":
			break
	if intro == null or intro.name != &"Intro":
		_failures.append("Intro did not become the current scene.")
		_finish()
		return
	var sequence: FullScreenSequence = intro.get_node("IntroSequence") as FullScreenSequence
	_expect_true(sequence.is_playing(), "Intro should start playing automatically.")
	var menu_path: String = await AppFlow.scene_changed
	_expect_string(menu_path, AppFlow.MAIN_MENU_SCENE, "The intro should automatically open the main menu.")
	await get_tree().process_frame
	_expect_true(
		get_tree().current_scene != null and get_tree().current_scene.name == &"MainMenu",
		"The intro transition should create the main menu scene."
	)
	AppFlow.open_intro.call_deferred()
	var replayed_intro_path: String = await AppFlow.scene_changed
	_expect_string(replayed_intro_path, AppFlow.INTRO_SCENE, "The intro should remain reusable.")
	for _frame: int in range(4):
		await get_tree().process_frame
		intro = get_tree().current_scene as Control
		if intro != null and intro.name == &"Intro":
			break
	if intro == null or intro.name != &"Intro":
		_failures.append("Replayed intro did not become the current scene.")
		_finish()
		return
	sequence = intro.get_node("IntroSequence") as FullScreenSequence
	sequence.skip_to_end.call_deferred()
	var skipped_menu_path: String = await AppFlow.scene_changed
	_expect_string(skipped_menu_path, AppFlow.MAIN_MENU_SCENE, "Skipping the intro should open the main menu.")
	_finish()


func _expect_string(actual: String, expected: String, message: String) -> void:
	if actual != expected:
		_failures.append("%s Expected '%s', received '%s'." % [message, expected, actual])


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("INTRO_FLOW_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
