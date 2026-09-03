extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"
const RESULT_SCENE_PATH: String = "res://scenes/ui/result_screen.tscn"
const COMPENDIUM_SCENE_PATH: String = "res://scenes/ui/compendium.tscn"

var _failures: Array[String] = []
var _unit_results: Array[RunResult] = []
var _natural_finish_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_saved_progress()
	_check_achievement_definition_contract()
	await _check_event_achievement_wiring()
	await _check_run_progress_guard_and_energy()
	await _check_automatic_finish_and_shutdown()
	_check_finish_energy_rules_and_boundaries()
	_check_settings_persistence_values()
	await _check_clean_run_instance()
	await _check_result_and_compendium_ui()
	_finish()


func _reset_saved_progress() -> void:
	SaveService.erase_section(AchievementService.SAVE_SECTION)
	SaveService.erase_section(SettingsService.SAVE_SECTION)
	AchievementService.reload_from_save()
	SettingsService.reload_from_save()


func _check_achievement_definition_contract() -> void:
	var expected: Array[Dictionary] = [
		{"id": &"extreme_dry_eye", "name": "极限干眼", "condition": "润眼倒计时进入最后1秒后成功下潜并存活"},
		{"id": &"survival_skill", "name": "生存之技", "condition": "鸟实际锁定后主动脱离警戒范围并存活"},
		{"id": &"delicious_shellfish", "name": "美味海贝", "condition": "在水下成功吃到一个贝类"},
		{"id": &"fish_spring", "name": "鱼形弹簧", "condition": "成功捕食一个空中昆虫"},
		{"id": &"fish_hungry", "name": "鱼好饿", "condition": "自然通关时最终能量不高于2"},
		{"id": &"fish_full", "name": "鱼好撑", "condition": "自然通关时最终能量高于30"},
		{"id": &"fish_gone", "name": "鱼已逝", "condition": "达到失败状态一次"},
	]
	var definitions: Array[AchievementDefinition] = AchievementService.get_definitions()
	_expect_equal(definitions.size(), expected.size(), "The compendium must contain exactly the seven planned entries.")
	for entry: Dictionary in expected:
		var definition: AchievementDefinition = AchievementService.get_definition(entry.id)
		_expect_true(definition != null, "Missing achievement definition: %s" % String(entry.id))
		if definition == null:
			continue
		_expect_string(definition.display_name, entry.name, "Achievement name must match the planning document.")
		_expect_string(definition.condition_text, entry.condition, "Achievement condition must match the planning document.")
		_expect_true(definition.icon != null, "Every planned achievement must use its supplied icon.")
	_expect_true(
		not AchievementService.qualifies_for_extreme_dry_eye(8.999),
		"Extreme dry eye must not unlock before nine seconds."
	)
	_expect_true(
		AchievementService.qualifies_for_extreme_dry_eye(9.0),
		"Extreme dry eye must unlock at nine seconds."
	)


func _check_event_achievement_wiring() -> void:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	var forage_gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var forage_config: WorldConfig = forage_gameplay.world_config.duplicate() as WorldConfig
	forage_config.run_finish_distance = 100000.0
	forage_gameplay.world_config = forage_config
	forage_gameplay.route_scenes_after_settlement = false
	add_child(forage_gameplay)
	await get_tree().process_frame
	var wet_eye: WetEyeController = forage_gameplay.get_node("Systems/WetEyeController") as WetEyeController
	var forage: ForageModeController = forage_gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	wet_eye.set_process(false)
	wet_eye.advance_time(9.0)
	forage_gameplay._on_region_motion_started(6)
	_expect_true(not AchievementService.is_unlocked(&"extreme_dry_eye"), "Extreme dry eye must wait for a successful completed dive.")
	forage_gameplay._on_forage_profile_changed(RegionLayout.ViewProfile.FORAGE_DEEP)
	forage_gameplay._on_forage_state_changed(ForageModeController.State.DEEP_FORAGE)
	forage.food_collected.emit(&"shellfish", 7)
	forage.food_collected.emit(&"insect", 10)
	_expect_true(AchievementService.is_unlocked(&"extreme_dry_eye"), "A qualified surface exposure followed by a successful dive should unlock 极限干眼.")
	_expect_true(AchievementService.is_unlocked(&"delicious_shellfish"), "Shellfish collection should unlock 美味海贝.")
	_expect_true(AchievementService.is_unlocked(&"fish_spring"), "Insect collection should unlock 鱼形弹簧.")
	var ecology: EcologyEventDirector = forage_gameplay.get_node("ModeHost/EcologyEventDirector") as EcologyEventDirector
	ecology.bird_evaded.emit(1)
	_expect_true(AchievementService.is_unlocked(&"survival_skill"), "Avoiding a bird should unlock 生存之技.")
	forage_gameplay.queue_free()
	await get_tree().process_frame


func _check_run_progress_guard_and_energy() -> void:
	_unit_results.clear()
	_natural_finish_count = 0
	var player: Node2D = Node2D.new()
	var controller: RunProgressController = RunProgressController.new()
	add_child(player)
	add_child(controller)
	player.global_position.x = 100.0
	controller.result_ready.connect(_on_unit_result_ready)
	controller.run_finished.connect(_on_natural_finish)
	_expect_true(
		controller.configure(player, AppFlow.GameMode.FORAGE, 100.0, 1000.0),
		"RunProgressController should accept a valid run."
	)
	controller.set_energy(14)
	_expect_true(controller.finish_naturally(), "The first natural finish should settle the run.")
	_expect_true(not controller.fail(AppFlow.FAILURE_DEBUG), "Failure cannot settle an already finished run.")
	_expect_true(not controller.abandon(), "Abandon cannot settle an already finished run.")
	_expect_equal(_unit_results.size(), 1, "A run result must only be emitted once.")
	_expect_equal(_natural_finish_count, 1, "The natural finish signal must only be emitted once.")
	if not _unit_results.is_empty():
		_expect_equal(_unit_results[0].energy, 14, "Forage energy must be carried into the result.")
		_expect_true(_unit_results[0].success, "A natural finish should be successful.")
	controller.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _check_automatic_finish_and_shutdown() -> void:
	_reset_saved_progress()
	AppFlow.current_mode = AppFlow.GameMode.PATROL
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.run_finish_distance = 30.0
	test_config.wet_eye_duration = 120.0
	gameplay.world_config = test_config
	gameplay.route_scenes_after_settlement = false
	add_child(gameplay)
	var progress: RunProgressController = gameplay.get_node("Systems/RunProgressController") as RunProgressController
	var finish_count: Array[int] = [0]
	progress.run_finished.connect(func(_result: RunResult) -> void: finish_count[0] += 1)
	for _frame: int in range(60):
		if progress.has_emitted_result():
			break
		await get_tree().physics_frame
	await get_tree().process_frame
	var result: RunResult = gameplay.get_settled_result()
	_expect_true(result != null and result.is_natural_finish(), "Crossing the configured distance should finish naturally.")
	_expect_equal(finish_count[0], 1, "The integrated endpoint must emit once.")
	await get_tree().create_timer(0.15).timeout
	_expect_equal(finish_count[0], 1, "The endpoint must remain settled on later frames.")
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var wet_eye: WetEyeController = gameplay.get_node("Systems/WetEyeController") as WetEyeController
	var encounters: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var hud_timer: Timer = gameplay.get_node("HudUpdateTimer") as Timer
	var mode_host: Node = gameplay.get_node("ModeHost")
	_expect_true(not player.is_physics_processing(), "Settlement must stop player movement immediately.")
	_expect_true(not wet_eye.is_running(), "Settlement must stop the wet-eye timer.")
	_expect_true(not encounters.is_enabled_for_patrol(), "Settlement must stop encounter generation.")
	_expect_true(not forage.is_enabled_for_forage(), "Settlement must stop forage generation and input.")
	_expect_true(hud_timer.is_stopped(), "Settlement must stop the HUD timer.")
	_expect_equal(mode_host.process_mode, Node.PROCESS_MODE_DISABLED, "Settlement must disable the mode host.")
	var hud: Control = gameplay.get_node("Interface/HUD") as Control
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect_true(viewport_rect.encloses(hud.get_global_rect()), "The full HUD must remain inside the viewport.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_finish_energy_rules_and_boundaries() -> void:
	SaveService.erase_section(AchievementService.SAVE_SECTION)
	AchievementService.reload_from_save()
	AchievementService.evaluate_run(_make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.NATURAL_FINISH, 2.0))
	_expect_true(AchievementService.is_unlocked(&"fish_hungry"), "Natural completion at energy 2 must unlock 鱼好饿.")
	_expect_true(not AchievementService.is_unlocked(&"fish_full"), "Low-energy completion must not unlock 鱼好撑.")
	AchievementService.reload_from_save()
	AchievementService.evaluate_run(_make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.NATURAL_FINISH, 2.001))
	_expect_true(not AchievementService.is_unlocked(&"fish_hungry"), "Energy above 2 must not unlock 鱼好饿.")
	AchievementService.evaluate_run(_make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.NATURAL_FINISH, 30.0))
	_expect_true(not AchievementService.is_unlocked(&"fish_full"), "Energy exactly 30 must not unlock 鱼好撑.")
	AchievementService.evaluate_run(_make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.NATURAL_FINISH, 30.001))
	_expect_true(AchievementService.is_unlocked(&"fish_full"), "Energy above 30 must unlock 鱼好撑.")
	AchievementService.evaluate_run(_make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.FAILURE, 0.0))
	_expect_true(AchievementService.is_unlocked(&"fish_gone"), "The first failed run should unlock 鱼已逝.")
	AchievementService.reload_from_save()
	AchievementService.evaluate_run(_make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.DEBUG_FINISH, 99.0))
	_expect_true(not AchievementService.is_unlocked(&"fish_full"), "Debug completion must not trigger natural-finish energy achievements.")
	var stored_unlocks: Variant = SaveService.get_value(
		AchievementService.SAVE_SECTION,
		AchievementService.SAVE_KEY_UNLOCKED,
		PackedStringArray()
	)
	_expect_true(
		stored_unlocks is PackedStringArray and stored_unlocks.is_empty(),
		"Achievement unlocks must remain session-only and never be written to user://."
	)
	_expect_equal(
		int(SaveService.get_value(AchievementService.SAVE_SECTION, AchievementService.SAVE_KEY_PATROL_STREAK, 0)),
		0,
		"Patrol streak must remain session-only and never be written to user://."
	)
	_expect_equal(
		int(SaveService.get_value(AchievementService.SAVE_SECTION, AchievementService.SAVE_KEY_FORAGE_STREAK, 0)),
		0,
		"Forage streak must remain session-only and never be written to user://."
	)


func _check_settings_persistence_values() -> void:
	SaveService.erase_section(SettingsService.SAVE_SECTION)
	SettingsService.reload_from_save()
	_expect_true(SettingsService.is_audio_enabled(), "Audio should default to enabled.")
	_expect_true(not SettingsService.is_fullscreen_enabled(), "Fullscreen should default to disabled.")
	SettingsService.set_audio_enabled(false)
	SettingsService.set_fullscreen_enabled(true)
	_expect_true(
		not bool(SaveService.get_value(SettingsService.SAVE_SECTION, SettingsService.SAVE_KEY_AUDIO, true)),
		"The audio switch must save under user://."
	)
	_expect_true(
		bool(SaveService.get_value(SettingsService.SAVE_SECTION, SettingsService.SAVE_KEY_FULLSCREEN, false)),
		"The fullscreen switch must save under user://."
	)
	SettingsService.set_audio_enabled(true)
	SettingsService.set_fullscreen_enabled(false)


func _check_clean_run_instance() -> void:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.run_finish_distance = 100000.0
	test_config.normal_energy_drain_per_second = 0.0
	test_config.boosted_energy_drain_per_second = 0.0
	gameplay.world_config = test_config
	gameplay.route_scenes_after_settlement = false
	add_child(gameplay)
	await get_tree().process_frame
	var progress: RunProgressController = gameplay.get_node("Systems/RunProgressController") as RunProgressController
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var opportunities: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	var wet_eye: WetEyeController = gameplay.get_node("Systems/WetEyeController") as WetEyeController
	_expect_true(progress.get_travelled_distance() < 20.0, "A fresh retry must start near zero distance.")
	_expect_equal(forage.get_energy(), 20, "A fresh retry must start at twenty energy.")
	_expect_equal(opportunities.get_active_foods().size(), 0, "A fresh retry must not retain food from the previous run.")
	_expect_true(
		wet_eye.get_remaining_time() > wet_eye.get_maximum_time() - 0.1,
		"A fresh retry must reset the wet-eye timer before normal frame time advances."
	)
	gameplay.queue_free()
	await get_tree().process_frame


func _check_result_and_compendium_ui() -> void:
	var result: RunResult = _make_result(AppFlow.GameMode.FORAGE, RunResult.Outcome.NATURAL_FINISH, 14)
	result.travelled_distance = 5000.0
	result.streak_count = 2
	result.add_new_unlock(AchievementService.ACHIEVEMENT_DELICIOUS_SHELLFISH)
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	AppFlow.store_run_result(result)
	var result_scene: PackedScene = load(RESULT_SCENE_PATH) as PackedScene
	var result_ui: Control = result_scene.instantiate() as Control
	add_child(result_ui)
	await get_tree().process_frame
	_expect_string(
		(result_ui.get_node("StatsPanel/DistanceLabel") as Label).text,
		"前进距离：5000 px",
		"Result UI must display distance."
	)
	_expect_string(
		(result_ui.get_node("StatsPanel/EnergyLabel") as Label).text,
		"14",
		"Result UI must display forage energy."
	)
	var new_cards: VBoxContainer = result_ui.get_node(
		"NewAchievementsArea/NewAchievementsScroll/NewAchievements"
	) as VBoxContainer
	_expect_equal(new_cards.get_child_count(), 1, "Result UI should stack newly unlocked achievement cards.")
	result_ui.queue_free()
	await get_tree().process_frame
	var compendium_scene: PackedScene = load(COMPENDIUM_SCENE_PATH) as PackedScene
	var compendium: Control = compendium_scene.instantiate() as Control
	add_child(compendium)
	await get_tree().process_frame
	var achievement_list: GridContainer = compendium.get_node(
		"RightColumn/Scroll/AchievementList"
	) as GridContainer
	_expect_equal(
		achievement_list.get_child_count(),
		7,
		"Compendium UI must render all seven planned entries."
	)
	compendium.queue_free()
	await get_tree().process_frame


func _make_result(mode: int, outcome: RunResult.Outcome, energy: float) -> RunResult:
	var result: RunResult = RunResult.new()
	result.mode = mode
	result.outcome = outcome
	result.energy = energy
	result.success = outcome == RunResult.Outcome.NATURAL_FINISH
	result.failure_reason = AppFlow.FAILURE_DEBUG if outcome == RunResult.Outcome.FAILURE else &""
	return result


func _on_unit_result_ready(result: RunResult) -> void:
	_unit_results.append(result)


func _on_natural_finish(_result: RunResult) -> void:
	_natural_finish_count += 1


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_failures.append("%s Expected %d, received %d." % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s Expected %.3f, received %.3f." % [message, expected, actual])


func _expect_string(actual: String, expected: String, message: String) -> void:
	if actual != expected:
		_failures.append("%s Expected '%s', received '%s'." % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("STEP6_RUNTIME_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
