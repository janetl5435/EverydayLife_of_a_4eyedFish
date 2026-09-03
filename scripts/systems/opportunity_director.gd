class_name OpportunityDirector extends Node

signal opportunity_spawned(opportunity_id: int, air_food_id: StringName, underwater_food_id: StringName)
signal opportunity_resolved(opportunity_id: int, collected_food_id: StringName)
signal food_collected(food_id: StringName, energy_value: int)

@export_group("Food definitions")
@export var air_food_definition: FoodDefinition
@export var underwater_food_definitions: Array[FoodDefinition] = []

@export_group("Distance scheduling")
@export_range(0.0, 5000.0, 20.0) var first_opportunity_distance: float = 420.0
@export_range(200.0, 5000.0, 20.0) var opportunity_spacing: float = 760.0
@export_range(300.0, 5000.0, 20.0) var opportunity_window_distance: float = 1050.0
@export_range(0.0, 300.0, 10.0) var spawn_edge_inset: float = 90.0

var _player: PlayerFish
var _layout: RegionLayout
var _camera: Camera2D
var _air_root: Node2D
var _underwater_root: Node2D
var _enabled: bool = false
var _automatic_spawning_enabled: bool = true
var _next_spawn_x: float = 0.0
var _pair_deadline_x: float = 0.0
var _next_opportunity_id: int = 1
var _underwater_cursor: int = 0
var _current_opportunity_id: int = -1
var _current_air_food: ForageFood
var _current_underwater_food: ForageFood
var _spawned_foods: Array[ForageFood] = []


func _ready() -> void:
	set_physics_process(false)


func configure(
	player: PlayerFish,
	layout: RegionLayout,
	camera: Camera2D,
	air_root: Node2D,
	underwater_root: Node2D,
	enabled: bool
) -> bool:
	_player = player
	_layout = layout
	_camera = camera
	_air_root = air_root
	_underwater_root = underwater_root
	_enabled = enabled
	if not _enabled:
		set_physics_process(false)
		return true
	if (
		_player == null
		or _layout == null
		or _camera == null
		or _air_root == null
		or _underwater_root == null
		or air_food_definition == null
		or not air_food_definition.is_valid()
		or underwater_food_definitions.is_empty()
	):
		push_error("OpportunityDirector is missing required forage dependencies or food data.")
		_enabled = false
		return false
	for definition: FoodDefinition in underwater_food_definitions:
		if definition == null or not definition.is_valid():
			push_error("OpportunityDirector contains an invalid underwater FoodDefinition.")
			_enabled = false
			return false
	_next_spawn_x = _player.global_position.x + first_opportunity_distance
	set_physics_process(_automatic_spawning_enabled)
	return true


func stop_all() -> void:
	_enabled = false
	set_physics_process(false)
	_current_opportunity_id = -1
	_current_air_food = null
	_current_underwater_food = null
	var foods_to_free: Array[ForageFood] = _spawned_foods.duplicate()
	_spawned_foods.clear()
	for food: ForageFood in foods_to_free:
		if is_instance_valid(food):
			food.stop_and_free()


func force_spawn_pair(underwater_food_id: StringName = &"") -> bool:
	if not _enabled or _current_opportunity_id >= 0:
		return false
	var underwater_definition: FoodDefinition = _find_underwater_definition(underwater_food_id)
	if underwater_definition == null:
		return false
	return _spawn_pair(underwater_definition)


func set_automatic_spawning_enabled(enabled: bool) -> void:
	_automatic_spawning_enabled = enabled
	set_physics_process(_enabled and _automatic_spawning_enabled)


func spawn_independent_food(
	food_id: StringName,
	event_id: int,
	spawn_position: Vector2,
	world_velocity_override: float = INF
) -> ForageFood:
	if not _enabled:
		return null
	var definition: FoodDefinition = get_food_definition(food_id)
	if definition == null:
		return null
	if food_id == &"algae" or food_id == &"shellfish":
		spawn_position.y = _layout.get_region_center_y(definition.spawn_region)
	var parent: Node2D = (
		_air_root
		if definition.collection_method == FoodDefinition.CollectionMethod.CONTACT
		else _underwater_root
	)
	var food: ForageFood = _instantiate_food(definition, event_id, spawn_position, parent)
	if food != null and world_velocity_override != INF:
		food.set_world_velocity_x(world_velocity_override)
	return food


func get_food_definition(food_id: StringName) -> FoodDefinition:
	if air_food_definition != null and air_food_definition.food_id == food_id:
		return air_food_definition
	return _find_underwater_definition(food_id)


func get_available_food_count() -> int:
	var count: int = 0
	for food: ForageFood in _spawned_foods:
		if is_instance_valid(food) and food.is_available():
			count += 1
	return count


func try_interact(player: PlayerFish, current_region: int) -> bool:
	var target: ForageFood = get_best_interactable(player, current_region)
	if target == null:
		return false
	return target.try_collect_by_interaction(player, current_region)


func try_interact_by_food_id(
	player: PlayerFish,
	current_region: int,
	food_id: StringName
) -> bool:
	var target: ForageFood = get_best_interactable_by_food_id(
		player,
		current_region,
		food_id
	)
	if target == null:
		return false
	return target.try_collect_by_interaction(player, current_region)


func get_best_interactable(player: PlayerFish, current_region: int) -> ForageFood:
	var best_target: ForageFood
	var best_distance: float = INF
	for food: ForageFood in _spawned_foods:
		if not is_instance_valid(food) or not food.can_interact(player, current_region):
			continue
		var distance: float = food.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = food
	return best_target


func get_best_interactable_by_food_id(
	player: PlayerFish,
	current_region: int,
	food_id: StringName
) -> ForageFood:
	var best_target: ForageFood
	var best_distance: float = INF
	for food: ForageFood in _spawned_foods:
		if (
			not is_instance_valid(food)
			or food.get_food_id() != food_id
			or not food.can_interact(player, current_region)
		):
			continue
		var distance: float = food.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = food
	return best_target


func get_active_foods() -> Array[ForageFood]:
	var active_foods: Array[ForageFood] = []
	for food: ForageFood in _spawned_foods:
		if is_instance_valid(food):
			active_foods.append(food)
	return active_foods


func get_current_air_food() -> ForageFood:
	return _current_air_food


func get_current_underwater_food() -> ForageFood:
	return _current_underwater_food


func get_current_opportunity_id() -> int:
	return _current_opportunity_id


func is_running() -> bool:
	return _enabled


func _physics_process(_delta: float) -> void:
	if not _enabled or not _automatic_spawning_enabled or _player == null:
		return
	_cleanup_invalid_foods()
	if _current_opportunity_id >= 0:
		if _player.global_position.x >= _pair_deadline_x:
			_expire_current_pair()
		return
	if _player.global_position.x >= _next_spawn_x:
		_spawn_next_pair()


func _spawn_next_pair() -> void:
	if underwater_food_definitions.is_empty():
		return
	var definition: FoodDefinition = underwater_food_definitions[
		_underwater_cursor % underwater_food_definitions.size()
	]
	if _spawn_pair(definition):
		_underwater_cursor = (_underwater_cursor + 1) % underwater_food_definitions.size()


func _spawn_pair(underwater_definition: FoodDefinition) -> bool:
	var opportunity_id: int = _next_opportunity_id
	var spawn_x: float = _get_spawn_x()
	var air_food: ForageFood = _instantiate_food(
		air_food_definition,
		opportunity_id,
		Vector2(spawn_x, _layout.get_region_center_y(air_food_definition.spawn_region)),
		_air_root
	)
	if air_food == null:
		return false
	var underwater_food: ForageFood = _instantiate_food(
		underwater_definition,
		opportunity_id,
		Vector2(spawn_x, _layout.get_region_center_y(underwater_definition.spawn_region)),
		_underwater_root
	)
	if underwater_food == null:
		air_food.stop_and_free()
		return false
	_next_opportunity_id += 1
	_current_opportunity_id = opportunity_id
	_current_air_food = air_food
	_current_underwater_food = underwater_food
	_pair_deadline_x = _player.global_position.x + opportunity_window_distance
	opportunity_spawned.emit(
		opportunity_id,
		air_food_definition.food_id,
		underwater_definition.food_id
	)
	return true


func _instantiate_food(
	definition: FoodDefinition,
	opportunity_id: int,
	spawn_position: Vector2,
	parent: Node2D
) -> ForageFood:
	var food: ForageFood = definition.scene.instantiate() as ForageFood
	if food == null:
		push_error("Food scene root must use ForageFood: %s" % definition.food_id)
		return null
	parent.add_child(food)
	food.collected.connect(_on_food_collected)
	food.retired.connect(_on_food_retired)
	if not food.configure(definition, opportunity_id, spawn_position, _camera):
		food.queue_free()
		return null
	_spawned_foods.append(food)
	return food


func _on_food_collected(food: ForageFood, food_id: StringName, energy_value: int) -> void:
	food_collected.emit(food_id, energy_value)
	if food.get_opportunity_id() != _current_opportunity_id:
		return
	var resolved_opportunity_id: int = _current_opportunity_id
	_current_opportunity_id = -1
	_current_air_food = null
	_current_underwater_food = null
	_next_spawn_x = _player.global_position.x + opportunity_spacing
	opportunity_resolved.emit(resolved_opportunity_id, food_id)


func _on_food_retired(food: ForageFood) -> void:
	_spawned_foods.erase(food)
	if food == _current_air_food:
		_current_air_food = null
	elif food == _current_underwater_food:
		_current_underwater_food = null
	if (
		_current_opportunity_id >= 0
		and not is_instance_valid(_current_air_food)
		and not is_instance_valid(_current_underwater_food)
	):
		_resolve_missed_pair()


func _expire_current_pair() -> void:
	if _current_opportunity_id < 0:
		return
	var expired_id: int = _current_opportunity_id
	_current_opportunity_id = -1
	_current_air_food = null
	_current_underwater_food = null
	_next_spawn_x = _player.global_position.x + opportunity_spacing
	opportunity_resolved.emit(expired_id, &"")


func _resolve_missed_pair() -> void:
	var missed_id: int = _current_opportunity_id
	_current_opportunity_id = -1
	_current_air_food = null
	_current_underwater_food = null
	_next_spawn_x = _player.global_position.x + opportunity_spacing
	opportunity_resolved.emit(missed_id, &"")


func _cleanup_invalid_foods() -> void:
	for index: int in range(_spawned_foods.size() - 1, -1, -1):
		if not is_instance_valid(_spawned_foods[index]):
			_spawned_foods.remove_at(index)


func _find_underwater_definition(food_id: StringName) -> FoodDefinition:
	if String(food_id).is_empty():
		return underwater_food_definitions[_underwater_cursor % underwater_food_definitions.size()]
	for definition: FoodDefinition in underwater_food_definitions:
		if definition.food_id == food_id:
			return definition
	return null


func _get_spawn_x() -> float:
	var half_view_width: float = get_viewport().get_visible_rect().size.x * 0.5 / _camera.zoom.x
	return _camera.global_position.x + half_view_width - spawn_edge_inset
