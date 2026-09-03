extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_fail("Could not load GameplayRoot.")
		_finish()
		return
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	add_child(gameplay)
	await get_tree().process_frame
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	var player_fish: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var camera_rig: CameraRig = gameplay.get_node("World/CameraRig") as CameraRig
	var background: LoopingSeaBackground = gameplay.get_node("World/LoopingSeaBackground") as LoopingSeaBackground
	if region_controller == null or player_fish == null or camera_rig == null or background == null:
		_fail("GameplayRoot is missing a required step 2 node.")
		_finish()
		return
	var layout: RegionLayout = gameplay.region_layout
	_expect_true(layout.is_valid(), "Region layout should be valid.")
	_expect_equal(region_controller.get_current_region(), 5, "Forage should start in water region 5.")
	_expect_equal(region_controller.get_min_region(), 5, "Surface swimming minimum should be region 5.")
	_expect_equal(region_controller.get_max_region(), 6, "Surface swimming maximum should be region 6.")
	_expect_equal(
		layout.get_camera_min_region(RegionLayout.ViewProfile.FORAGE_SURFACE),
		1,
		"Surface camera minimum should be region 1."
	)
	_expect_equal(
		layout.get_camera_max_region(RegionLayout.ViewProfile.FORAGE_SURFACE),
		6,
		"Surface camera maximum should be region 6."
	)
	_expect_equal(
		camera_rig.get_current_profile(),
		RegionLayout.ViewProfile.FORAGE_SURFACE,
		"Forage should start with the surface camera."
	)
	var display_size: Vector2 = background.get_display_size()
	if not is_equal_approx(display_size.x, 3072.0) or not is_equal_approx(display_size.y, 1104.0):
		_fail("Unexpected displayed map size: %s" % display_size)
	_expect_float(layout.get_region_bottom_y(4), 435.6, "Region 4 bottom should be the water surface.")
	_expect_float(layout.get_region_bottom_y(8), 948.0, "Region 8 bottom should be the soil surface.")
	_expect_float(layout.get_region_bottom_y(9), 1066.5, "Region 9 should end above the map bottom.")
	_expect_float(
		layout.get_unassigned_bottom_height(display_size.y),
		37.5,
		"The bottom sediment strip should remain outside all regions."
	)
	_expect_true(player_fish.is_fully_inside_current_region(), "Fish should start fully inside region 5.")
	_expect_float(gameplay.world_config.speed_boost_multiplier, 2.0, "The global Shift speed multiplier should be 2.0.")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_float(player_fish.velocity.x, 180.0, "Normal forward velocity should use the configured 180 px/s speed.")
	Input.action_press(&"accelerate")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_true(player_fish.is_speed_boost_active(), "Holding Shift should activate the global speed boost.")
	_expect_float(player_fish.get_current_forward_speed(), 360.0, "Shift should multiply the 180 px/s forward speed by 2.0.")
	_expect_float(player_fish.velocity.x, 360.0, "Holding Shift should apply the 2.0 multiplier to actual horizontal velocity.")
	_expect_float(
		camera_rig.global_position.x - player_fish.global_position.x,
		gameplay.world_config.camera_horizontal_look_ahead,
		"The camera should preserve its horizontal offset while the fish accelerates."
	)
	Input.action_release(&"accelerate")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_true(not player_fish.is_speed_boost_active(), "Releasing Shift should stop the speed boost.")
	_expect_float(player_fish.get_current_forward_speed(), 180.0, "Releasing Shift should restore normal forward speed.")
	var start_x: float = player_fish.global_position.x
	await _press_region_action(&"move_up")
	_expect_equal(region_controller.get_current_region(), 5, "Surface swimming cannot enter sky region 4.")
	_expect_true(player_fish.is_fully_inside_current_region(), "Fish should remain fully inside region 5.")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 6, "Downward movement should end in water region 6.")
	_expect_true(player_fish.is_fully_inside_current_region(), "Fish should fit fully inside region 6.")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 6, "The second S/Down at surface region 6 must keep the same global region while diving.")
	_expect_equal(region_controller.get_min_region(), 5, "Deep swimming minimum should remain region 5.")
	_expect_equal(region_controller.get_max_region(), 8, "Deep swimming maximum should be region 8.")
	_expect_equal(
		layout.get_camera_min_region(RegionLayout.ViewProfile.FORAGE_DEEP),
		4,
		"Deep camera minimum should be region 4."
	)
	_expect_equal(
		layout.get_camera_max_region(RegionLayout.ViewProfile.FORAGE_DEEP),
		9,
		"Deep camera maximum should be region 9."
	)
	_expect_equal(
		camera_rig.get_current_profile(),
		RegionLayout.ViewProfile.FORAGE_DEEP,
		"The second S/Down at surface region 6 should select the deep camera."
	)
	_expect_true(player_fish.is_fully_inside_current_region(), "Depth switching should not move the fish out of region 6.")
	await _press_region_action(&"move_up")
	_expect_equal(region_controller.get_current_region(), 5, "Upward move should return to region 5.")
	await _press_region_action(&"move_up")
	_expect_equal(region_controller.get_min_region(), 5, "Surface swimming minimum should be restored.")
	_expect_equal(region_controller.get_max_region(), 6, "Surface swimming maximum should be restored.")
	_expect_equal(
		camera_rig.get_current_profile(),
		RegionLayout.ViewProfile.FORAGE_SURFACE,
		"The second W/Up at deep region 5 should return to the surface camera."
	)
	if player_fish.global_position.x <= start_x:
		_fail("Player did not move forward in world coordinates.")
	var map_a: Sprite2D = background.get_node("MapA") as Sprite2D
	var map_b: Sprite2D = background.get_node("MapB") as Sprite2D
	player_fish.global_position.x = 4000.0
	await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
	var rightmost_panel_x: float = maxf(map_a.position.x, map_b.position.x)
	if rightmost_panel_x < 6144.0:
		_fail("The passed map panel was not recycled to the right.")
	gameplay.queue_free()
	await get_tree().process_frame
	await _check_patrol_profile(gameplay_scene)
	_finish()


func _press_region_action(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().create_timer(0.6).timeout


func _check_patrol_profile(gameplay_scene: PackedScene) -> void:
	AppFlow.current_mode = AppFlow.GameMode.PATROL
	var patrol_gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	add_child(patrol_gameplay)
	await get_tree().process_frame
	var region_controller: RegionController = patrol_gameplay.get_node("Systems/RegionController") as RegionController
	var player_fish: PlayerFish = patrol_gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var camera_rig: CameraRig = patrol_gameplay.get_node("World/CameraRig") as CameraRig
	var layout: RegionLayout = patrol_gameplay.region_layout
	_expect_equal(region_controller.get_current_region(), 5, "Patrol should start in water region 5.")
	_expect_equal(region_controller.get_min_region(), 5, "Patrol swimming minimum should be region 5.")
	_expect_equal(region_controller.get_max_region(), 7, "Patrol swimming maximum should be region 7.")
	_expect_equal(
		layout.get_camera_min_region(RegionLayout.ViewProfile.PATROL),
		2,
		"Patrol camera minimum should be region 2."
	)
	_expect_equal(
		layout.get_camera_max_region(RegionLayout.ViewProfile.PATROL),
		7,
		"Patrol camera maximum should be region 7."
	)
	_expect_equal(
		camera_rig.get_current_profile(),
		RegionLayout.ViewProfile.PATROL,
		"Patrol should use the global region 2–7 camera."
	)
	_expect_true(player_fish.is_fully_inside_current_region(), "Patrol fish should start fully inside region 5.")
	await _press_region_action(&"move_up")
	_expect_equal(region_controller.get_current_region(), 5, "Patrol cannot swim into sky region 4.")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 7, "Patrol should be able to reach water region 7.")
	_expect_true(player_fish.is_fully_inside_current_region(), "Patrol fish should fit fully inside region 7.")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 7, "Patrol cannot enter water region 8.")
	patrol_gameplay.queue_free()
	await get_tree().process_frame


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
		print("STEP2_RUNTIME_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
