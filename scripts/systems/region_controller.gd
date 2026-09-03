class_name RegionController extends Node

signal bounds_changed(min_region: int, max_region: int)
signal region_move_started(from_region: int, to_region: int)
signal region_changed(current_region: int, previous_region: int)

var _layout: RegionLayout
var _min_region: int = 1
var _max_region: int = RegionLayout.REGION_COUNT
var _current_region: int = 1
var _target_region: int = 1
var _move_in_progress: bool = false


func configure(layout: RegionLayout, min_region: int, max_region: int, start_region: int) -> bool:
	if not layout.is_valid():
		push_error("Region layout is invalid.")
		return false
	if not _are_bounds_valid(layout, min_region, max_region):
		return false
	if start_region < min_region or start_region > max_region:
		push_error("Start region %d is outside active bounds %d–%d." % [start_region, min_region, max_region])
		return false
	_layout = layout
	_min_region = min_region
	_max_region = max_region
	_current_region = start_region
	_target_region = start_region
	_move_in_progress = false
	bounds_changed.emit(_min_region, _max_region)
	return true


func set_bounds(min_region: int, max_region: int) -> bool:
	if _layout == null or not _are_bounds_valid(_layout, min_region, max_region):
		return false
	if _move_in_progress:
		return false
	if _current_region < min_region or _current_region > max_region:
		push_error("Current region %d is outside requested bounds %d–%d." % [_current_region, min_region, max_region])
		return false
	_min_region = min_region
	_max_region = max_region
	bounds_changed.emit(_min_region, _max_region)
	return true


func try_begin_move(direction: int) -> int:
	if _layout == null or _move_in_progress or direction == 0:
		return -1
	var next_region: int = _current_region + signi(direction)
	if next_region < _min_region or next_region > _max_region:
		return -1
	_target_region = next_region
	_move_in_progress = true
	region_move_started.emit(_current_region, _target_region)
	return _target_region


func complete_move() -> void:
	if not _move_in_progress:
		return
	var previous_region: int = _current_region
	_current_region = _target_region
	_move_in_progress = false
	region_changed.emit(_current_region, previous_region)


func get_current_region() -> int:
	return _current_region


func get_current_y() -> float:
	if _layout == null:
		return 0.0
	return _layout.get_region_center_y(_current_region)


func get_min_region() -> int:
	return _min_region


func get_max_region() -> int:
	return _max_region


func is_move_in_progress() -> bool:
	return _move_in_progress


func _are_bounds_valid(layout: RegionLayout, min_region: int, max_region: int) -> bool:
	if not layout.is_valid_region(min_region) or not layout.is_valid_region(max_region):
		push_error("Region bounds must remain inside global regions 1–%d." % RegionLayout.REGION_COUNT)
		return false
	if min_region > max_region:
		push_error("Minimum region cannot be greater than maximum region.")
		return false
	return true
