extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_transition_has_no_invulnerability()
	await _check_jump_has_no_invulnerability()
	await _check_eat_has_no_invulnerability()
	_finish()


func _check_transition_has_no_invulnerability() -> void:
	var gameplay: GameplayRoot = await _create_gameplay()
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	await _press_region_action(&"move_down", 0.15)
	_expect_equal(forage.get_state(), ForageModeController.State.SURFACE_FORAGE, "The first S/Down should only move from surface region 5 to 6.")
	await _press_region_action(&"move_down", 0.0)
	_expect_equal(forage.get_state(), ForageModeController.State.DIVING_TRANSITION, "The second S/Down should begin the view transition.")
	_expect_true(gameplay.begin_failure(AppFlow.FAILURE_DEBUG), "A view transition must not make the player invulnerable.")
	await get_tree().process_frame
	gameplay.queue_free()
	await get_tree().process_frame


func _check_jump_has_no_invulnerability() -> void:
	var gameplay: GameplayRoot = await _create_gameplay()
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	_expect_true(forage.begin_jump_charge(), "The surface fish should be able to charge a jump.")
	_expect_true(forage.set_jump_target(player.global_position + Vector2(300.0, -300.0)), "The test jump direction should be valid.")
	_expect_true(forage.release_jump_charge(), "The test jump should launch.")
	_expect_true(player.is_jump_active(), "The player should be airborne before the failure check.")
	_expect_true(gameplay.begin_failure(AppFlow.FAILURE_DEBUG), "An airborne jump must not make the player invulnerable.")
	await get_tree().process_frame
	gameplay.queue_free()
	await get_tree().process_frame


func _check_eat_has_no_invulnerability() -> void:
	var gameplay: GameplayRoot = await _create_gameplay()
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	await _press_region_action(&"move_down", 0.15)
	await _press_region_action(&"move_down", 0.15)
	_expect_equal(forage.get_state(), ForageModeController.State.DEEP_FORAGE, "The test fish should reach the underwater view.")
	_expect_true(not forage.request_interaction(), "Eating without a nearby target should award no food.")
	_expect_true(player.get_visual_animation_name() == &"eat", "The no-target F input should still enter the eat animation.")
	_expect_true(gameplay.begin_failure(AppFlow.FAILURE_DEBUG), "The eat animation must not make the player invulnerable.")
	await get_tree().process_frame
	gameplay.queue_free()
	await get_tree().process_frame


func _create_gameplay() -> GameplayRoot:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_failures.append("Could not load GameplayRoot for the unified journey test.")
		return null
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.camera_vertical_transition_duration = 0.05
	test_config.death_animation_duration = 5.0
	test_config.run_finish_distance = 100000.0
	test_config.normal_energy_drain_per_second = 0.0
	test_config.boosted_energy_drain_per_second = 0.0
	gameplay.world_config = test_config
	gameplay.route_scenes_after_settlement = false
	var opportunities: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	opportunities.first_opportunity_distance = 100000.0
	add_child(gameplay)
	await get_tree().process_frame
	return gameplay


func _press_region_action(action: StringName, settle_time: float) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().process_frame
	if settle_time > 0.0:
		await get_tree().create_timer(settle_time).timeout


func _expect_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_failures.append("%s Expected %d, received %d." % [message, expected, actual])


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UNIFIED_JOURNEY_STEP1_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
