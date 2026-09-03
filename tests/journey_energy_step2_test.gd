extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"
const WORLD_CONFIG_PATH: String = "res://data/world_config.tres"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	_check_default_config()
	await _check_energy_math_and_depletion()
	await _check_pause_transition_and_settlement_boundaries()
	_finish()


func _check_default_config() -> void:
	var config: WorldConfig = load(WORLD_CONFIG_PATH) as WorldConfig
	_expect_true(config != null, "The journey world configuration must load.")
	if config == null:
		return
	_expect_true(config.run_finish_distance > 0.0, "The user-tuned journey length must remain positive.")
	_expect_float(config.speed_boost_multiplier, 2.0, "Shift acceleration must use a 2x speed multiplier.")
	_expect_float(config.initial_energy, 20.0, "A journey must start with twenty energy.")
	_expect_float(config.normal_energy_drain_per_second, 1.0, "Normal travel must drain one energy per second.")
	_expect_float(config.boosted_energy_drain_per_second, 2.5, "Accelerated travel must drain 2.5 energy per second.")


func _check_energy_math_and_depletion() -> void:
	var gameplay: GameplayRoot = await _create_gameplay(10.0, 1.0, 2.5, 0.05)
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var energy_label: Label = gameplay.get_node("Interface/HUD/EnergyPanel/Margin/Content/EnergyLabel") as Label
	forage.set_process(false)
	_expect_float(forage.get_energy(), 10.0, "Energy must initialize to ten.")
	_expect_true(energy_label.text == "能量：10", "The HUD must initially show ten energy.")
	forage.advance_energy(0.4)
	_expect_float(forage.get_energy(), 9.6, "Normal drain must retain an exact fractional value internally.")
	_expect_true(energy_label.text == "能量：9", "The HUD must floor fractional energy for display.")
	forage.advance_energy(1.6)
	_expect_float(forage.get_energy(), 8.0, "Two normal seconds in total must consume two energy.")
	Input.action_press(&"accelerate")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_true(player.is_speed_boost_active(), "The player must be in the accelerated state for the boosted drain check.")
	forage.advance_energy(2.0)
	_expect_float(forage.get_energy(), 3.0, "Two accelerated seconds must consume five energy.")
	Input.action_release(&"accelerate")
	await get_tree().physics_frame
	await get_tree().process_frame
	forage.advance_energy(3.0)
	_expect_float(forage.get_energy(), 0.0, "Energy must clamp to zero instead of becoming negative.")
	var result: RunResult = gameplay.get_settled_result()
	_expect_true(result != null and result.is_failure(), "Zero energy must settle the journey as a failure.")
	if result != null:
		_expect_true(result.failure_reason == AppFlow.FAILURE_ENERGY, "Energy depletion must use the dedicated failure reason.")
		_expect_float(result.energy, 0.0, "The failure result must retain the exact final energy.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_pause_transition_and_settlement_boundaries() -> void:
	var gameplay: GameplayRoot = await _create_gameplay(100.0, 10.0, 25.0, 0.5)
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var pause_menu: PauseMenu = gameplay.get_node("Interface/PauseMenu") as PauseMenu
	var progress: RunProgressController = gameplay.get_node("Systems/RunProgressController") as RunProgressController
	pause_menu.open_menu()
	var paused_energy: float = forage.get_energy()
	await get_tree().create_timer(0.2).timeout
	_expect_float(forage.get_energy(), paused_energy, "Pausing must stop energy consumption.", 0.001)
	pause_menu.close_menu()
	await get_tree().create_timer(0.2).timeout
	_expect_true(forage.get_energy() < paused_energy - 1.0, "Energy consumption must resume after unpausing.")
	await _press_region_action(&"move_down", 0.15)
	await _press_region_action(&"move_down", 0.0)
	_expect_equal(forage.get_state(), ForageModeController.State.DIVING_TRANSITION, "The second S/Down must start a camera transition.")
	var transition_energy: float = forage.get_energy()
	await get_tree().create_timer(0.2).timeout
	_expect_true(forage.get_energy() < transition_energy - 1.0, "Camera transitions must continue consuming energy.")
	_expect_true(progress.finish_for_debug(), "The test settlement must finish the active journey.")
	var settled_energy: float = forage.get_energy()
	await get_tree().create_timer(0.2).timeout
	_expect_float(forage.get_energy(), settled_energy, "Settlement must stop energy consumption.", 0.001)
	gameplay.queue_free()
	await get_tree().process_frame


func _create_gameplay(
	initial_energy: float,
	normal_drain: float,
	boosted_drain: float,
	transition_duration: float
) -> GameplayRoot:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_failures.append("Could not load GameplayRoot for the Step 2 energy test.")
		return null
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.initial_energy = initial_energy
	test_config.normal_energy_drain_per_second = normal_drain
	test_config.boosted_energy_drain_per_second = boosted_drain
	test_config.run_finish_distance = 100000.0
	test_config.wet_eye_duration = 120.0
	test_config.camera_vertical_transition_duration = transition_duration
	test_config.death_animation_duration = 5.0
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


func _expect_float(
	actual: float,
	expected: float,
	message: String,
	tolerance: float = 0.01
) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s Expected %.3f, received %.3f." % [message, expected, actual])


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("JOURNEY_ENERGY_STEP2_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
