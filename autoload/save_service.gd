extends Node

const SAVE_PATH: String = "user://save.cfg"

var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
	var error: Error = _config.load(SAVE_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load save data (error %d)." % error)


func get_value(section: StringName, key: StringName, default_value: Variant = null) -> Variant:
	return _config.get_value(String(section), String(key), default_value)


func set_value(section: StringName, key: StringName, value: Variant) -> void:
	_config.set_value(String(section), String(key), value)
	_flush()


func erase_section(section: StringName) -> void:
	if not _config.has_section(String(section)):
		return
	_config.erase_section(String(section))
	_flush()


func _flush() -> void:
	var error: Error = _config.save(SAVE_PATH)
	if error != OK:
		push_error("Could not save data (error %d)." % error)
