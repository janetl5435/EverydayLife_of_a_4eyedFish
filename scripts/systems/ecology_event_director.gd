class_name EcologyEventDirector extends Node

signal event_started(event_id: int)
signal batch_activated(event_id: int, batch_index: int)
signal warning_started(event_id: int, duration: float)
signal warning_cancelled(event_id: int)
signal bird_evaded(event_id: int)
signal capture_started(event_id: int, animal_type: ThreatEntry.AnimalType)

@export_group("Event scheduling")
@export_range(0.0, 2000.0, 10.0) var first_event_distance: float = 320.0
@export_range(1800.0, 2200.0, 10.0) var event_1_length: float = 2000.0
@export_range(1800.0, 2200.0, 10.0) var event_2_length: float = 2100.0
@export_range(1800.0, 2200.0, 10.0) var event_3_length: float = 2200.0
@export_range(1800.0, 2200.0, 10.0) var event_4_length: float = 1800.0
@export_range(0.0, 2000.0, 10.0) var stop_spawning_before_finish: float = 800.0
@export_range(0.0, 1000.0, 10.0) var safe_finish_buffer: float = 400.0

@export_group("Visible limits")
@export_range(1, 6, 1) var maximum_visible_threats: int = 3
@export_range(1, 8, 1) var maximum_visible_foods: int = 4

@export_group("Threat rules")
@export_range(50.0, 800.0, 10.0) var bird_forward_vision_distance: float = 300.0
@export_range(0.1, 3.0, 0.1) var warning_duration: float = 1.0
@export_range(0.0, 3.0, 0.05) var attack_charge_duration: float = 0.55
@export_range(0.0, 2.0, 0.05) var consume_duration: float = 0.25
@export_range(0.0, 300.0, 10.0) var spawn_edge_inset: float = 90.0

var _gameplay: GameplayRoot
var _player: PlayerFish
var _region_controller: RegionController
var _layout: RegionLayout
var _camera: Camera2D
var _threat_pool: ThreatPool
var _food_service: OpportunityDirector
var _warning_panel: PanelContainer
var _warning_title: Label
var _warning_time: Label
var _warning_detail: Label
var _current_profile: RegionLayout.ViewProfile = RegionLayout.ViewProfile.FORAGE_SURFACE
var _enabled: bool = false
var _automatic_spawning_enabled: bool = true
var _capture_active: bool = false
var _alert_active: bool = false
var _journey_start_x: float = 0.0
var _finish_distance: float = 0.0
var _next_event_x: float = 0.0
var _current_event_start_x: float = 0.0
var _current_event: EcologyEventDefinition
var _current_batch_index: int = 0
var _next_regular_event_id: int = 1
var _event_serial: int = 0
var _started_event_ids: Array[int] = []
var _event_id_by_threat: Dictionary[PatrolThreat, int] = {}
var _exposure_elapsed_by_threat: Dictionary[PatrolThreat, float] = {}


func _ready() -> void:
	set_physics_process(false)


func configure(
	gameplay: GameplayRoot,
	player: PlayerFish,
	region_controller: RegionController,
	layout: RegionLayout,
	camera: Camera2D,
	threat_pool: ThreatPool,
	food_service: OpportunityDirector,
	warning_panel: PanelContainer,
	warning_title: Label,
	warning_time: Label,
	warning_detail: Label,
	journey_start_x: float,
	finish_distance: float,
	initial_profile: RegionLayout.ViewProfile,
	enabled: bool
) -> bool:
	_gameplay = gameplay
	_player = player
	_region_controller = region_controller
	_layout = layout
	_camera = camera
	_threat_pool = threat_pool
	_food_service = food_service
	_warning_panel = warning_panel
	_warning_title = warning_title
	_warning_time = warning_time
	_warning_detail = warning_detail
	_journey_start_x = journey_start_x
	_finish_distance = finish_distance
	_current_profile = initial_profile
	_enabled = enabled
	if _warning_panel != null:
		_warning_panel.visible = false
	if not _enabled:
		set_physics_process(false)
		return true
	if (
		_gameplay == null
		or _player == null
		or _region_controller == null
		or _layout == null
		or _camera == null
		or _threat_pool == null
		or _food_service == null
		or _warning_panel == null
		or _warning_title == null
		or _warning_time == null
		or _warning_detail == null
		or _finish_distance <= 0.0
	):
		push_error("EcologyEventDirector is missing required unified-journey dependencies.")
		_enabled = false
		return false
	for event_id: int in range(1, 5):
		if not is_event_surface_threat_spacing_valid(event_id):
			push_error(
				"Ecology event %d places a bird and the surface escape-lane predator in the same batch."
				% event_id
			)
			_enabled = false
			return false
	_food_service.set_automatic_spawning_enabled(false)
	_next_event_x = _journey_start_x + first_event_distance
	set_physics_process(true)
	return true


func stop_all() -> void:
	_enabled = false
	_capture_active = false
	_current_event = null
	_current_batch_index = 0
	_clear_alert_state()
	_event_id_by_threat.clear()
	_exposure_elapsed_by_threat.clear()
	if _threat_pool != null:
		_threat_pool.release_all()
	set_physics_process(false)


func set_automatic_spawning_enabled(enabled: bool) -> void:
	_automatic_spawning_enabled = enabled


func set_player_view_profile(profile: RegionLayout.ViewProfile) -> void:
	_current_profile = profile


func is_running() -> bool:
	return _enabled


func is_alert_active() -> bool:
	return _alert_active


func is_capture_active() -> bool:
	return _capture_active


func get_current_event_id() -> int:
	return _current_event.event_id if _current_event != null else 0


func get_started_event_ids() -> Array[int]:
	var result: Array[int] = []
	result.append_array(_started_event_ids)
	return result


func get_active_threat_count() -> int:
	return _threat_pool.get_active_count() if _threat_pool != null else 0


func get_active_food_count() -> int:
	return _food_service.get_available_food_count() if _food_service != null else 0


func get_active_threats() -> Array[PatrolThreat]:
	return _threat_pool.get_active_threats() if _threat_pool != null else []


func get_event_length(event_id: int) -> float:
	return _build_event(event_id).length


func get_event_total_food_count(event_id: int) -> int:
	var total: int = 0
	for batch: EcologyEventDefinition.Batch in _build_event(event_id).batches:
		total += batch.foods.size()
	return total


func get_event_total_threat_count(event_id: int) -> int:
	var total: int = 0
	for batch: EcologyEventDefinition.Batch in _build_event(event_id).batches:
		total += batch.threats.size()
	return total


func get_event_food_type_count(event_id: int, food_id: StringName) -> int:
	var total: int = 0
	for batch: EcologyEventDefinition.Batch in _build_event(event_id).batches:
		for food: EcologyEventDefinition.FoodSpawn in batch.foods:
			if food.food_id == food_id:
				total += 1
	return total


func get_event_bird_count(event_id: int) -> int:
	var total: int = 0
	for batch: EcologyEventDefinition.Batch in _build_event(event_id).batches:
		for threat: EcologyEventDefinition.ThreatSpawn in batch.threats:
			if threat.animal_type == ThreatEntry.AnimalType.BIRD:
				total += 1
	return total


func is_event_surface_threat_spacing_valid(event_id: int) -> bool:
	var event: EcologyEventDefinition = _build_event(event_id)
	for batch: EcologyEventDefinition.Batch in event.batches:
		if _batch_contains_bird(batch) and _batch_contains_surface_escape_fish(batch):
			return false
	return true


func _physics_process(delta: float) -> void:
	if not _enabled or _player == null or _capture_active:
		return
	_cleanup_inactive_threat_tracking()
	var remaining_distance: float = _get_remaining_distance()
	if remaining_distance <= safe_finish_buffer:
		_release_threats_for_finish_buffer()
	else:
		_update_threat_awareness(delta)
	if not _automatic_spawning_enabled or remaining_distance <= stop_spawning_before_finish:
		return
	_update_event_schedule()


func _update_event_schedule() -> void:
	if _current_event == null:
		if _player.global_position.x >= _next_event_x:
			_start_next_event()
		return
	while _current_batch_index < _current_event.batches.size():
		var batch: EcologyEventDefinition.Batch = _current_event.batches[_current_batch_index]
		if _player.global_position.x < _current_event_start_x + batch.distance_offset:
			break
		if not _has_capacity_for_batch(batch):
			break
		_activate_batch(batch, _current_batch_index)
		_current_batch_index += 1
	if (
		_current_batch_index >= _current_event.batches.size()
		and _player.global_position.x >= _current_event_start_x + _current_event.length
	):
		_next_event_x = _current_event_start_x + _current_event.length
		_current_event = null
		_start_next_event()


func _start_next_event() -> void:
	if _get_remaining_distance() <= stop_spawning_before_finish:
		return
	var event_id: int
	if _started_event_ids.is_empty():
		event_id = 4
	else:
		event_id = _next_regular_event_id
		_next_regular_event_id = 1 + (_next_regular_event_id % 3)
	_current_event = _build_event(event_id)
	_current_event_start_x = maxf(_next_event_x, _player.global_position.x)
	_current_batch_index = 0
	_event_serial += 1
	_started_event_ids.append(event_id)
	event_started.emit(event_id)
	_update_event_schedule()


func _has_capacity_for_batch(batch: EcologyEventDefinition.Batch) -> bool:
	return (
		get_active_threat_count() + batch.threats.size() <= maximum_visible_threats
		and get_active_food_count() + batch.foods.size() <= maximum_visible_foods
		and _preserves_surface_escape_corridor(batch)
	)


func _preserves_surface_escape_corridor(batch: EcologyEventDefinition.Batch) -> bool:
	var adds_bird: bool = _batch_contains_bird(batch)
	var adds_surface_escape_fish: bool = _batch_contains_surface_escape_fish(batch)
	if adds_bird and adds_surface_escape_fish:
		return false
	if not adds_bird and not adds_surface_escape_fish:
		return true
	for threat: PatrolThreat in _threat_pool.get_active_threats():
		if not threat.is_inside_camera_view():
			continue
		if not threat.is_player_in_forward_view(_player.global_position.x):
			continue
		if adds_surface_escape_fish and threat.get_animal_type() == ThreatEntry.AnimalType.BIRD:
			return false
		if (
			adds_bird
			and threat.get_animal_type() == ThreatEntry.AnimalType.PREDATOR_FISH
			and threat.get_danger_region() == _layout.forage_surface_swim_max_region
		):
			return false
	return true


func _batch_contains_bird(batch: EcologyEventDefinition.Batch) -> bool:
	for plan: EcologyEventDefinition.ThreatSpawn in batch.threats:
		if plan.animal_type == ThreatEntry.AnimalType.BIRD:
			return true
	return false


func _batch_contains_surface_escape_fish(batch: EcologyEventDefinition.Batch) -> bool:
	for plan: EcologyEventDefinition.ThreatSpawn in batch.threats:
		if (
			plan.animal_type == ThreatEntry.AnimalType.PREDATOR_FISH
			and plan.world_region == _layout.forage_surface_swim_max_region
		):
			return true
	return false


func _activate_batch(batch: EcologyEventDefinition.Batch, batch_index: int) -> void:
	for threat_plan: EcologyEventDefinition.ThreatSpawn in batch.threats:
		_spawn_threat(threat_plan, _current_event.event_id)
	for food_plan: EcologyEventDefinition.FoodSpawn in batch.foods:
		_spawn_food(food_plan)
	batch_activated.emit(_current_event.event_id, batch_index)


func _spawn_threat(plan: EcologyEventDefinition.ThreatSpawn, event_id: int) -> void:
	var entry: ThreatEntry = ThreatEntry.new()
	entry.animal_type = plan.animal_type
	entry.world_region = plan.world_region
	entry.direction = plan.direction
	entry.speed = plan.speed
	entry.active_time = 10.0
	var threat: PatrolThreat = _threat_pool.acquire(plan.animal_type)
	if threat == null:
		return
	var spawn_position: Vector2 = Vector2(
		_get_spawn_x(plan.direction) + plan.horizontal_offset,
		_layout.get_region_center_y(plan.world_region)
	)
	threat.activate(entry, spawn_position, _camera)
	if plan.animal_type == ThreatEntry.AnimalType.BIRD:
		threat.set_forward_vision_distance(bird_forward_vision_distance)
	else:
		threat.set_forward_vision_distance(INF)
	threat.set_warning_active(false)
	_event_id_by_threat[threat] = event_id


func _spawn_food(plan: EcologyEventDefinition.FoodSpawn) -> void:
	var definition: FoodDefinition = _food_service.get_food_definition(plan.food_id)
	if definition == null:
		return
	var spawn_position: Vector2 = Vector2(
		_get_spawn_x(-1) + plan.horizontal_offset,
		_layout.get_region_center_y(plan.world_region)
	)
	_food_service.spawn_independent_food(
		plan.food_id,
		_event_serial,
		spawn_position,
		plan.world_velocity_override
	)


func _update_threat_awareness(delta: float) -> void:
	var exposing_threats: Array[PatrolThreat] = []
	var attacker: PatrolThreat
	for threat: PatrolThreat in _threat_pool.get_active_threats():
		var is_exposing: bool = _can_threat_target_current_view(threat) and threat.is_exposing_player(
			_region_controller.get_current_region(),
			_player.global_position.x
		)
		var previous_elapsed: float = _exposure_elapsed_by_threat.get(threat, 0.0)
		threat.set_warning_active(is_exposing)
		if not is_exposing:
			if (
				previous_elapsed > 0.0
				and threat.get_animal_type() == ThreatEntry.AnimalType.BIRD
				and threat.is_inside_camera_view()
				and _did_player_actively_escape_bird(threat)
			):
				bird_evaded.emit(_event_id_by_threat.get(threat, 0))
			_exposure_elapsed_by_threat.erase(threat)
			continue
		exposing_threats.append(threat)
		var elapsed: float = minf(previous_elapsed + delta, warning_duration)
		_exposure_elapsed_by_threat[threat] = elapsed
		if attacker == null and elapsed >= warning_duration:
			attacker = threat
	if attacker != null:
		_begin_capture(attacker)
		return
	_update_alert_hud(exposing_threats)


func _can_threat_target_current_view(threat: PatrolThreat) -> bool:
	if threat.get_animal_type() == ThreatEntry.AnimalType.BIRD:
		return _current_profile == RegionLayout.ViewProfile.FORAGE_SURFACE
	return true


func _did_player_actively_escape_bird(bird: PatrolThreat) -> bool:
	return (
		_current_profile != RegionLayout.ViewProfile.FORAGE_SURFACE
		or not bird.is_exposing_region(_region_controller.get_current_region())
		or bird.is_player_beyond_forward_view(_player.global_position.x)
	)


func _update_alert_hud(exposing_threats: Array[PatrolThreat]) -> void:
	if exposing_threats.is_empty():
		if _alert_active:
			var resolved_event_id: int = _get_primary_alert_event_id()
			_clear_alert_state()
			warning_cancelled.emit(resolved_event_id)
		return
	var primary: PatrolThreat = exposing_threats[0]
	var event_id: int = _event_id_by_threat.get(primary, 0)
	if not _alert_active:
		_alert_active = true
		_warning_panel.visible = true
		warning_started.emit(event_id, warning_duration)
	_warning_title.text = "捕食者警觉：生态事件%d" % event_id
	var shortest_remaining: float = warning_duration
	for threat: PatrolThreat in exposing_threats:
		shortest_remaining = minf(
			shortest_remaining,
			maxf(warning_duration - _exposure_elapsed_by_threat.get(threat, 0.0), 0.0)
		)
	_warning_time.text = "锁定剩余 %.1f s" % shortest_remaining
	_warning_detail.text = "离开捕食者前方视野；水面鸟类视野长度为%d px。" % roundi(bird_forward_vision_distance)


func _begin_capture(attacker: PatrolThreat) -> void:
	if attacker == null or not _gameplay.begin_predator_capture():
		return
	_capture_active = true
	_alert_active = false
	_warning_panel.visible = true
	_warning_title.text = "捕食者已锁定"
	_warning_time.text = "追击中"
	_warning_detail.text = "四眼鱼停止前进；捕食者正在完成追击演出。"
	_threat_pool.freeze_non_attacker(attacker)
	attacker.attack_finished.connect(_on_attack_finished, CONNECT_ONE_SHOT)
	attacker.start_attack(_player, attack_charge_duration, consume_duration)
	capture_started.emit(
		_event_id_by_threat.get(attacker, 0),
		attacker.get_animal_type()
	)


func _release_threats_for_finish_buffer() -> void:
	if _threat_pool.get_active_count() == 0:
		return
	_threat_pool.release_all()
	_event_id_by_threat.clear()
	_exposure_elapsed_by_threat.clear()
	_clear_alert_state()


func _cleanup_inactive_threat_tracking() -> void:
	for threat: PatrolThreat in _event_id_by_threat.keys():
		if threat != null and threat.is_pool_active():
			continue
		_event_id_by_threat.erase(threat)
		_exposure_elapsed_by_threat.erase(threat)


func _clear_alert_state() -> void:
	_alert_active = false
	if _warning_panel != null:
		_warning_panel.visible = false


func _get_primary_alert_event_id() -> int:
	for threat: PatrolThreat in _exposure_elapsed_by_threat.keys():
		return _event_id_by_threat.get(threat, 0)
	return 0


func _get_remaining_distance() -> float:
	return _finish_distance - (_player.global_position.x - _journey_start_x)


func _get_spawn_x(direction: int) -> float:
	var half_view_width: float = get_viewport().get_visible_rect().size.x * 0.5 / _camera.zoom.x
	if direction < 0:
		return _camera.global_position.x + half_view_width - spawn_edge_inset
	return _camera.global_position.x - half_view_width + spawn_edge_inset


func _on_attack_finished(_attacker: PatrolThreat) -> void:
	if _capture_active:
		_gameplay.begin_failure(AppFlow.FAILURE_PREDATOR)


func _build_event(event_id: int) -> EcologyEventDefinition:
	match event_id:
		1:
			return _build_event_1()
		2:
			return _build_event_2()
		3:
			return _build_event_3()
		_:
			return _build_event_4()


func _build_event_1() -> EcologyEventDefinition:
	var event: EcologyEventDefinition = EcologyEventDefinition.new(1, event_1_length)
	var first: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(0.0)
	first.threats.append(_threat(ThreatEntry.AnimalType.BIRD, 3, -1, 230.0))
	first.foods.append(_food(&"insect", 4, 120.0))
	first.foods.append(_food(&"insect", 4, 210.0))
	first.foods.append(_food(&"algae", 8, 20.0))
	var surface_fish: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(600.0)
	surface_fish.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 6, -1, 250.0, -80.0))
	var deep_fish: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(900.0)
	deep_fish.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 7, 1, 260.0))
	deep_fish.foods.append(_food(&"algae", 8, -80.0))
	deep_fish.foods.append(_food(&"shellfish", 8, 60.0))
	deep_fish.foods.append(_food(&"shrimp", 6, 170.0))
	var final_foods: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(1250.0)
	final_foods.foods.append(_food(&"shellfish", 8, -60.0))
	final_foods.foods.append(_food(&"shrimp", 8, 120.0))
	event.batches.assign([first, surface_fish, deep_fish, final_foods])
	return event


func _build_event_2() -> EcologyEventDefinition:
	var event: EcologyEventDefinition = EcologyEventDefinition.new(2, event_2_length)
	var first: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(0.0)
	first.threats.append(_threat(ThreatEntry.AnimalType.BIRD, 3, 1, 260.0))
	first.foods.append(_food(&"insect", 4, -40.0))
	first.foods.append(_food(&"insect", 4, 150.0))
	first.foods.append(_food(&"shrimp", 7, 60.0))
	var deep_fish: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(700.0)
	deep_fish.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 7, 1, 250.0))
	deep_fish.foods.append(_food(&"shrimp", 6, -100.0))
	deep_fish.foods.append(_food(&"algae", 8, 40.0))
	deep_fish.foods.append(_food(&"shrimp", 7, 180.0))
	var surface_fish: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(900.0)
	surface_fish.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 6, -1, 250.0))
	var final_foods: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(1350.0)
	final_foods.foods.append(_food(&"shellfish", 8, -70.0))
	final_foods.foods.append(_food(&"shrimp", 6, 120.0))
	event.batches.assign([first, deep_fish, surface_fish, final_foods])
	return event


func _build_event_3() -> EcologyEventDefinition:
	var event: EcologyEventDefinition = EcologyEventDefinition.new(3, event_3_length)
	var first: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(0.0)
	first.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 6, -1, 230.0, -60.0))
	first.foods.append(_food(&"insect", 4, 40.0))
	first.foods.append(_food(&"shrimp", 6, 90.0, -230.0))
	first.foods.append(_food(&"algae", 8, -80.0))
	var second: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(720.0)
	second.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 7, -1, 230.0, -60.0))
	second.foods.append(_food(&"shrimp", 7, 90.0, -230.0))
	second.foods.append(_food(&"shellfish", 8, -60.0))
	second.foods.append(_food(&"algae", 8, 170.0))
	var third: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(1450.0)
	third.foods.append(_food(&"shrimp", 7, -80.0))
	third.foods.append(_food(&"shellfish", 8, 100.0))
	event.batches.assign([first, second, third])
	return event


func _build_event_4() -> EcologyEventDefinition:
	var event: EcologyEventDefinition = EcologyEventDefinition.new(4, event_4_length)
	var first: EcologyEventDefinition.Batch = EcologyEventDefinition.Batch.new(0.0)
	first.threats.append(_threat(ThreatEntry.AnimalType.PREDATOR_FISH, 7, -1, 220.0))
	first.foods.append(_food(&"insect", 4, 80.0))
	first.foods.append(_food(&"algae", 8, -60.0))
	first.foods.append(_food(&"shellfish", 8, 150.0))
	event.batches.append(first)
	return event


func _food(
	food_id: StringName,
	world_region: int,
	horizontal_offset: float = 0.0,
	world_velocity_override: float = INF
) -> EcologyEventDefinition.FoodSpawn:
	return EcologyEventDefinition.FoodSpawn.new(
		food_id,
		world_region,
		horizontal_offset,
		world_velocity_override
	)


func _threat(
	animal_type: ThreatEntry.AnimalType,
	world_region: int,
	direction: int,
	speed: float,
	horizontal_offset: float = 0.0
) -> EcologyEventDefinition.ThreatSpawn:
	return EcologyEventDefinition.ThreatSpawn.new(
		animal_type,
		world_region,
		direction,
		speed,
		horizontal_offset
	)
