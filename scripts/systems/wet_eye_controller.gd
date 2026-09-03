class_name WetEyeController extends Node

signal remaining_time_changed(remaining_time: float, maximum_time: float)
signal warning_started(remaining_time: float)
signal warning_ended
signal dive_accepted
signal exposed_changed(is_exposed: bool)
signal timed_out

var _maximum_time: float = 10.0
var _warning_time: float = 3.0
var _remaining_time: float = 10.0
var _is_exposed: bool = false
var _is_running: bool = false
var _warning_active: bool = false
var _timeout_pending: bool = false
var _has_timed_out: bool = false


func _ready() -> void:
	set_process(false)


func configure(maximum_time: float, warning_time: float) -> void:
	_maximum_time = maxf(maximum_time, 0.01)
	_warning_time = clampf(warning_time, 0.0, _maximum_time)
	_remaining_time = _maximum_time


func start(initially_exposed: bool) -> void:
	_remaining_time = _maximum_time
	_is_exposed = initially_exposed
	_is_running = true
	_has_timed_out = false
	_timeout_pending = false
	_set_warning_active(false)
	set_process(true)
	remaining_time_changed.emit(_remaining_time, _maximum_time)
	exposed_changed.emit(_is_exposed)
	_update_warning_state()


func stop() -> void:
	_is_running = false
	_timeout_pending = false
	set_process(false)
	_set_warning_active(false)


func accept_dive() -> bool:
	if not _is_running or _has_timed_out:
		return false
	_remaining_time = _maximum_time
	_timeout_pending = false
	_set_warning_active(false)
	_set_exposed_internal(false)
	remaining_time_changed.emit(_remaining_time, _maximum_time)
	dive_accepted.emit()
	return true


func set_exposed(exposed: bool) -> void:
	if _has_timed_out:
		return
	_set_exposed_internal(exposed)
	if _is_exposed:
		_update_warning_state()


func advance_time(delta: float) -> void:
	if delta <= 0.0 or not _is_running or not _is_exposed or _has_timed_out:
		return
	_remaining_time = maxf(_remaining_time - delta, 0.0)
	remaining_time_changed.emit(_remaining_time, _maximum_time)
	_update_warning_state()
	if is_zero_approx(_remaining_time) and not _timeout_pending:
		_timeout_pending = true
		_resolve_timeout.call_deferred()


func get_remaining_time() -> float:
	return _remaining_time


func get_maximum_time() -> float:
	return _maximum_time


func is_exposed() -> bool:
	return _is_exposed


func is_running() -> bool:
	return _is_running


func is_warning_active() -> bool:
	return _warning_active


func has_timed_out() -> bool:
	return _has_timed_out


func _process(delta: float) -> void:
	advance_time(delta)


func _set_exposed_internal(exposed: bool) -> void:
	if _is_exposed == exposed:
		return
	_is_exposed = exposed
	exposed_changed.emit(_is_exposed)


func _update_warning_state() -> void:
	var should_warn: bool = (
		_is_running
		and _is_exposed
		and _remaining_time > 0.0
		and _remaining_time <= _warning_time
	)
	_set_warning_active(should_warn)


func _set_warning_active(active: bool) -> void:
	if _warning_active == active:
		return
	_warning_active = active
	if _warning_active:
		warning_started.emit(_remaining_time)
	else:
		warning_ended.emit()


func _resolve_timeout() -> void:
	_timeout_pending = false
	if (
		not _is_running
		or not _is_exposed
		or _remaining_time > 0.0
		or _has_timed_out
	):
		return
	_has_timed_out = true
	_is_running = false
	set_process(false)
	_set_warning_active(false)
	timed_out.emit()
