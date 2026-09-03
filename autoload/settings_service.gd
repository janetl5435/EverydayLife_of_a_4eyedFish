extends Node

signal audio_enabled_changed(enabled: bool)
signal fullscreen_enabled_changed(enabled: bool)

const SAVE_SECTION: StringName = &"settings"
const SAVE_KEY_AUDIO: StringName = &"audio_enabled"
const SAVE_KEY_FULLSCREEN: StringName = &"fullscreen_enabled"

var _audio_enabled: bool = true
var _fullscreen_enabled: bool = false


func _ready() -> void:
	reload_from_save()


func reload_from_save() -> void:
	_audio_enabled = bool(SaveService.get_value(SAVE_SECTION, SAVE_KEY_AUDIO, true))
	_fullscreen_enabled = bool(
		SaveService.get_value(SAVE_SECTION, SAVE_KEY_FULLSCREEN, false)
	)
	_apply_audio_setting()
	_apply_fullscreen_setting()


func set_audio_enabled(enabled: bool) -> void:
	if _audio_enabled == enabled:
		return
	_audio_enabled = enabled
	SaveService.set_value(SAVE_SECTION, SAVE_KEY_AUDIO, _audio_enabled)
	_apply_audio_setting()
	audio_enabled_changed.emit(_audio_enabled)


func set_fullscreen_enabled(enabled: bool) -> void:
	if _fullscreen_enabled == enabled:
		return
	_fullscreen_enabled = enabled
	SaveService.set_value(SAVE_SECTION, SAVE_KEY_FULLSCREEN, _fullscreen_enabled)
	_apply_fullscreen_setting()
	fullscreen_enabled_changed.emit(_fullscreen_enabled)


func is_audio_enabled() -> bool:
	return _audio_enabled


func is_fullscreen_enabled() -> bool:
	return _fullscreen_enabled


func _apply_audio_setting() -> void:
	var master_bus_index: int = AudioServer.get_bus_index(&"Master")
	if master_bus_index >= 0:
		AudioServer.set_bus_mute(master_bus_index, not _audio_enabled)


func _apply_fullscreen_setting() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target_mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if _fullscreen_enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
