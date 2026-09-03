class_name ForageModeController extends Node

signal state_changed(state: State)
signal profile_changed(profile: RegionLayout.ViewProfile)
signal energy_changed(energy: float)
signal energy_depleted
signal food_collected(food_id: StringName, energy_value: int)
signal interaction_attempted
signal action_hint_changed(text: String)
signal interaction_prompt_changed(text: String)

enum State {
	SURFACE_FORAGE,
	DIVING_TRANSITION,
	DEEP_FORAGE,
	RISING_TRANSITION,
	FINISHED,
}

const SURFACE_INTERACTION_FOOD_ID: StringName = &"shrimp"

@export_range(0.0, 1.0, 0.05) var interaction_depth_lock_duration: float = 0.2

@onready var opportunity_director: OpportunityDirector = %OpportunityDirector

var _player: PlayerFish
var _region_controller: RegionController
var _layout: RegionLayout
var _camera_rig: CameraRig
var _region_guide: RegionGuide
var _wet_eye_controller: WetEyeController
var _enabled: bool = false
var _state: State = State.FINISHED
var _current_profile: RegionLayout.ViewProfile = RegionLayout.ViewProfile.FORAGE_SURFACE
var _energy: float = 0.0
var _normal_energy_drain_per_second: float = 1.0
var _boosted_energy_drain_per_second: float = 2.5
var _energy_depleted_emitted: bool = false
var _last_prompt: String = ""
var _interaction_depth_lock_remaining: float = 0.0


func _ready() -> void:
	set_process(false)


func configure(
	player: PlayerFish,
	region_controller: RegionController,
	layout: RegionLayout,
	camera_rig: CameraRig,
	region_guide: RegionGuide,
	wet_eye_controller: WetEyeController,
	air_food_root: Node2D,
	underwater_food_root: Node2D,
	initial_energy: float,
	normal_energy_drain_per_second: float,
	boosted_energy_drain_per_second: float,
	enabled: bool
) -> bool:
	_player = player
	_region_controller = region_controller
	_layout = layout
	_camera_rig = camera_rig
	_region_guide = region_guide
	_wet_eye_controller = wet_eye_controller
	_normal_energy_drain_per_second = maxf(normal_energy_drain_per_second, 0.0)
	_boosted_energy_drain_per_second = maxf(boosted_energy_drain_per_second, 0.0)
	_enabled = enabled
	if not _enabled:
		_state = State.FINISHED
		set_process(false)
		return opportunity_director.configure(
			player,
			layout,
			camera_rig.get_camera(),
			air_food_root,
			underwater_food_root,
			false
		)
	if (
		_player == null
		or _region_controller == null
		or _layout == null
		or _camera_rig == null
		or _region_guide == null
		or _wet_eye_controller == null
	):
		push_error("ForageModeController is missing required gameplay dependencies.")
		return false
	if initial_energy <= 0.0:
		push_error("ForageModeController requires positive initial energy.")
		return false
	if not _camera_rig.view_transition_finished.is_connected(_on_view_transition_finished):
		_camera_rig.view_transition_finished.connect(_on_view_transition_finished)
	if not opportunity_director.food_collected.is_connected(_on_food_collected):
		opportunity_director.food_collected.connect(_on_food_collected)
	_current_profile = RegionLayout.ViewProfile.FORAGE_SURFACE
	_state = State.SURFACE_FORAGE
	_energy = initial_energy
	_energy_depleted_emitted = false
	_interaction_depth_lock_remaining = 0.0
	energy_changed.emit(_energy)
	state_changed.emit(_state)
	profile_changed.emit(_current_profile)
	if not opportunity_director.configure(
		player,
		layout,
		camera_rig.get_camera(),
		air_food_root,
		underwater_food_root,
		true
	):
		return false
	set_process(true)
	_emit_default_hint()
	return true


func request_depth_switch() -> bool:
	if (
		not _enabled
		or _state == State.DIVING_TRANSITION
		or _state == State.RISING_TRANSITION
		or _region_controller.is_move_in_progress()
		or _player.is_jump_active()
		or _interaction_depth_lock_remaining > 0.0
	):
		action_hint_changed.emit("进食锁定、区域移动、跳跃或相机切换结束后才能再次切换。")
		return false
	var current_region: int = _region_controller.get_current_region()
	var target_profile: RegionLayout.ViewProfile
	var target_state: State
	if _state == State.SURFACE_FORAGE and current_region == 6:
		target_profile = RegionLayout.ViewProfile.FORAGE_DEEP
		target_state = State.DIVING_TRANSITION
	elif _state == State.DEEP_FORAGE and current_region == 5:
		target_profile = RegionLayout.ViewProfile.FORAGE_SURFACE
		target_state = State.RISING_TRANSITION
	else:
		_emit_default_hint()
		return false
	if not _region_controller.set_bounds(
		_layout.get_swim_min_region(target_profile),
		_layout.get_swim_max_region(target_profile)
	):
		return false
	_player.cancel_jump()
	_player.set_region_input_enabled(false)
	_state = target_state
	_current_profile = target_profile
	state_changed.emit(_state)
	profile_changed.emit(_current_profile)
	_region_guide.set_active_profile(_current_profile)
	_camera_rig.set_view_profile(_current_profile, true)
	action_hint_changed.emit("相机切换中……")
	return true


func request_interaction() -> bool:
	if not _enabled or _player.is_jump_active():
		return false
	var current_region: int = _region_controller.get_current_region()
	if _state == State.SURFACE_FORAGE:
		_player.play_eat_animation()
		var surface_shrimp: ForageFood = opportunity_director.get_best_interactable_by_food_id(
			_player,
			current_region,
			SURFACE_INTERACTION_FOOD_ID
		)
		if surface_shrimp == null:
			action_hint_changed.emit("进食动作已执行；嘴巴进入虾的碰撞范围时才能成功获得食物。")
			return false
		var surface_collected: bool = surface_shrimp.try_collect_by_interaction(
			_player,
			current_region
		)
		if surface_collected:
			_interaction_depth_lock_remaining = interaction_depth_lock_duration
		return surface_collected
	if _state != State.DEEP_FORAGE:
		return false
	_player.play_eat_animation()
	var collected: bool = opportunity_director.try_interact(
		_player,
		current_region
	)
	if collected:
		_interaction_depth_lock_remaining = interaction_depth_lock_duration
	else:
		action_hint_changed.emit("进食动作已执行；嘴巴进入食物碰撞范围时才能成功获得食物。")
	return collected


func begin_jump_charge() -> bool:
	if (
		not _enabled
		or _state != State.SURFACE_FORAGE
		or _region_controller.get_current_region() != 5
		or _region_controller.is_move_in_progress()
	):
		return false
	if not _player.begin_jump_charge():
		return false
	action_hint_changed.emit("按住空格，点击鱼右上方选择方向；松开空格起跳。")
	return true


func set_jump_target(world_target: Vector2) -> bool:
	if not _enabled or _state != State.SURFACE_FORAGE:
		return false
	return _player.set_jump_target(world_target)


func release_jump_charge() -> bool:
	if not _enabled or not _player.is_jump_charging():
		return false
	var launched: bool = _player.release_jump_charge()
	if not launched:
		action_hint_changed.emit("未选择合法的右上方向，本次跳跃已取消。")
	else:
		action_hint_changed.emit("跳跃中：接触昆虫即可捕食。")
	return launched


func handle_unhandled_input(event: InputEvent) -> bool:
	if not _enabled or _state == State.FINISHED:
		return false
	if event.is_action_pressed(&"jump", false):
		return begin_jump_charge()
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and _player.is_jump_charging():
			set_jump_target(_player.get_global_mouse_position())
			return true
	if event.is_action_released(&"jump", false) and _player.is_jump_charging():
		release_jump_charge()
		return true
	if event.is_action_pressed(&"interact", false):
		interaction_attempted.emit()
		request_interaction()
		return true
	return false


func stop_all() -> void:
	if _state == State.FINISHED and not _enabled:
		return
	_enabled = false
	_state = State.FINISHED
	_interaction_depth_lock_remaining = 0.0
	set_process(false)
	_player.cancel_jump()
	opportunity_director.stop_all()
	interaction_prompt_changed.emit("")
	state_changed.emit(_state)


func get_state() -> State:
	return _state


func get_current_profile() -> RegionLayout.ViewProfile:
	return _current_profile


func get_energy() -> float:
	return _energy


func get_display_energy() -> int:
	return floori(maxf(_energy, 0.0))


func is_enabled_for_forage() -> bool:
	return _enabled


func get_interaction_depth_lock_remaining() -> float:
	return _interaction_depth_lock_remaining


func advance_energy(delta: float) -> void:
	if delta <= 0.0 or not _enabled or _energy_depleted_emitted:
		return
	var drain_rate: float = (
		_boosted_energy_drain_per_second
		if _player.is_speed_boost_active()
		else _normal_energy_drain_per_second
	)
	if drain_rate <= 0.0:
		return
	_energy = maxf(_energy - drain_rate * delta, 0.0)
	energy_changed.emit(_energy)
	if is_zero_approx(_energy):
		_energy_depleted_emitted = true
		energy_depleted.emit()


func _process(delta: float) -> void:
	if not _enabled:
		return
	advance_energy(delta)
	_interaction_depth_lock_remaining = maxf(
		_interaction_depth_lock_remaining - delta,
		0.0
	)
	if not _enabled:
		return
	var prompt: String = ""
	if _state == State.DEEP_FORAGE or _state == State.SURFACE_FORAGE:
		var target: ForageFood
		if _state == State.SURFACE_FORAGE:
			target = opportunity_director.get_best_interactable_by_food_id(
				_player,
				_region_controller.get_current_region(),
				SURFACE_INTERACTION_FOOD_ID
			)
		else:
			target = opportunity_director.get_best_interactable(
				_player,
				_region_controller.get_current_region()
			)
		if target != null:
			prompt = "按F进食：%s（+%d能量）" % [
				target.get_definition().display_name,
				target.get_definition().energy_value,
			]
	if prompt != _last_prompt:
		_last_prompt = prompt
		interaction_prompt_changed.emit(prompt)


func _on_view_transition_finished(profile: RegionLayout.ViewProfile) -> void:
	if not _enabled or profile != _current_profile:
		return
	if _state == State.DIVING_TRANSITION:
		_state = State.DEEP_FORAGE
	elif _state == State.RISING_TRANSITION:
		_state = State.SURFACE_FORAGE
	else:
		return
	_player.set_region_input_enabled(true)
	_wet_eye_controller.set_exposed(
		_layout.is_wet_eye_exposed(
			_current_profile,
			_region_controller.get_current_region()
		)
	)
	state_changed.emit(_state)
	_emit_default_hint()


func _on_food_collected(food_id: StringName, energy_value: int) -> void:
	if not _enabled:
		return
	_energy += float(energy_value)
	energy_changed.emit(_energy)
	food_collected.emit(food_id, energy_value)
	action_hint_changed.emit("获得%s，能量 +%d。" % [String(food_id), energy_value])


func _emit_default_hint() -> void:
	if not _enabled:
		return
	if _state == State.SURFACE_FORAGE:
		action_hint_changed.emit("区域5可蓄力跳跃；水面可按F吃虾；按S进入区域6润眼，再按S下潜；Shift加速。")
	elif _state == State.DEEP_FORAGE:
		action_hint_changed.emit("区域5–8水下寻食；按F进食；按W进入区域5，再按W上浮；按住Shift加速。")
