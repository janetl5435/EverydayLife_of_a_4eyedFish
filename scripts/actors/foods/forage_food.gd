class_name ForageFood extends Area2D

signal collected(food: ForageFood, food_id: StringName, energy_value: int)
signal retired(food: ForageFood)

enum State {
	INACTIVE,
	AVAILABLE,
	CLAIMED,
	RETIRING,
}

@export var retain_after_collection: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var placeholder_visual: Node2D = get_node_or_null("PlaceholderVisual") as Node2D
@onready var animated_visual: AnimatedSprite2D = %AnimatedVisual
@onready var name_label: Label = %NameLabel

var _definition: FoodDefinition
var _opportunity_id: int = -1
var _state: State = State.INACTIVE
var _camera: Camera2D
var _elapsed_time: float = 0.0
var _world_velocity_x: float = 0.0
var _finish_tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	animated_visual.animation_finished.connect(_on_visual_animation_finished)
	monitoring = false
	monitorable = false
	set_physics_process(false)


func configure(
	definition: FoodDefinition,
	opportunity_id: int,
	spawn_position: Vector2,
	camera: Camera2D
) -> bool:
	if definition == null or not definition.is_valid():
		push_error("ForageFood requires a valid FoodDefinition.")
		return false
	_definition = definition
	_opportunity_id = opportunity_id
	_camera = camera
	_elapsed_time = 0.0
	_world_velocity_x = definition.world_velocity_x
	_state = State.AVAILABLE
	global_position = spawn_position
	modulate = Color.WHITE
	scale = Vector2.ONE
	name_label.text = "%s  +%d" % [_definition.display_name, _definition.energy_value]
	monitoring = true
	monitorable = true
	_set_visual_animation(&"idle", true)
	set_physics_process(true)
	return true


func try_collect_by_interaction(player: PlayerFish, current_region: int) -> bool:
	if not can_interact(player, current_region):
		return false
	return collect()


func can_interact(player: PlayerFish, _current_region: int) -> bool:
	return (
		_state == State.AVAILABLE
		and _definition != null
		and _definition.collection_method == FoodDefinition.CollectionMethod.INTERACT
		and player != null
		and contains_world_point(player.get_mouth_world_position())
	)


func contains_world_point(world_point: Vector2) -> bool:
	if collision_shape == null or collision_shape.shape == null or collision_shape.disabled:
		return false
	var local_point: Vector2 = collision_shape.to_local(world_point)
	var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
	if circle_shape != null:
		return local_point.length_squared() <= circle_shape.radius * circle_shape.radius
	var rectangle_shape: RectangleShape2D = collision_shape.shape as RectangleShape2D
	if rectangle_shape != null:
		var half_size: Vector2 = rectangle_shape.size * 0.5
		return absf(local_point.x) <= half_size.x and absf(local_point.y) <= half_size.y
	push_error("ForageFood mouth-point checks require a CircleShape2D or RectangleShape2D.")
	return false


func collect() -> bool:
	if _state != State.AVAILABLE or _definition == null:
		return false
	_state = State.CLAIMED
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	set_physics_process(false)
	_set_visual_animation(&"collected")
	collected.emit(self, _definition.food_id, _definition.energy_value)
	if retain_after_collection:
		if not _has_visual_animation(&"collected"):
			_finish_retained_collection.call_deferred()
		return true
	_finish_tween = create_tween().set_parallel(true)
	_finish_tween.set_trans(Tween.TRANS_BACK)
	_finish_tween.set_ease(Tween.EASE_IN)
	_finish_tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.16)
	_finish_tween.tween_property(self, "modulate:a", 0.0, 0.16)
	_finish_tween.finished.connect(_finish_and_free, CONNECT_ONE_SHOT)
	return true


func retire_unselected() -> void:
	if _state != State.AVAILABLE:
		return
	_state = State.RETIRING
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	modulate = Color(0.72, 0.72, 0.72, 0.58)
	_set_visual_animation(&"retire")


func stop_and_free() -> void:
	if _state == State.INACTIVE:
		return
	if _finish_tween != null and _finish_tween.is_valid():
		_finish_tween.kill()
	_state = State.INACTIVE
	monitoring = false
	monitorable = false
	set_physics_process(false)
	retired.emit(self)
	queue_free()


func get_definition() -> FoodDefinition:
	return _definition


func get_food_id() -> StringName:
	if _definition == null:
		return &""
	return _definition.food_id


func get_opportunity_id() -> int:
	return _opportunity_id


func get_state() -> State:
	return _state


func is_available() -> bool:
	return _state == State.AVAILABLE


func is_retained_after_collection() -> bool:
	return retain_after_collection


func set_world_velocity_x(velocity: float) -> void:
	_world_velocity_x = velocity


func _physics_process(delta: float) -> void:
	if _state != State.AVAILABLE and _state != State.RETIRING:
		return
	_elapsed_time += delta
	global_position.x += _world_velocity_x * delta
	if _has_left_camera_margin():
		_finish_and_free()


func _has_left_camera_margin() -> bool:
	if _camera == null:
		return false
	var half_view_width: float = get_viewport_rect().size.x * 0.5 / _camera.zoom.x
	var camera_left: float = _camera.global_position.x - half_view_width
	var camera_right: float = _camera.global_position.x + half_view_width
	var recycle_margin: float = 240.0
	return (
		global_position.x < camera_left - recycle_margin
		or global_position.x > camera_right + recycle_margin
	)


func _on_body_entered(body: Node2D) -> void:
	if (
		_state == State.AVAILABLE
		and _definition != null
		and _definition.collection_method == FoodDefinition.CollectionMethod.CONTACT
		and body is PlayerFish
	):
		collect()


func _on_visual_animation_finished() -> void:
	if _state == State.CLAIMED and retain_after_collection and animated_visual.animation == &"collected":
		_finish_retained_collection()


func _finish_retained_collection() -> void:
	if _state != State.CLAIMED or not retain_after_collection:
		return
	_state = State.RETIRING
	modulate = Color.WHITE
	scale = Vector2.ONE
	_set_visual_animation(&"retire", true)
	set_physics_process(true)


func _finish_and_free() -> void:
	if _state == State.INACTIVE:
		return
	_state = State.INACTIVE
	monitoring = false
	monitorable = false
	set_physics_process(false)
	retired.emit(self)
	queue_free()


func _set_visual_animation(animation_name: StringName, force: bool = false) -> void:
	var frames: SpriteFrames = animated_visual.sprite_frames
	if frames != null and frames.has_animation(animation_name):
		animated_visual.animation = animation_name
	var has_animation_frames: bool = _has_visual_animation(animation_name)
	if placeholder_visual != null:
		placeholder_visual.visible = not has_animation_frames
	animated_visual.visible = has_animation_frames
	if has_animation_frames:
		if force or animated_visual.animation != animation_name or not animated_visual.is_playing():
			animated_visual.play(animation_name)
	else:
		animated_visual.stop()


func _has_visual_animation(animation_name: StringName) -> bool:
	var frames: SpriteFrames = animated_visual.sprite_frames
	return (
		frames != null
		and frames.has_animation(animation_name)
		and frames.get_frame_count(animation_name) > 0
	)
