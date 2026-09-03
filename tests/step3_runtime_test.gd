extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []
var _unit_timeout_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_same_frame_dive_priority()
	await _check_gameplay_integration()
	_finish()


func _check_same_frame_dive_priority() -> void:
	var controller: WetEyeController = WetEyeController.new()
	add_child(controller)
	controller.timed_out.connect(_on_unit_controller_timed_out)
	controller.configure(10.0, 3.0)
	controller.start(true)
	controller.set_process(false)
	controller.advance_time(10.0)
	_expect_true(controller.accept_dive(), "A valid dive should be accepted at the zero-time boundary.")
	await get_tree().process_frame
	_expect_equal(_unit_timeout_count, 0, "A same-frame valid dive must cancel the pending timeout.")
	_expect_float(controller.get_remaining_time(), 10.0, "A valid dive should refill the timer.")
	_expect_true(not controller.is_exposed(), "A valid dive should immediately pause exposure.")
	controller.set_exposed(true)
	controller.advance_time(10.0)
	await get_tree().process_frame
	_expect_equal(_unit_timeout_count, 1, "An unresolved zero timer should emit exactly one timeout.")
	_expect_true(controller.has_timed_out(), "The controller should retain its timed-out state.")
	controller.queue_free()
	await get_tree().process_frame


func _check_gameplay_integration() -> void:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_fail("Could not load GameplayRoot for step 3.")
		return
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	add_child(gameplay)
	await get_tree().process_frame
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	var wet_eye_controller: WetEyeController = gameplay.get_node("Systems/WetEyeController") as WetEyeController
	var player_fish: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var camera_rig: CameraRig = gameplay.get_node("World/CameraRig") as CameraRig
	var wet_eye_panel: PanelContainer = gameplay.get_node("Interface/HUD/WetEyePanel") as PanelContainer
	var warning_overlay: CenterContainer = gameplay.get_node(
		"Interface/HUD/WetEyePanel/WetEyeWarningOverlay"
	) as CenterContainer
	var mode_host: Node = gameplay.get_node("ModeHost")
	if (
		region_controller == null
		or wet_eye_controller == null
		or player_fish == null
		or camera_rig == null
		or wet_eye_panel == null
		or warning_overlay == null
		or mode_host == null
	):
		_fail("GameplayRoot is missing a required step 3 node.")
		return
	wet_eye_controller.set_process(false)
	_expect_true(
		gameplay.region_layout.is_wet_eye_exposed(RegionLayout.ViewProfile.FORAGE_SURFACE, 5),
		"Surface forage region 5 should be the exposed surface lane."
	)
	_expect_true(
		not gameplay.region_layout.is_wet_eye_exposed(RegionLayout.ViewProfile.FORAGE_DEEP, 5),
		"Deep forage region 5 should remain fully submerged."
	)
	_expect_true(wet_eye_controller.is_exposed(), "Forage should start exposed in surface region 5.")
	_expect_float(wet_eye_controller.get_maximum_time(), 10.0, "Wet-eye maximum time should be 10 seconds.")
	wet_eye_controller.advance_time(7.1)
	_expect_true(wet_eye_controller.is_warning_active(), "The last three seconds should activate a warning.")
	_expect_true(warning_overlay.visible, "The HUD warning mark should be visible in the last three seconds.")
	var before_invalid_rise: float = wet_eye_controller.get_remaining_time()
	await _press_region_action(&"move_up")
	_expect_float(
		wet_eye_controller.get_remaining_time(),
		before_invalid_rise,
		"W/Up at surface region 5 must not reset the wet-eye timer or change views."
	)
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 6, "The accepted dive should end in region 6.")
	_expect_float(wet_eye_controller.get_remaining_time(), 10.0, "Starting a valid dive should immediately refill the timer.")
	_expect_true(not wet_eye_controller.is_exposed(), "Region 6 should pause the wet-eye timer.")
	_expect_true(not warning_overlay.visible, "A valid dive should clear the warning immediately.")
	await _press_region_action(&"move_down")
	_expect_equal(
		camera_rig.get_current_profile(),
		RegionLayout.ViewProfile.FORAGE_DEEP,
		"The second S/Down at surface region 6 should enter the deep profile."
	)
	_expect_true(not wet_eye_controller.is_exposed(), "Deep forage should keep the timer paused.")
	_expect_true(not wet_eye_panel.visible, "The wet-eye HUD should be hidden during deep forage.")
	await _press_region_action(&"move_up")
	_expect_equal(region_controller.get_current_region(), 5, "Deep forage should be able to return to region 5.")
	_expect_true(not wet_eye_controller.is_exposed(), "Deep region 5 must not restart exposure.")
	await _press_region_action(&"move_up")
	_expect_equal(
		camera_rig.get_current_profile(),
		RegionLayout.ViewProfile.FORAGE_SURFACE,
		"The second W/Up at deep region 5 should return to the surface profile."
	)
	_expect_true(wet_eye_controller.is_exposed(), "Exposure should resume after the rising transition finishes.")
	_expect_true(wet_eye_panel.visible, "The wet-eye HUD should return with the surface profile.")
	wet_eye_controller.set_process(false)
	wet_eye_controller.advance_time(10.0)
	await get_tree().process_frame
	_expect_true(gameplay.is_failure_active(), "A dry-eye timeout should enter the unified failure state.")
	_expect_true(player_fish.is_death_animation_active(), "Failure should start the belly-up fish animation.")
	_expect_true(not player_fish.is_region_input_enabled(), "Failure should disable player region input.")
	_expect_equal(mode_host.process_mode, Node.PROCESS_MODE_DISABLED, "Failure should stop mode-specific encounter processing.")
	_expect_true(not wet_eye_controller.is_running(), "The timer should stop after failure begins.")


func _press_region_action(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().create_timer(0.6).timeout


func _on_unit_controller_timed_out() -> void:
	_unit_timeout_count += 1


func _expect_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_fail("%s Expected %d, received %d." % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s Expected %.3f, received %.3f." % [message, expected, actual])


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("STEP3_RUNTIME_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
