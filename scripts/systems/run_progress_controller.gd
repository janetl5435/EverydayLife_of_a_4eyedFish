class_name RunProgressController extends Node

signal run_finished(result: RunResult)
signal result_ready(result: RunResult)
signal distance_changed(travelled_distance: float, finish_distance: float)

var _player: Node2D
var _mode: int = 0
var _start_world_x: float = 0.0
var _finish_distance: float = 5000.0
var _travelled_distance: float = 0.0
var _energy: float = 0.0
var _success: bool = false
var _result_emitted: bool = false
var _new_unlock_ids: Array[StringName] = []


func _ready() -> void:
	set_physics_process(false)


func configure(
	player: Node2D,
	mode: int,
	start_world_x: float,
	finish_distance: float
) -> bool:
	if player == null or finish_distance <= 0.0:
		push_error("RunProgressController requires a player and a positive finish distance.")
		return false
	_player = player
	_mode = mode
	_start_world_x = start_world_x
	_finish_distance = finish_distance
	_travelled_distance = 0.0
	_energy = 0.0
	_success = false
	_result_emitted = false
	_new_unlock_ids.clear()
	set_physics_process(true)
	distance_changed.emit(_travelled_distance, _finish_distance)
	return true


func set_energy(energy: float) -> void:
	_energy = maxf(energy, 0.0)


func record_new_achievement(achievement_id: StringName) -> void:
	if achievement_id == &"" or _new_unlock_ids.has(achievement_id):
		return
	_new_unlock_ids.append(achievement_id)


func finish_naturally() -> bool:
	return _emit_result(RunResult.Outcome.NATURAL_FINISH, &"")


func finish_for_debug() -> bool:
	return _emit_result(RunResult.Outcome.DEBUG_FINISH, &"")


func fail(reason: StringName) -> bool:
	return _emit_result(RunResult.Outcome.FAILURE, reason)


func abandon() -> bool:
	return _emit_result(RunResult.Outcome.ABANDONED, &"abandoned")


func get_travelled_distance() -> float:
	_update_distance()
	return _travelled_distance


func get_finish_distance() -> float:
	return _finish_distance


func get_energy() -> float:
	return _energy


func has_emitted_result() -> bool:
	return _result_emitted


func is_running() -> bool:
	return not _result_emitted and is_physics_processing()


func _physics_process(_delta: float) -> void:
	if _result_emitted or _player == null:
		return
	_update_distance()
	distance_changed.emit(_travelled_distance, _finish_distance)
	if _travelled_distance >= _finish_distance:
		finish_naturally()


func _update_distance() -> void:
	if _player == null:
		return
	_travelled_distance = maxf(_player.global_position.x - _start_world_x, 0.0)


func _emit_result(outcome: RunResult.Outcome, reason: StringName) -> bool:
	if _result_emitted:
		return false
	_update_distance()
	_result_emitted = true
	_success = (
		outcome == RunResult.Outcome.NATURAL_FINISH
		or outcome == RunResult.Outcome.DEBUG_FINISH
	)
	set_physics_process(false)
	var result: RunResult = RunResult.new()
	result.mode = _mode
	result.start_world_x = _start_world_x
	result.travelled_distance = _travelled_distance
	result.energy = _energy
	result.success = _success
	result.outcome = outcome
	result.failure_reason = reason
	for achievement_id: StringName in _new_unlock_ids:
		result.add_new_unlock(achievement_id)
	if outcome == RunResult.Outcome.NATURAL_FINISH:
		run_finished.emit(result)
	result_ready.emit(result)
	return true
