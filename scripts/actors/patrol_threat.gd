class_name PatrolThreat extends Area2D

signal release_requested(threat: PatrolThreat)
signal attack_finished(threat: PatrolThreat)
signal bite_started(threat: PatrolThreat)

enum VisualState {
	IDLE,
	ALERT,
	CHASING,
	EATING,
}

@onready var visual_root: Node2D = %VisualRoot
@onready var vision_origin: Marker2D = %VisionOrigin
@onready var placeholder_visual: Node2D = %PlaceholderVisual
@onready var animated_visual: AnimatedSprite2D = %AnimatedVisual
@onready var warning_marker: Label = get_node_or_null("%WarningMarker") as Label

var _animal_type: ThreatEntry.AnimalType = ThreatEntry.AnimalType.BIRD
var _world_region: int = ThreatEntry.BIRD_WORLD_REGION
var _danger_region: int = ThreatEntry.BIRD_DANGER_REGION
var _direction: int = -1
var _speed: float = 0.0
var _active_time: float = 0.0
var _elapsed_time: float = 0.0
var _pool_active: bool = false
var _attacking: bool = false
var _danger_enabled: bool = false
var _forward_vision_distance: float = INF
var _visual_state: VisualState = VisualState.IDLE
var _camera: Camera2D
var _attack_tween: Tween


func _ready() -> void:
	deactivate()


func activate(entry: ThreatEntry, spawn_position: Vector2, camera: Camera2D) -> void:
	if entry == null or not entry.is_valid():
		push_error("PatrolThreat requires a valid ThreatEntry.")
		return
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	_animal_type = entry.animal_type
	_world_region = entry.world_region
	_danger_region = entry.get_danger_region()
	_direction = entry.direction
	_speed = entry.speed
	_active_time = entry.active_time
	_elapsed_time = 0.0
	_pool_active = true
	_attacking = false
	_danger_enabled = true
	_forward_vision_distance = INF
	_camera = camera
	global_position = spawn_position
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	visual_root.scale = Vector2(float(_direction), 1.0)
	_set_visual_state(VisualState.IDLE, true)
	if warning_marker != null:
		warning_marker.visible = false
		warning_marker.text = "!"
		warning_marker.modulate = Color.WHITE
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)


func deactivate() -> void:
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	_pool_active = false
	_attacking = false
	_danger_enabled = false
	_visual_state = VisualState.IDLE
	_camera = null
	animated_visual.stop()
	animated_visual.visible = false
	placeholder_visual.visible = true
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)


func set_warning_active(enabled: bool) -> void:
	var should_alert: bool = enabled and is_danger_active()
	if warning_marker != null:
		warning_marker.visible = should_alert
		if should_alert:
			warning_marker.modulate = Color.WHITE
	if should_alert:
		_set_visual_state(VisualState.ALERT)
	elif _pool_active and not _attacking:
		_set_visual_state(VisualState.IDLE)


func freeze_for_capture() -> void:
	if not _pool_active:
		return
	set_warning_active(false)
	set_physics_process(false)


func start_attack(target: Node2D, charge_duration: float, consume_duration: float) -> void:
	if not _pool_active or target == null or _attacking:
		return
	_attacking = true
	set_physics_process(false)
	_set_visual_state(VisualState.CHASING)
	if warning_marker != null:
		warning_marker.visible = true
		warning_marker.text = "!!"
		warning_marker.modulate = Color(1.0, 0.2, 0.12, 1.0)
	var safe_charge_duration: float = maxf(charge_duration, 0.0)
	var safe_consume_duration: float = maxf(consume_duration, 0.0)
	_attack_tween = create_tween()
	_attack_tween.set_trans(Tween.TRANS_QUAD)
	_attack_tween.set_ease(Tween.EASE_IN)
	_attack_tween.tween_property(self, "global_position", target.global_position, safe_charge_duration)
	_attack_tween.tween_callback(_begin_eating)
	_attack_tween.tween_property(self, "scale", Vector2(1.18, 1.18), safe_consume_duration)
	_attack_tween.finished.connect(_on_attack_tween_finished, CONNECT_ONE_SHOT)


func is_exposing_region(region_id: int) -> bool:
	return is_danger_active() and region_id == _danger_region


func is_exposing_player(region_id: int, player_world_x: float) -> bool:
	if not is_inside_camera_view() or not is_exposing_region(region_id):
		return false
	return is_player_in_forward_view(player_world_x)


func is_player_in_forward_view(player_world_x: float) -> bool:
	var vision_origin_x: float = get_vision_origin_world_x()
	var signed_forward_distance: float = (player_world_x - vision_origin_x) * float(_direction)
	return signed_forward_distance >= 0.0 and signed_forward_distance <= _forward_vision_distance


func is_player_beyond_forward_view(player_world_x: float) -> bool:
	var vision_origin_x: float = get_vision_origin_world_x()
	var signed_forward_distance: float = (player_world_x - vision_origin_x) * float(_direction)
	return signed_forward_distance > _forward_vision_distance


func set_forward_vision_distance(distance: float) -> void:
	_forward_vision_distance = maxf(distance, 0.0)


func get_forward_vision_distance() -> float:
	return _forward_vision_distance


func get_vision_origin_world_x() -> float:
	if vision_origin == null:
		return global_position.x
	return vision_origin.global_position.x


func is_danger_active() -> bool:
	return _pool_active and _danger_enabled and not _attacking


func is_pool_active() -> bool:
	return _pool_active


func is_attacking() -> bool:
	return _attacking


func is_encounter_danger_enabled() -> bool:
	return _danger_enabled


func get_visual_state() -> VisualState:
	return _visual_state


func get_visual_animation_name() -> StringName:
	return _get_animation_name(_visual_state)


func get_animal_type() -> ThreatEntry.AnimalType:
	return _animal_type


func get_world_region() -> int:
	return _world_region


func get_danger_region() -> int:
	return _danger_region


func _physics_process(delta: float) -> void:
	if not _pool_active or _attacking:
		return
	_elapsed_time += delta
	global_position.x += float(_direction) * _speed * delta
	if warning_marker != null and warning_marker.visible:
		if is_danger_active():
			warning_marker.modulate.a = 0.65 + 0.35 * sin(_elapsed_time * 18.0)
		else:
			warning_marker.visible = false
	if _has_left_camera_margin():
		release_requested.emit(self)


func _has_left_camera_margin() -> bool:
	if _camera == null:
		return false
	var half_view_width: float = get_viewport_rect().size.x * 0.5 / _camera.zoom.x
	var camera_left: float = _camera.global_position.x - half_view_width
	var camera_right: float = _camera.global_position.x + half_view_width
	var recycle_margin: float = 220.0
	return (
		global_position.x < camera_left - recycle_margin
		or global_position.x > camera_right + recycle_margin
	)


func is_inside_camera_view() -> bool:
	if _camera == null:
		return false
	var half_view_width: float = get_viewport_rect().size.x * 0.5 / _camera.zoom.x
	var camera_left: float = _camera.global_position.x - half_view_width
	var camera_right: float = _camera.global_position.x + half_view_width
	return global_position.x >= camera_left and global_position.x <= camera_right


func _on_attack_tween_finished() -> void:
	attack_finished.emit(self)


func _begin_eating() -> void:
	if _pool_active and _attacking:
		_set_visual_state(VisualState.EATING)
		bite_started.emit(self)


func _set_visual_state(state: VisualState, force: bool = false) -> void:
	if not force and _visual_state == state:
		return
	_visual_state = state
	var animation_name: StringName = _get_animation_name(state)
	var frames: SpriteFrames = animated_visual.sprite_frames
	var has_animation_frames: bool = (
		frames != null
		and frames.has_animation(animation_name)
		and frames.get_frame_count(animation_name) > 0
	)
	placeholder_visual.visible = not has_animation_frames
	animated_visual.visible = has_animation_frames
	if has_animation_frames:
		animated_visual.play(animation_name)
	else:
		animated_visual.stop()


func _get_animation_name(state: VisualState) -> StringName:
	match state:
		VisualState.ALERT:
			return &"alert"
		VisualState.CHASING:
			return &"chase"
		VisualState.EATING:
			return &"eat"
		_:
			return &"idle"
