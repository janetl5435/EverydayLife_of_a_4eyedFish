class_name CameraRig extends Node2D

signal view_transition_started(profile: RegionLayout.ViewProfile)
signal view_profile_changed(profile: RegionLayout.ViewProfile)
signal view_transition_finished(profile: RegionLayout.ViewProfile)

@onready var camera: Camera2D = %Camera2D

var _target: Node2D
var _layout: RegionLayout
var _map_display_height: float = 0.0
var _horizontal_look_ahead: float = 0.0
var _vertical_transition_duration: float = 0.5
var _current_profile: RegionLayout.ViewProfile = RegionLayout.ViewProfile.PATROL
var _vertical_tween: Tween


func _ready() -> void:
	set_physics_process(false)


func configure(
	target: Node2D,
	layout: RegionLayout,
	config: WorldConfig,
	map_display_height: float,
	initial_profile: RegionLayout.ViewProfile
) -> void:
	_target = target
	_layout = layout
	_map_display_height = map_display_height
	_horizontal_look_ahead = config.camera_horizontal_look_ahead
	_vertical_transition_duration = config.camera_vertical_transition_duration
	camera.limit_top = 0
	camera.limit_bottom = ceili(_map_display_height)
	_current_profile = initial_profile
	position = Vector2(
		_target.global_position.x + _horizontal_look_ahead,
		_get_profile_y(initial_profile)
	)
	set_physics_process(true)


func set_view_profile(profile: RegionLayout.ViewProfile, animate: bool = true) -> void:
	if _layout == null:
		return
	if _vertical_tween != null and _vertical_tween.is_valid():
		_vertical_tween.kill()
	_current_profile = profile
	var target_y: float = _get_profile_y(profile)
	view_transition_started.emit(profile)
	if not animate or is_zero_approx(_vertical_transition_duration):
		position.y = target_y
		view_profile_changed.emit(profile)
		view_transition_finished.emit(profile)
		return
	_vertical_tween = create_tween()
	_vertical_tween.set_trans(Tween.TRANS_SINE)
	_vertical_tween.set_ease(Tween.EASE_IN_OUT)
	_vertical_tween.tween_property(self, "position:y", target_y, _vertical_transition_duration)
	_vertical_tween.finished.connect(_on_vertical_tween_finished, CONNECT_ONE_SHOT)


func get_camera() -> Camera2D:
	return camera


func get_current_profile() -> RegionLayout.ViewProfile:
	return _current_profile


func _physics_process(_delta: float) -> void:
	if _target == null:
		return
	position.x = _target.global_position.x + _horizontal_look_ahead


func _get_profile_y(profile: RegionLayout.ViewProfile) -> float:
	return _layout.get_profile_camera_y(
		profile,
		get_viewport_rect().size.y,
		_map_display_height
	)


func _on_vertical_tween_finished() -> void:
	view_profile_changed.emit(_current_profile)
	view_transition_finished.emit(_current_profile)
