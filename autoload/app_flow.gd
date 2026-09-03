extends Node

signal mode_started(mode: GameMode)
signal scene_changed(scene_path: String)
signal run_result_stored(result: RunResult)

enum GameMode {
	NONE,
	PATROL,
	FORAGE,
}

const INTRO_SCENE: String = "res://scenes/ui/intro.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const COMPENDIUM_SCENE: String = "res://scenes/ui/compendium.tscn"
const SETTINGS_SCENE: String = "res://scenes/ui/settings_screen.tscn"
const GAMEPLAY_SCENE: String = "res://scenes/gameplay/gameplay_root.tscn"
const RESULT_SCENE: String = "res://scenes/ui/result_screen.tscn"
const DEATH_SCENE: String = "res://scenes/ui/death_restart.tscn"
const FAILURE_UNKNOWN: StringName = &"unknown"
const FAILURE_DRY_EYES: StringName = &"dry_eyes"
const FAILURE_PREDATOR: StringName = &"predator"
const FAILURE_ENERGY: StringName = &"energy"
const FAILURE_DEBUG: StringName = &"debug"

var current_mode: GameMode = GameMode.NONE
var last_run_succeeded: bool = false
var last_failure_reason: StringName = FAILURE_UNKNOWN
var last_run_result: RunResult
var _scene_change_pending: bool = false


func open_intro() -> void:
	_change_scene(INTRO_SCENE)


func open_main_menu() -> void:
	get_tree().paused = false
	current_mode = GameMode.NONE
	last_failure_reason = FAILURE_UNKNOWN
	_change_scene(MAIN_MENU_SCENE)


func open_compendium() -> void:
	_change_scene(COMPENDIUM_SCENE)


func open_settings() -> void:
	_change_scene(SETTINGS_SCENE)


func begin_journey() -> void:
	begin_mode(GameMode.FORAGE)


func begin_mode(mode: GameMode) -> void:
	if mode == GameMode.NONE:
		push_error("Cannot begin gameplay without a selected mode.")
		return
	get_tree().paused = false
	current_mode = mode
	last_run_succeeded = false
	last_failure_reason = FAILURE_UNKNOWN
	last_run_result = null
	mode_started.emit(mode)
	_change_scene(GAMEPLAY_SCENE)


func store_run_result(result: RunResult) -> bool:
	if result == null:
		push_error("Cannot store a null run result.")
		return false
	if last_run_result == result:
		return true
	last_run_result = result
	last_run_succeeded = result.success
	last_failure_reason = result.failure_reason if result.is_failure() else FAILURE_UNKNOWN
	run_result_stored.emit(result)
	return true


func complete_run(result: RunResult) -> void:
	if store_run_result(result):
		_change_scene(RESULT_SCENE)


func open_death_for_result(result: RunResult) -> void:
	if store_run_result(result):
		_change_scene(DEATH_SCENE)


func finish_current_run() -> void:
	if current_mode == GameMode.NONE:
		push_error("Cannot finish a run before selecting a mode.")
		return
	var result: RunResult = RunResult.new()
	result.mode = current_mode
	result.success = true
	result.outcome = RunResult.Outcome.DEBUG_FINISH
	complete_run(result)


func fail_current_run(reason: StringName = FAILURE_UNKNOWN) -> void:
	if current_mode == GameMode.NONE:
		push_error("Cannot fail a run before selecting a mode.")
		return
	var result: RunResult = RunResult.new()
	result.mode = current_mode
	result.success = false
	result.outcome = RunResult.Outcome.FAILURE
	result.failure_reason = reason
	open_death_for_result(result)


func retry_current_mode() -> void:
	if current_mode == GameMode.NONE:
		open_main_menu()
		return
	get_tree().paused = false
	last_run_succeeded = false
	last_failure_reason = FAILURE_UNKNOWN
	last_run_result = null
	_change_scene(GAMEPLAY_SCENE)


func get_current_mode_label() -> String:
	return get_mode_label(current_mode)


func get_mode_label(mode: int) -> String:
	match mode:
		GameMode.PATROL:
			return "巡游模式"
		GameMode.FORAGE:
			return "旅程"
		_:
			return "未选择模式"


func get_last_failure_reason_label() -> String:
	return get_failure_reason_label(last_failure_reason)


func get_failure_reason_label(reason: StringName) -> String:
	match reason:
		FAILURE_DRY_EYES:
			return "眼睛过于干燥，未能及时润湿"
		FAILURE_PREDATOR:
			return "被捕食者发现并捕获"
		FAILURE_ENERGY:
			return "能量耗尽，未能继续旅程"
		FAILURE_DEBUG:
			return "测试失败流程"
		_:
			return "本次旅程未能继续"


func quit_game() -> void:
	get_tree().quit()


func _change_scene(scene_path: String) -> void:
	if _scene_change_pending:
		return
	_scene_change_pending = true
	var error: Error = get_tree().change_scene_to_file(scene_path)
	_scene_change_pending = false
	if error != OK:
		push_error("Failed to change scene to %s (error %d)." % [scene_path, error])
		return
	scene_changed.emit(scene_path)
