class_name PlayerFish extends CharacterBody2D

signal region_motion_started(target_region: int)
signal region_motion_finished(current_region: int)
signal region_boundary_requested(direction: int, current_region: int)
signal jump_started(launch_velocity: Vector2)
signal jump_landed(current_region: int)
signal speed_boost_changed(active: bool, speed_multiplier: float)
signal death_animation_finished

enum JumpState {
	SWIMMING,
	CHARGING,
	AIRBORNE,
}

@onready var collision_shape: CollisionShape2D = %CollisionShape2D
@onready var mouth_anchor: Marker2D = %MouthAnchor
@onready var placeholder_visual: Node2D = %PlaceholderVisual
@onready var animated_visual: AnimatedSprite2D = %AnimatedVisual
@onready var jump_aim_preview: Line2D = %JumpAimPreview

var _region_controller: RegionController
var _layout: RegionLayout
var _forward_speed: float = 0.0
var _speed_boost_multiplier: float = 2.0
var _speed_boost_active: bool = false
var _region_move_duration: float = 0.1
var _jump_speed: float = 650.0
var _jump_gravity: float = 980.0
var _region_input_enabled: bool = true
var _region_motion_active: bool = false
var _move_elapsed: float = 0.0
var _move_start_y: float = 0.0
var _move_target_y: float = 0.0
var _death_animation_active: bool = false
var _death_tween: Tween
var _visual_animation: StringName = &"swim"
var _jump_state: JumpState = JumpState.SWIMMING
var _jump_target: Vector2 = Vector2.ZERO
var _has_jump_target: bool = false
var _jump_horizontal_impulse: float = 0.0
var _region_input_before_jump: bool = true


func _ready() -> void:
	animated_visual.animation_finished.connect(_on_animated_visual_animation_finished)
	_set_visual_animation(&"swim", true)
	set_physics_process(false)


func configure(controller: RegionController, layout: RegionLayout, config: WorldConfig) -> void:
	_region_controller = controller
	_layout = layout
	_forward_speed = config.forward_speed
	_speed_boost_multiplier = config.speed_boost_multiplier
	_speed_boost_active = false
	_region_move_duration = config.region_move_duration
	_jump_speed = config.jump_speed
	_jump_gravity = config.jump_gravity
	_jump_state = JumpState.SWIMMING
	_has_jump_target = false
	jump_aim_preview.visible = false
	global_position = Vector2(
		config.player_start_x,
		_layout.get_safe_center_y(_region_controller.get_current_region(), get_body_half_height())
	)
	_set_visual_animation(&"swim", true)
	set_physics_process(true)


func set_region_input_enabled(enabled: bool) -> void:
	_region_input_enabled = enabled


func stop_for_settlement() -> void:
	cancel_jump()
	_set_speed_boost_active(false)
	_region_input_enabled = false
	_forward_speed = 0.0
	velocity = Vector2.ZERO
	set_physics_process(false)


func freeze_for_predator_capture() -> void:
	stop_for_settlement()


func play_eat_animation() -> bool:
	if _death_animation_active or not _has_visual_animation(&"eat"):
		return false
	_set_visual_animation(&"eat", true)
	return true


func play_death_animation(surface_float_y: float, duration: float) -> void:
	if _death_animation_active:
		return
	_death_animation_active = true
	cancel_jump()
	_set_speed_boost_active(false)
	_set_visual_animation(&"death")
	_region_input_enabled = false
	_forward_speed = 0.0
	velocity = Vector2.ZERO
	set_physics_process(false)
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	var safe_duration: float = maxf(duration, 0.0)
	if is_zero_approx(safe_duration):
		global_position.y = surface_float_y
		rotation = PI
		_finish_death_animation.call_deferred()
		return
	_death_tween = create_tween().set_parallel(true)
	_death_tween.set_trans(Tween.TRANS_SINE)
	_death_tween.set_ease(Tween.EASE_IN_OUT)
	_death_tween.tween_property(self, "global_position:y", surface_float_y, safe_duration)
	_death_tween.tween_property(self, "rotation", PI, safe_duration)
	_death_tween.finished.connect(_finish_death_animation, CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	if _region_controller == null or _layout == null:
		return
	_update_speed_boost_state()
	if _jump_state == JumpState.AIRBORNE:
		_process_airborne_jump(delta)
		return
	if _jump_state == JumpState.CHARGING:
		velocity = Vector2(get_current_forward_speed(), 0.0)
		move_and_slide()
		global_position.y = _layout.get_safe_center_y(5, get_body_half_height())
		return
	if _region_input_enabled and not _region_motion_active:
		if Input.is_action_just_pressed(&"move_up"):
			_try_begin_region_motion(-1)
		elif Input.is_action_just_pressed(&"move_down"):
			_try_begin_region_motion(1)
	var desired_y: float = global_position.y
	if _region_motion_active:
		_move_elapsed = minf(_move_elapsed + delta, _region_move_duration)
		var progress: float = 1.0 if is_zero_approx(_region_move_duration) else _move_elapsed / _region_move_duration
		var eased_progress: float = smoothstep(0.0, 1.0, progress)
		desired_y = lerpf(_move_start_y, _move_target_y, eased_progress)
	else:
		desired_y = _layout.clamp_body_center_to_region(
			desired_y,
			_region_controller.get_current_region(),
			get_body_half_height()
		)
	velocity = Vector2(get_current_forward_speed(), (desired_y - global_position.y) / maxf(delta, 0.0001))
	move_and_slide()
	if _region_motion_active and _move_elapsed >= _region_move_duration:
		global_position.y = _move_target_y
		_region_motion_active = false
		_region_controller.complete_move()
		_set_visual_animation(&"swim")
		region_motion_finished.emit(_region_controller.get_current_region())


func begin_jump_charge() -> bool:
	if (
		_death_animation_active
		or _jump_state != JumpState.SWIMMING
		or _region_motion_active
		or _region_controller == null
		or _region_controller.get_current_region() != 5
	):
		return false
	_region_input_before_jump = _region_input_enabled
	_region_input_enabled = false
	_jump_state = JumpState.CHARGING
	_has_jump_target = false
	jump_aim_preview.clear_points()
	jump_aim_preview.add_point(Vector2.ZERO)
	jump_aim_preview.add_point(Vector2.ZERO)
	jump_aim_preview.visible = true
	_set_visual_animation(&"jump_charge")
	return true


func set_jump_target(world_target: Vector2) -> bool:
	if _jump_state != JumpState.CHARGING:
		return false
	var offset: Vector2 = world_target - global_position
	if offset.x <= 0.0 or offset.y >= 0.0 or offset.length_squared() < 1.0:
		_has_jump_target = false
		jump_aim_preview.set_point_position(1, Vector2.ZERO)
		return false
	var launch_vertical_speed: float = offset.normalized().y * _jump_speed
	var maximum_rise: float = (
		launch_vertical_speed * launch_vertical_speed
		/ (2.0 * maxf(_jump_gravity, 0.01))
	)
	var required_rise: float = global_position.y - _layout.get_water_surface_y() + 1.0
	if maximum_rise < required_rise:
		_has_jump_target = false
		jump_aim_preview.set_point_position(1, Vector2.ZERO)
		return false
	_jump_target = world_target
	_has_jump_target = true
	jump_aim_preview.set_point_position(1, to_local(_jump_target))
	return true


func release_jump_charge() -> bool:
	if _jump_state != JumpState.CHARGING:
		return false
	if not _has_jump_target:
		cancel_jump_charge()
		return false
	var launch_direction: Vector2 = (_jump_target - global_position).normalized()
	var launch_impulse: Vector2 = launch_direction * _jump_speed
	_jump_state = JumpState.AIRBORNE
	_has_jump_target = false
	jump_aim_preview.visible = false
	_jump_horizontal_impulse = launch_impulse.x
	velocity = Vector2(
		get_current_forward_speed() + _jump_horizontal_impulse,
		launch_impulse.y
	)
	_set_visual_animation(&"jump_airborne")
	jump_started.emit(velocity)
	return true


func cancel_jump_charge() -> void:
	if _jump_state != JumpState.CHARGING:
		return
	_finish_jump(false)


func cancel_jump() -> void:
	if _jump_state == JumpState.SWIMMING:
		return
	_finish_jump(false)


func is_jump_charging() -> bool:
	return _jump_state == JumpState.CHARGING


func is_jump_active() -> bool:
	return _jump_state != JumpState.SWIMMING


func get_jump_state() -> JumpState:
	return _jump_state


func get_current_forward_speed() -> float:
	return _forward_speed * (_speed_boost_multiplier if _speed_boost_active else 1.0)


func is_speed_boost_active() -> bool:
	return _speed_boost_active


func get_speed_boost_multiplier() -> float:
	return _speed_boost_multiplier


func _process_airborne_jump(delta: float) -> void:
	velocity.x = get_current_forward_speed() + _jump_horizontal_impulse
	velocity.y += _jump_gravity * delta
	move_and_slide()
	var landing_y: float = _layout.get_safe_center_y(5, get_body_half_height())
	if velocity.y > 0.0 and global_position.y >= landing_y:
		global_position.y = landing_y
		_finish_jump(true)


func _finish_jump(landed: bool) -> void:
	_jump_state = JumpState.SWIMMING
	_has_jump_target = false
	_jump_horizontal_impulse = 0.0
	jump_aim_preview.visible = false
	velocity = Vector2(get_current_forward_speed(), 0.0)
	_region_input_enabled = _region_input_before_jump
	_set_visual_animation(&"swim")
	if landed and _region_controller != null:
		jump_landed.emit(_region_controller.get_current_region())


func _update_speed_boost_state() -> void:
	_set_speed_boost_active(
		_forward_speed > 0.0 and Input.is_action_pressed(&"accelerate")
	)


func _set_speed_boost_active(active: bool) -> void:
	if _speed_boost_active == active:
		return
	_speed_boost_active = active
	speed_boost_changed.emit(_speed_boost_active, _speed_boost_multiplier)


func _try_begin_region_motion(direction: int) -> void:
	var target_region: int = _region_controller.try_begin_move(direction)
	if target_region < 1:
		region_boundary_requested.emit(signi(direction), _region_controller.get_current_region())
		return
	_region_motion_active = true
	_move_elapsed = 0.0
	_move_start_y = global_position.y
	_move_target_y = _layout.get_safe_center_y(target_region, get_body_half_height())
	_set_visual_animation(&"rise" if direction < 0 else &"dive")
	region_motion_started.emit(target_region)


func get_body_half_height() -> float:
	if collision_shape == null or collision_shape.shape == null:
		return 0.0
	var rectangle_shape: RectangleShape2D = collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		push_error("PlayerFish currently requires a RectangleShape2D for lane bounds.")
		return 0.0
	return (
		absf(collision_shape.position.y)
		+ rectangle_shape.size.y * 0.5 * absf(collision_shape.scale.y)
	)


func get_mouth_world_position() -> Vector2:
	if mouth_anchor == null:
		return global_position
	return mouth_anchor.global_position


func is_fully_inside_current_region() -> bool:
	if _layout == null or _region_controller == null or _region_motion_active:
		return false
	return _layout.is_body_inside_region(
		global_position.y,
		_region_controller.get_current_region(),
		get_body_half_height()
	)


func is_region_input_enabled() -> bool:
	return _region_input_enabled


func is_death_animation_active() -> bool:
	return _death_animation_active


func get_visual_animation_name() -> StringName:
	return _visual_animation


func _finish_death_animation() -> void:
	death_animation_finished.emit()


func _on_animated_visual_animation_finished() -> void:
	if _visual_animation != &"eat":
		return
	_set_visual_animation(_get_contextual_visual_animation(), true)


func _get_contextual_visual_animation() -> StringName:
	match _jump_state:
		JumpState.CHARGING:
			return &"jump_charge"
		JumpState.AIRBORNE:
			return &"jump_airborne"
	if _region_motion_active:
		return &"rise" if _move_target_y < _move_start_y else &"dive"
	return &"swim"


func _has_visual_animation(animation_name: StringName) -> bool:
	var frames: SpriteFrames = animated_visual.sprite_frames
	return (
		frames != null
		and frames.has_animation(animation_name)
		and frames.get_frame_count(animation_name) > 0
	)


func _set_visual_animation(animation_name: StringName, force: bool = false) -> void:
	if not force and _visual_animation == animation_name:
		return
	_visual_animation = animation_name
	var has_animation_frames: bool = _has_visual_animation(animation_name)
	placeholder_visual.visible = not has_animation_frames
	animated_visual.visible = has_animation_frames
	if has_animation_frames:
		animated_visual.play(animation_name)
	else:
		animated_visual.stop()
