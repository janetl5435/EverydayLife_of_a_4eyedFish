class_name GameplayRoot extends Node2D

signal failure_started(reason: StringName)

enum RunState {
	RUNNING,
	CAPTURED,
	FAILING,
	FINISHED,
}

@export var region_layout: RegionLayout
@export var world_config: WorldConfig
@export_group("Testing")
@export var route_scenes_after_settlement: bool = true

@onready var looping_background: LoopingSeaBackground = %LoopingSeaBackground
@onready var player_fish: PlayerFish = %PlayerFish
@onready var camera_rig: CameraRig = %CameraRig
@onready var region_guide: RegionGuide = %RegionGuide
@onready var region_controller: RegionController = %RegionController
@onready var wet_eye_controller: WetEyeController = %WetEyeController
@onready var run_progress_controller: RunProgressController = %RunProgressController
@onready var mode_host: Node = %ModeHost
@onready var active_threats: Node2D = %ActiveThreats
@onready var threat_pool: ThreatPool = %ThreatPool
@onready var encounter_director: EncounterDirector = %EncounterDirector
@onready var ecology_event_director: EcologyEventDirector = %EcologyEventDirector
@onready var forage_mode_controller: ForageModeController = %ForageModeController
@onready var air_foods: Node2D = %AirFoods
@onready var underwater_foods: Node2D = %UnderwaterFoods
@onready var mode_label: Label = %ModeLabel
@onready var view_label: Label = %ViewLabel
@onready var region_label: Label = %RegionLabel
@onready var distance_label: Label = %DistanceLabel
@onready var energy_panel: PanelContainer = %EnergyPanel
@onready var energy_label: Label = %EnergyLabel
@onready var action_hint_label: Label = %ActionHintLabel
@onready var interaction_prompt_panel: PanelContainer = %InteractionPromptPanel
@onready var interaction_prompt_label: Label = %InteractionPromptLabel
@onready var wet_eye_panel: PanelContainer = %WetEyePanel
@onready var wet_eye_progress: ProgressBar = %WetEyeProgress
@onready var wet_eye_time_label: Label = %WetEyeTimeLabel
@onready var wet_eye_status_label: Label = %WetEyeStatusLabel
@onready var wet_eye_warning_overlay: CenterContainer = %WetEyeWarningOverlay
@onready var wet_eye_warning_icon: TextureRect = %WetEyeWarningIcon
@onready var encounter_warning_panel: PanelContainer = %EncounterWarningPanel
@onready var encounter_warning_title: Label = %EncounterWarningTitle
@onready var encounter_warning_time: Label = %EncounterWarningTime
@onready var encounter_warning_detail: Label = %EncounterWarningDetail
@onready var complete_test_button: Button = %CompleteTestButton
@onready var fail_test_button: Button = %FailTestButton
@onready var menu_button: Button = %MenuButton
@onready var hud_update_timer: Timer = %HudUpdateTimer
@onready var pause_menu: PauseMenu = %PauseMenu

var _selected_mode: AppFlow.GameMode = AppFlow.GameMode.FORAGE
var _current_profile: RegionLayout.ViewProfile = RegionLayout.ViewProfile.FORAGE_SURFACE
var _depth_transition_active: bool = false
var _run_state: RunState = RunState.RUNNING
var _failure_reason: StringName = AppFlow.FAILURE_UNKNOWN
var _settled_result: RunResult
var _warning_tween: Tween
var _pending_extreme_dry_eye: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if region_layout == null or world_config == null:
		push_error("GameplayRoot requires region_layout and world_config resources.")
		return
	_selected_mode = AppFlow.current_mode
	if _selected_mode == AppFlow.GameMode.NONE:
		_selected_mode = AppFlow.GameMode.FORAGE
		AppFlow.current_mode = _selected_mode
	_current_profile = (
		RegionLayout.ViewProfile.FORAGE_SURFACE
		if _selected_mode == AppFlow.GameMode.FORAGE
		else RegionLayout.ViewProfile.PATROL
	)
	var min_region: int = region_layout.get_swim_min_region(_current_profile)
	var max_region: int = region_layout.get_swim_max_region(_current_profile)
	var start_region: int = region_layout.get_swim_start_region(_current_profile)
	if not region_controller.configure(region_layout, min_region, max_region, start_region):
		return
	looping_background.configure(world_config)
	var map_display_size: Vector2 = looping_background.get_display_size()
	player_fish.configure(region_controller, region_layout, world_config)
	camera_rig.configure(
		player_fish,
		region_layout,
		world_config,
		map_display_size.y,
		_current_profile
	)
	looping_background.track_camera(camera_rig.get_camera())
	region_guide.configure(
		region_layout,
		camera_rig.get_camera(),
		_current_profile,
		map_display_size.y
	)
	run_progress_controller.result_ready.connect(_on_run_result_ready)
	if not run_progress_controller.configure(
		player_fish,
		_selected_mode,
		player_fish.global_position.x,
		world_config.run_finish_distance
	):
		return
	region_controller.region_changed.connect(_on_region_changed)
	region_controller.bounds_changed.connect(_on_region_bounds_changed)
	player_fish.region_motion_started.connect(_on_region_motion_started)
	player_fish.region_boundary_requested.connect(_on_region_boundary_requested)
	player_fish.jump_started.connect(_on_player_jump_started)
	player_fish.death_animation_finished.connect(_on_player_death_animation_finished)
	camera_rig.view_transition_started.connect(_on_view_transition_started)
	camera_rig.view_transition_finished.connect(_on_view_transition_finished)
	wet_eye_controller.remaining_time_changed.connect(_on_wet_eye_remaining_time_changed)
	wet_eye_controller.warning_started.connect(_on_wet_eye_warning_started)
	wet_eye_controller.warning_ended.connect(_on_wet_eye_warning_ended)
	wet_eye_controller.dive_accepted.connect(_on_wet_eye_dive_accepted)
	wet_eye_controller.exposed_changed.connect(_on_wet_eye_exposed_changed)
	wet_eye_controller.timed_out.connect(_on_wet_eye_timed_out)
	complete_test_button.pressed.connect(_on_complete_test_pressed)
	fail_test_button.pressed.connect(_on_fail_test_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	hud_update_timer.timeout.connect(_on_hud_update_timer_timeout)
	pause_menu.abandon_requested.connect(_on_pause_abandon_requested)
	wet_eye_controller.configure(
		world_config.wet_eye_duration,
		world_config.wet_eye_warning_duration
	)
	wet_eye_controller.start(
		region_layout.is_wet_eye_exposed(
			_current_profile,
			region_controller.get_current_region()
		)
	)
	threat_pool.configure(active_threats)
	threat_pool.threat_bite_started.connect(_on_threat_bite_started)
	encounter_director.configure(
		self,
		player_fish,
		region_controller,
		region_layout,
		world_config.region_move_duration,
		camera_rig.get_camera(),
		threat_pool,
		encounter_warning_panel,
		encounter_warning_title,
		encounter_warning_time,
		encounter_warning_detail,
		_selected_mode == AppFlow.GameMode.PATROL
	)
	encounter_director.bird_evaded.connect(_on_bird_evaded)
	encounter_director.warning_started.connect(_on_encounter_warning_started)
	encounter_director.warning_cancelled.connect(_on_encounter_warning_cancelled)
	encounter_director.capture_started.connect(_on_encounter_capture_started)
	ecology_event_director.bird_evaded.connect(_on_ecology_bird_evaded)
	ecology_event_director.warning_started.connect(_on_ecology_warning_started)
	ecology_event_director.warning_cancelled.connect(_on_ecology_warning_cancelled)
	ecology_event_director.capture_started.connect(_on_ecology_capture_started)
	forage_mode_controller.profile_changed.connect(_on_forage_profile_changed)
	forage_mode_controller.state_changed.connect(_on_forage_state_changed)
	forage_mode_controller.energy_changed.connect(_on_forage_energy_changed)
	forage_mode_controller.energy_depleted.connect(_on_forage_energy_depleted)
	forage_mode_controller.food_collected.connect(_on_forage_food_collected)
	forage_mode_controller.interaction_attempted.connect(_on_forage_interaction_attempted)
	forage_mode_controller.action_hint_changed.connect(_on_forage_action_hint_changed)
	forage_mode_controller.interaction_prompt_changed.connect(_on_interaction_prompt_changed)
	if not forage_mode_controller.configure(
		player_fish,
		region_controller,
		region_layout,
		camera_rig,
		region_guide,
		wet_eye_controller,
		air_foods,
		underwater_foods,
		world_config.initial_energy,
		world_config.normal_energy_drain_per_second,
		world_config.boosted_energy_drain_per_second,
		_selected_mode == AppFlow.GameMode.FORAGE
	):
		push_error("GameplayRoot could not configure forage mode.")
		return
	if not ecology_event_director.configure(
		self,
		player_fish,
		region_controller,
		region_layout,
		camera_rig.get_camera(),
		threat_pool,
		forage_mode_controller.opportunity_director,
		encounter_warning_panel,
		encounter_warning_title,
		encounter_warning_time,
		encounter_warning_detail,
		player_fish.global_position.x,
		world_config.run_finish_distance,
		_current_profile,
		_selected_mode == AppFlow.GameMode.FORAGE
	):
		push_error("GameplayRoot could not configure unified ecology events.")
		return
	_update_all_hud()


func _unhandled_input(event: InputEvent) -> void:
	if _run_state != RunState.RUNNING:
		return
	if event.is_action_pressed(&"pause", false):
		pause_menu.open_menu()
		get_viewport().set_input_as_handled()
		return
	if (
		_selected_mode == AppFlow.GameMode.FORAGE
		and forage_mode_controller.handle_unhandled_input(event)
	):
		get_viewport().set_input_as_handled()


func request_depth_switch() -> void:
	if _selected_mode != AppFlow.GameMode.FORAGE:
		return
	forage_mode_controller.request_depth_switch()


func _update_all_hud() -> void:
	mode_label.text = AppFlow.get_current_mode_label()
	_update_view_hud()
	_update_region_hud()
	_update_distance_hud()
	_update_energy_hud(forage_mode_controller.get_energy())
	_update_wet_eye_hud(
		wet_eye_controller.get_remaining_time(),
		wet_eye_controller.get_maximum_time()
	)
	_update_wet_eye_panel_visibility()
	_update_default_action_hint()


func _update_view_hud() -> void:
	view_label.text = "%s　可游范围：%d–%d" % [
		region_layout.get_profile_label(_current_profile),
		region_layout.get_swim_min_region(_current_profile),
		region_layout.get_swim_max_region(_current_profile),
	]


func _update_region_hud() -> void:
	region_label.text = "当前水下泳道：全局区域%d　普通游动范围：%d–%d" % [
		region_controller.get_current_region(),
		region_controller.get_min_region(),
		region_controller.get_max_region(),
	]


func _update_distance_hud() -> void:
	var travelled: float = run_progress_controller.get_travelled_distance()
	var finish_distance: float = run_progress_controller.get_finish_distance()
	distance_label.text = "旅程：%d / %d px\n剩余：%d px" % [
		roundi(travelled),
		roundi(finish_distance),
		roundi(maxf(finish_distance - travelled, 0.0)),
	]


func _update_energy_hud(energy: float) -> void:
	energy_panel.visible = _selected_mode == AppFlow.GameMode.FORAGE
	energy_label.text = "能量：%d" % floori(maxf(energy, 0.0))


func _update_default_action_hint() -> void:
	if _run_state != RunState.RUNNING:
		return
	if _selected_mode == AppFlow.GameMode.PATROL:
		action_hint_label.text = "W/↑、S/↓ 离开攻击视野　Shift 加速"
	elif _current_profile == RegionLayout.ViewProfile.FORAGE_SURFACE:
		action_hint_label.text = "空格＋鼠标起跳　F吃水面虾　区域5按S进入6，再按S下潜　Shift加速"
	else:
		action_hint_label.text = "F 进食　区域6按W进入5，再按W上浮　Shift 加速"


func _on_region_changed(current_region: int, _previous_region: int) -> void:
	if _run_state == RunState.RUNNING:
		wet_eye_controller.set_exposed(
			region_layout.is_wet_eye_exposed(_current_profile, current_region)
		)
	_update_region_hud()
	_update_default_action_hint()


func _on_region_bounds_changed(_min_region: int, _max_region: int) -> void:
	_update_region_hud()


func _on_region_boundary_requested(direction: int, current_region: int) -> void:
	if _run_state != RunState.RUNNING or _selected_mode != AppFlow.GameMode.FORAGE:
		return
	var requests_dive: bool = (
		direction > 0
		and current_region == 6
		and forage_mode_controller.get_state() == ForageModeController.State.SURFACE_FORAGE
	)
	var requests_rise: bool = (
		direction < 0
		and current_region == 5
		and forage_mode_controller.get_state() == ForageModeController.State.DEEP_FORAGE
	)
	if requests_dive or requests_rise:
		request_depth_switch()


func _on_view_transition_started(_profile: RegionLayout.ViewProfile) -> void:
	_depth_transition_active = true
	action_hint_label.text = "相机切换中……"
	_update_wet_eye_panel_visibility()


func _on_view_transition_finished(_profile: RegionLayout.ViewProfile) -> void:
	_depth_transition_active = false
	if _run_state == RunState.RUNNING and _selected_mode != AppFlow.GameMode.FORAGE:
		player_fish.set_region_input_enabled(true)
		wet_eye_controller.set_exposed(
			region_layout.is_wet_eye_exposed(
				_current_profile,
				region_controller.get_current_region()
			)
		)
	_update_view_hud()
	_update_wet_eye_panel_visibility()
	_update_default_action_hint()


func _on_hud_update_timer_timeout() -> void:
	_update_distance_hud()


func _on_forage_profile_changed(profile: RegionLayout.ViewProfile) -> void:
	_current_profile = profile
	ecology_event_director.set_player_view_profile(profile)
	_update_view_hud()
	_update_wet_eye_panel_visibility()


func _on_forage_state_changed(state: ForageModeController.State) -> void:
	_depth_transition_active = (
		state == ForageModeController.State.DIVING_TRANSITION
		or state == ForageModeController.State.RISING_TRANSITION
	)
	if (
		state == ForageModeController.State.DEEP_FORAGE
		and _pending_extreme_dry_eye
		and _run_state == RunState.RUNNING
	):
		_pending_extreme_dry_eye = false
		_record_achievement(AchievementService.ACHIEVEMENT_EXTREME_DRY_EYE)
	_update_wet_eye_panel_visibility()


func _on_forage_energy_changed(energy: float) -> void:
	run_progress_controller.set_energy(energy)
	_update_energy_hud(energy)


func _on_forage_energy_depleted() -> void:
	begin_failure(AppFlow.FAILURE_ENERGY)


func _on_forage_food_collected(food_id: StringName, _energy_value: int) -> void:
	AudioService.play_energy_gain()
	if food_id == &"shellfish" and _current_profile == RegionLayout.ViewProfile.FORAGE_DEEP:
		_record_achievement(AchievementService.ACHIEVEMENT_DELICIOUS_SHELLFISH)
	elif food_id == &"insect":
		_record_achievement(AchievementService.ACHIEVEMENT_FISH_SPRING)


func _on_forage_interaction_attempted() -> void:
	AudioService.play_bite()


func _on_forage_action_hint_changed(text: String) -> void:
	if _run_state == RunState.RUNNING:
		action_hint_label.text = text


func _on_interaction_prompt_changed(text: String) -> void:
	interaction_prompt_label.text = text
	interaction_prompt_panel.visible = not text.is_empty()


func _on_complete_test_pressed() -> void:
	if _run_state != RunState.RUNNING:
		return
	run_progress_controller.finish_for_debug()


func _on_fail_test_pressed() -> void:
	begin_failure(AppFlow.FAILURE_DEBUG)


func _on_menu_pressed() -> void:
	if _run_state == RunState.RUNNING:
		run_progress_controller.abandon()


func _on_pause_abandon_requested() -> void:
	if _run_state == RunState.RUNNING:
		run_progress_controller.abandon()


func begin_failure(reason: StringName) -> bool:
	var completes_predator_capture: bool = (
		_run_state == RunState.CAPTURED and reason == AppFlow.FAILURE_PREDATOR
	)
	if _run_state != RunState.RUNNING and not completes_predator_capture:
		return false
	return run_progress_controller.fail(reason)


func begin_predator_capture() -> bool:
	if _run_state != RunState.RUNNING:
		return false
	_run_state = RunState.CAPTURED
	_failure_reason = AppFlow.FAILURE_PREDATOR
	wet_eye_controller.stop()
	forage_mode_controller.stop_all()
	player_fish.freeze_for_predator_capture()
	hud_update_timer.stop()
	complete_test_button.disabled = true
	fail_test_button.disabled = true
	menu_button.disabled = true
	action_hint_label.text = "被同一捕食者连续锁定1秒：四眼鱼停止前进，捕食者开始追击。"
	return true


func is_failure_active() -> bool:
	return _run_state == RunState.FAILING


func is_predator_capture_active() -> bool:
	return _run_state == RunState.CAPTURED


func _on_region_motion_started(target_region: int) -> void:
	if _run_state != RunState.RUNNING:
		return
	var current_region: int = region_controller.get_current_region()
	var leaves_exposure: bool = (
		region_layout.is_wet_eye_exposed(_current_profile, current_region)
		and not region_layout.is_wet_eye_exposed(_current_profile, target_region)
	)
	if leaves_exposure:
		var exposed_seconds: float = (
			wet_eye_controller.get_maximum_time()
			- wet_eye_controller.get_remaining_time()
		)
		if AchievementService.qualifies_for_extreme_dry_eye(exposed_seconds):
			_pending_extreme_dry_eye = true
		wet_eye_controller.accept_dive()


func _on_wet_eye_remaining_time_changed(remaining_time: float, maximum_time: float) -> void:
	_update_wet_eye_hud(remaining_time, maximum_time)


func _on_wet_eye_warning_started(_remaining_time: float) -> void:
	_stop_warning_flash()
	wet_eye_warning_overlay.visible = true
	wet_eye_warning_icon.pivot_offset = wet_eye_warning_icon.size * 0.5
	wet_eye_warning_icon.scale = Vector2.ONE
	wet_eye_warning_icon.modulate = Color.WHITE
	_warning_tween = create_tween().set_loops()
	_warning_tween.set_trans(Tween.TRANS_SINE)
	_warning_tween.set_ease(Tween.EASE_IN_OUT)
	_warning_tween.tween_property(wet_eye_warning_icon, ^"scale", Vector2(1.14, 1.14), 0.36)
	_warning_tween.parallel().tween_property(wet_eye_warning_icon, ^"modulate:a", 0.55, 0.36)
	_warning_tween.tween_property(wet_eye_warning_icon, ^"scale", Vector2.ONE, 0.36)
	_warning_tween.parallel().tween_property(wet_eye_warning_icon, ^"modulate:a", 1.0, 0.36)


func _on_wet_eye_warning_ended() -> void:
	_stop_warning_flash()


func _on_wet_eye_dive_accepted() -> void:
	AudioService.play_dive_splash()
	action_hint_label.text = "润眼成功"


func _on_wet_eye_exposed_changed(is_exposed: bool) -> void:
	if is_exposed:
		wet_eye_status_label.text = "计时中"
	else:
		wet_eye_status_label.text = "眼睛已浸水"


func _on_wet_eye_timed_out() -> void:
	begin_failure(AppFlow.FAILURE_DRY_EYES)


func _on_player_death_animation_finished() -> void:
	if _run_state != RunState.FAILING or _settled_result == null:
		return
	if route_scenes_after_settlement:
		AppFlow.open_death_for_result(_settled_result)


func _on_player_jump_started(_launch_velocity: Vector2) -> void:
	AudioService.play_jump()


func _on_threat_bite_started(_threat: PatrolThreat) -> void:
	AudioService.play_bite()


func _on_encounter_warning_started(_pattern_id: StringName, _duration: float) -> void:
	AudioService.start_warning_loop()


func _on_encounter_warning_cancelled(_pattern_id: StringName) -> void:
	AudioService.stop_warning_loop()


func _on_encounter_capture_started(
	_pattern_id: StringName,
	_animal_type: ThreatEntry.AnimalType
) -> void:
	AudioService.stop_warning_loop()


func _on_ecology_warning_started(_event_id: int, _duration: float) -> void:
	AudioService.start_warning_loop()


func _on_ecology_warning_cancelled(_event_id: int) -> void:
	AudioService.stop_warning_loop()


func _on_ecology_capture_started(
	_event_id: int,
	_animal_type: ThreatEntry.AnimalType
) -> void:
	AudioService.stop_warning_loop()


func _on_bird_evaded(_pattern_id: StringName) -> void:
	_record_achievement(AchievementService.ACHIEVEMENT_SURVIVAL_SKILL)


func _on_ecology_bird_evaded(_event_id: int) -> void:
	if _run_state == RunState.RUNNING:
		_record_achievement(AchievementService.ACHIEVEMENT_SURVIVAL_SKILL)


func _record_achievement(achievement_id: StringName) -> void:
	if AchievementService.unlock(achievement_id):
		run_progress_controller.record_new_achievement(achievement_id)


func _on_run_result_ready(result: RunResult) -> void:
	if result == null or _settled_result != null:
		return
	_settled_result = result
	for achievement_id: StringName in AchievementService.evaluate_run(result):
		result.add_new_unlock(achievement_id)
	_failure_reason = result.failure_reason
	_stop_gameplay_systems()
	AppFlow.store_run_result(result)
	if result.outcome == RunResult.Outcome.NATURAL_FINISH:
		AudioService.play_game_success()
	match result.outcome:
		RunResult.Outcome.NATURAL_FINISH, RunResult.Outcome.DEBUG_FINISH:
			_run_state = RunState.FINISHED
			action_hint_label.text = "已抵达终点，正在进入结算。"
			if route_scenes_after_settlement:
				AppFlow.complete_run(result)
		RunResult.Outcome.FAILURE:
			_run_state = RunState.FAILING
			action_hint_label.text = AppFlow.get_failure_reason_label(result.failure_reason)
			if result.failure_reason == AppFlow.FAILURE_DRY_EYES:
				action_hint_label.text = "润眼倒计时归零：眼睛过于干燥。"
				wet_eye_status_label.text = "润眼失败"
			failure_started.emit(result.failure_reason)
			var surface_float_y: float = (
				region_layout.get_water_surface_y()
				+ player_fish.get_body_half_height()
				+ 8.0
			)
			player_fish.play_death_animation(
				surface_float_y,
				world_config.death_animation_duration
			)
		RunResult.Outcome.ABANDONED:
			_run_state = RunState.FINISHED
			if route_scenes_after_settlement:
				AppFlow.open_main_menu()
		_:
			pass


func _stop_gameplay_systems() -> void:
	_pending_extreme_dry_eye = false
	pause_menu.close_without_resume_signal()
	wet_eye_controller.stop()
	forage_mode_controller.stop_all()
	encounter_director.stop_all()
	ecology_event_director.stop_all()
	player_fish.stop_for_settlement()
	mode_host.process_mode = Node.PROCESS_MODE_DISABLED
	hud_update_timer.stop()
	complete_test_button.disabled = true
	fail_test_button.disabled = true
	menu_button.disabled = true
	interaction_prompt_panel.visible = false
	AudioService.stop_exploration_music()
	AudioService.stop_warning_loop()
	_stop_warning_flash()


func is_run_finished() -> bool:
	return _run_state == RunState.FINISHED


func get_settled_result() -> RunResult:
	return _settled_result


func _update_wet_eye_hud(remaining_time: float, maximum_time: float) -> void:
	wet_eye_progress.max_value = maximum_time
	wet_eye_progress.value = remaining_time
	wet_eye_time_label.text = "%.1f s" % remaining_time


func _update_wet_eye_panel_visibility() -> void:
	var forage_deep_or_transitioning: bool = (
		_selected_mode == AppFlow.GameMode.FORAGE
		and (
			_current_profile == RegionLayout.ViewProfile.FORAGE_DEEP
			or _depth_transition_active
		)
	)
	wet_eye_panel.visible = not forage_deep_or_transitioning


func _stop_warning_flash() -> void:
	if _warning_tween != null and _warning_tween.is_valid():
		_warning_tween.kill()
	wet_eye_warning_icon.scale = Vector2.ONE
	wet_eye_warning_icon.modulate = Color.WHITE
	wet_eye_warning_overlay.visible = false
