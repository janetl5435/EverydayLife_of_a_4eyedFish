class_name EncounterDirector extends Node

signal warning_started(pattern_id: StringName, duration: float)
signal warning_cancelled(pattern_id: StringName)
signal bird_evaded(pattern_id: StringName)
signal capture_started(pattern_id: StringName, animal_type: ThreatEntry.AnimalType)

const COMBINATION_PATTERN_PATHS: Array[String] = [
	"res://data/encounters/bird_fish_mid.tres",
	"res://data/encounters/bird_two_fish.tres",
	"res://data/encounters/two_fish_deep.tres",
]
const SIMPLE_PATTERN_PATHS: Array[String] = [
	"res://data/encounters/single_bird.tres",
	"res://data/encounters/single_fish_mid.tres",
	"res://data/encounters/single_fish_deep.tres",
]

@export_group("Distance scheduling")
@export_range(0.0, 5000.0, 10.0) var first_encounter_distance: float = 600.0
@export_range(100.0, 5000.0, 10.0) var simple_followup_distance: float = 160.0
@export_range(100.0, 5000.0, 10.0) var combination_followup_distance: float = 280.0
@export_range(0.0, 300.0, 10.0) var spawn_edge_inset: float = 100.0
@export_range(3, 12, 1) var maximum_visible_threats: int = 6

@export_group("Capture presentation")
@export_range(0.0, 3.0, 0.05) var attack_charge_duration: float = 0.55
@export_range(0.0, 2.0, 0.05) var consume_duration: float = 0.25

var _gameplay: GameplayRoot
var _player: PlayerFish
var _region_controller: RegionController
var _layout: RegionLayout
var _lane_move_duration: float = 0.1
var _camera: Camera2D
var _threat_pool: ThreatPool
var _warning_panel: PanelContainer
var _warning_title: Label
var _warning_time: Label
var _warning_detail: Label
var _patterns: Array[EncounterPattern] = []
var _combination_patterns: Array[EncounterPattern] = []
var _simple_patterns: Array[EncounterPattern] = []
var _active_pattern: EncounterPattern
var _encounter_threats: Array[PatrolThreat] = []
var _pattern_by_threat: Dictionary[PatrolThreat, EncounterPattern] = {}
var _exposure_elapsed_by_threat: Dictionary[PatrolThreat, float] = {}
var _enabled_for_patrol: bool = false
var _automatic_spawning_enabled: bool = true
var _encounter_active: bool = false
var _capture_active: bool = false
var _spawn_group_pending_resolution: bool = false
var _next_encounter_x: float = 0.0
var _combination_cursor: int = 0
var _simple_cursor: int = 0
var _next_automatic_encounter_is_simple: bool = false


func _ready() -> void:
	set_physics_process(false)


func configure(
	gameplay: GameplayRoot,
	player: PlayerFish,
	region_controller: RegionController,
	layout: RegionLayout,
	lane_move_duration: float,
	camera: Camera2D,
	threat_pool: ThreatPool,
	warning_panel: PanelContainer,
	warning_title: Label,
	warning_time: Label,
	warning_detail: Label,
	enable_for_patrol: bool
) -> void:
	_gameplay = gameplay
	_player = player
	_region_controller = region_controller
	_layout = layout
	_lane_move_duration = maxf(lane_move_duration, 0.01)
	_camera = camera
	_threat_pool = threat_pool
	_warning_panel = warning_panel
	_warning_title = warning_title
	_warning_time = warning_time
	_warning_detail = warning_detail
	_warning_panel.visible = false
	_enabled_for_patrol = enable_for_patrol
	if not _enabled_for_patrol:
		set_physics_process(false)
		return
	_load_default_patterns()
	_combination_cursor = 0
	_simple_cursor = 0
	_next_automatic_encounter_is_simple = false
	_next_encounter_x = _player.global_position.x + first_encounter_distance
	set_physics_process(not _patterns.is_empty())


func stop_all() -> void:
	_enabled_for_patrol = false
	_encounter_active = false
	_capture_active = false
	_active_pattern = null
	_encounter_threats.clear()
	_pattern_by_threat.clear()
	_exposure_elapsed_by_threat.clear()
	_spawn_group_pending_resolution = false
	if _threat_pool != null:
		_threat_pool.release_all()
	if _warning_panel != null:
		_warning_panel.visible = false
	set_physics_process(false)


func force_start_pattern(pattern_id: StringName) -> bool:
	if not _enabled_for_patrol or _encounter_active or _capture_active or _spawn_group_pending_resolution:
		return false
	for pattern: EncounterPattern in _patterns:
		if pattern.pattern_id == pattern_id:
			if _threat_pool.get_active_count() + pattern.threat_entries.size() > maximum_visible_threats:
				return false
			return _start_pattern(pattern)
	return false


func set_automatic_spawning_enabled(enabled: bool) -> void:
	_automatic_spawning_enabled = enabled


func get_available_patterns() -> Array[EncounterPattern]:
	var result: Array[EncounterPattern] = []
	result.append_array(_patterns)
	return result


func get_active_threats() -> Array[PatrolThreat]:
	if _threat_pool == null:
		return []
	return _threat_pool.get_active_threats()


func get_active_threat_count() -> int:
	if _threat_pool == null:
		return 0
	return _threat_pool.get_active_count()


func get_current_encounter_threats() -> Array[PatrolThreat]:
	var result: Array[PatrolThreat] = []
	result.append_array(_encounter_threats)
	return result


func get_current_encounter_threat_count() -> int:
	return _encounter_threats.size()


func is_alert_active() -> bool:
	return _encounter_active


func is_capture_active() -> bool:
	return _capture_active


func is_enabled_for_patrol() -> bool:
	return _enabled_for_patrol


func get_current_pattern_id() -> StringName:
	if _active_pattern == null:
		return &""
	return _active_pattern.pattern_id


func _physics_process(delta: float) -> void:
	if not _enabled_for_patrol or _player == null:
		return
	if _capture_active:
		return
	_cleanup_inactive_threat_tracking()
	var exposing_threats: Array[PatrolThreat] = _update_threat_awareness(delta)
	if not exposing_threats.is_empty():
		_update_active_alert(exposing_threats)
		return
	if _encounter_active:
		_resolve_current_alert()
	elif _spawn_group_pending_resolution:
		_complete_spawn_group_resolution()
	if not _automatic_spawning_enabled:
		return
	if _player.global_position.x >= _next_encounter_x:
		_try_start_next_pattern()


func _load_default_patterns() -> void:
	_patterns.clear()
	_combination_patterns = _load_valid_patterns(COMBINATION_PATTERN_PATHS, false)
	_simple_patterns = _load_valid_patterns(SIMPLE_PATTERN_PATHS, true)


func _load_valid_patterns(paths: Array[String], expected_simple: bool) -> Array[EncounterPattern]:
	var loaded_patterns: Array[EncounterPattern] = []
	for path: String in paths:
		var pattern: EncounterPattern = load(path) as EncounterPattern
		if pattern == null:
			push_error("Could not load encounter pattern: %s" % path)
			continue
		if not pattern.is_valid():
			push_error("Encounter pattern is structurally invalid: %s" % path)
			continue
		if pattern.is_simple() != expected_simple:
			push_error("Encounter pattern is in the wrong scheduling group: %s" % path)
			continue
		if not SafeRouteValidator.is_pattern_fair_for_threatened_starts(
			pattern,
			_layout.patrol_swim_min_region,
			_layout.patrol_swim_max_region,
			_lane_move_duration,
			3
		):
			push_error("Encounter pattern has no complete safe route: %s" % path)
			continue
		if not SafeRouteValidator.is_declared_minimum_route_valid(
			pattern,
			_layout.patrol_swim_min_region,
			_layout.patrol_swim_max_region,
			_lane_move_duration,
			3
		):
			push_error("Encounter pattern declares an invalid minimum safe route: %s" % path)
			continue
		loaded_patterns.append(pattern)
		_patterns.append(pattern)
	return loaded_patterns


func _try_start_next_pattern() -> void:
	var candidate_patterns: Array[EncounterPattern] = (
		_simple_patterns
		if _next_automatic_encounter_is_simple
		else _combination_patterns
	)
	if candidate_patterns.is_empty():
		return
	var current_region: int = _region_controller.get_current_region()
	var cursor: int = _simple_cursor if _next_automatic_encounter_is_simple else _combination_cursor
	for offset: int in range(candidate_patterns.size()):
		var pattern_index: int = (cursor + offset) % candidate_patterns.size()
		var pattern: EncounterPattern = candidate_patterns[pattern_index]
		if _threat_pool.get_active_count() + pattern.threat_entries.size() > maximum_visible_threats:
			continue
		if not pattern.is_region_threatened(current_region, 0.0):
			continue
		var route: PackedInt32Array = SafeRouteValidator.find_safe_route(
			pattern,
			current_region,
			_layout.patrol_swim_min_region,
			_layout.patrol_swim_max_region,
			_lane_move_duration
		)
		var move_count: int = SafeRouteValidator.get_route_move_count(route)
		if route.is_empty() or move_count < 1 or move_count > 3:
			continue
		if _start_pattern(pattern):
			if _next_automatic_encounter_is_simple:
				_simple_cursor = (pattern_index + 1) % candidate_patterns.size()
			else:
				_combination_cursor = (pattern_index + 1) % candidate_patterns.size()
			_next_automatic_encounter_is_simple = not _next_automatic_encounter_is_simple
			return


func _start_pattern(pattern: EncounterPattern) -> bool:
	if pattern == null or not pattern.is_valid() or pattern.threat_entries.size() > 3:
		return false
	var acquired: Array[PatrolThreat] = []
	for entry: ThreatEntry in pattern.threat_entries:
		var threat: PatrolThreat = _threat_pool.acquire(entry.animal_type)
		if threat == null:
			for acquired_threat: PatrolThreat in acquired:
				_threat_pool.release(acquired_threat)
			return false
		var spawn_position: Vector2 = Vector2(
			_get_spawn_x(entry.direction),
			_layout.get_region_center_y(entry.world_region)
		)
		threat.activate(entry, spawn_position, _camera)
		threat.set_warning_active(false)
		_pattern_by_threat[threat] = pattern
		acquired.append(threat)
	_active_pattern = pattern
	_encounter_threats.clear()
	_spawn_group_pending_resolution = true
	return true


func _update_threat_awareness(delta: float) -> Array[PatrolThreat]:
	var current_region: int = _region_controller.get_current_region()
	var exposing_threats: Array[PatrolThreat] = []
	var attacker: PatrolThreat = null
	for threat: PatrolThreat in _threat_pool.get_active_threats():
		var is_exposing: bool = threat.is_exposing_player(current_region, _player.global_position.x)
		var previous_elapsed: float = _exposure_elapsed_by_threat.get(threat, 0.0)
		threat.set_warning_active(is_exposing)
		if not is_exposing:
			if previous_elapsed > 0.0 and threat.get_animal_type() == ThreatEntry.AnimalType.BIRD:
				bird_evaded.emit(_get_pattern_id_for_threat(threat))
			_exposure_elapsed_by_threat.erase(threat)
			continue
		exposing_threats.append(threat)
		var pattern: EncounterPattern = _pattern_by_threat.get(threat)
		if pattern == null:
			continue
		var elapsed: float = minf(previous_elapsed + delta, pattern.warning_duration)
		_exposure_elapsed_by_threat[threat] = elapsed
		if attacker == null and elapsed >= pattern.warning_duration:
			attacker = threat
	if attacker != null:
		_begin_capture(attacker)
	return exposing_threats


func _update_active_alert(exposing_threats: Array[PatrolThreat]) -> void:
	if _capture_active:
		return
	_encounter_threats = exposing_threats
	var primary_threat: PatrolThreat = exposing_threats[0]
	var primary_pattern: EncounterPattern = _pattern_by_threat.get(primary_threat)
	if not _encounter_active:
		_encounter_active = true
		_active_pattern = primary_pattern
		_show_warning_hud(primary_pattern)
		warning_started.emit(primary_pattern.pattern_id, primary_pattern.warning_duration)
	var shortest_remaining: float = primary_pattern.warning_duration
	for threat: PatrolThreat in exposing_threats:
		var pattern: EncounterPattern = _pattern_by_threat.get(threat)
		if pattern == null:
			continue
		var elapsed: float = _exposure_elapsed_by_threat.get(threat, 0.0)
		shortest_remaining = minf(shortest_remaining, maxf(pattern.warning_duration - elapsed, 0.0))
	_warning_time.text = "锁定剩余 %.1f s" % shortest_remaining
	_warning_detail.text = "当前泳道：全局区域%d　离开每只捕食者的攻击视野会分别重置其计时。" % _region_controller.get_current_region()


func _resolve_current_alert() -> void:
	var completed_pattern_id: StringName = get_current_pattern_id()
	_encounter_active = false
	_active_pattern = null
	_encounter_threats.clear()
	_warning_panel.visible = false
	warning_cancelled.emit(completed_pattern_id)
	if _spawn_group_pending_resolution:
		_complete_spawn_group_resolution()


func _complete_spawn_group_resolution() -> void:
	_spawn_group_pending_resolution = false
	var followup_distance: float = (
		simple_followup_distance
		if _next_automatic_encounter_is_simple
		else combination_followup_distance
	)
	_next_encounter_x = _player.global_position.x + followup_distance


func _cleanup_inactive_threat_tracking() -> void:
	for threat: PatrolThreat in _pattern_by_threat.keys():
		if threat != null and threat.is_pool_active():
			continue
		_pattern_by_threat.erase(threat)
		_exposure_elapsed_by_threat.erase(threat)


func _get_pattern_id_for_threat(threat: PatrolThreat) -> StringName:
	var pattern: EncounterPattern = _pattern_by_threat.get(threat)
	if pattern == null:
		return &""
	return pattern.pattern_id


func _begin_capture(attacker: PatrolThreat) -> void:
	if attacker == null or not _gameplay.begin_predator_capture():
		return
	var attacker_pattern: EncounterPattern = _pattern_by_threat.get(attacker)
	if attacker_pattern != null:
		_active_pattern = attacker_pattern
	_encounter_active = false
	_capture_active = true
	_warning_title.text = "捕食者已锁定"
	_warning_time.text = "追击中"
	_warning_detail.text = "四眼鱼停止前进；捕食者正在完成追击演出。"
	_threat_pool.freeze_non_attacker(attacker)
	attacker.attack_finished.connect(_on_attack_finished, CONNECT_ONE_SHOT)
	attacker.start_attack(_player, attack_charge_duration, consume_duration)
	capture_started.emit(get_current_pattern_id(), attacker.get_animal_type())


func _get_spawn_x(direction: int) -> float:
	var half_view_width: float = get_viewport().get_visible_rect().size.x * 0.5 / _camera.zoom.x
	if direction < 0:
		return _camera.global_position.x + half_view_width - spawn_edge_inset
	return _camera.global_position.x - half_view_width + spawn_edge_inset


func _show_warning_hud(pattern: EncounterPattern) -> void:
	_warning_panel.visible = true
	_warning_title.text = (
		"捕食者警觉：单只进入攻击视野"
		if pattern.is_simple()
		else "捕食者警觉：多个攻击视野同时出现"
	)
	_warning_time.text = "锁定剩余 %.1f s" % pattern.warning_duration
	_warning_detail.text = "W/↑、S/↓切换全局区域5–7；连续1秒处于同一捕食者视野内将触发攻击。"


func _on_attack_finished(_attacker: PatrolThreat) -> void:
	if not _capture_active:
		return
	_gameplay.begin_failure(AppFlow.FAILURE_PREDATOR)
