class_name FullScreenSequence extends Control

signal sequence_finished

@export var frames: Array[Texture2D] = []
@export_range(0.05, 3.0, 0.01) var frame_duration: float = 0.25
@export var play_on_ready: bool = true
@export var hide_when_finished: bool = false

@onready var frame_view: TextureRect = %FrameView
@onready var frame_timer: Timer = %FrameTimer

var _frame_index: int = -1
var _playing: bool = false
var _finished: bool = false


func _ready() -> void:
	frame_timer.timeout.connect(_on_frame_timer_timeout)
	if play_on_ready:
		play()


func play() -> void:
	frame_timer.stop()
	_frame_index = 0
	_finished = false
	_playing = true
	visible = true
	if frames.is_empty():
		_finish_sequence.call_deferred()
		return
	frame_view.texture = frames[_frame_index]
	frame_timer.start(frame_duration)


func stop() -> void:
	frame_timer.stop()
	_playing = false


func skip_to_end() -> void:
	if _finished:
		return
	if not frames.is_empty():
		_frame_index = frames.size() - 1
		frame_view.texture = frames[_frame_index]
	_finish_sequence()


func is_playing() -> bool:
	return _playing


func has_finished() -> bool:
	return _finished


func get_frame_count() -> int:
	return frames.size()


func get_current_frame_index() -> int:
	return _frame_index


func _on_frame_timer_timeout() -> void:
	if not _playing:
		return
	_frame_index += 1
	if _frame_index >= frames.size():
		_finish_sequence()
		return
	frame_view.texture = frames[_frame_index]


func _finish_sequence() -> void:
	if _finished:
		return
	frame_timer.stop()
	_playing = false
	_finished = true
	if hide_when_finished:
		visible = false
	sequence_finished.emit()
