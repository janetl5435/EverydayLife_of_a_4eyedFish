extends Node

signal achievement_unlocked(achievement_id: StringName)
signal streak_changed(mode: int, streak_count: int)

const ACHIEVEMENT_EXTREME_DRY_EYE: StringName = &"extreme_dry_eye"
const ACHIEVEMENT_SURVIVAL_SKILL: StringName = &"survival_skill"
const ACHIEVEMENT_DELICIOUS_SHELLFISH: StringName = &"delicious_shellfish"
const ACHIEVEMENT_FISH_SPRING: StringName = &"fish_spring"
const ACHIEVEMENT_FISH_HUNGRY: StringName = &"fish_hungry"
const ACHIEVEMENT_FISH_FULL: StringName = &"fish_full"
const ACHIEVEMENT_FISH_GONE: StringName = &"fish_gone"

const EXTREME_DRY_EYE_SECONDS: float = 9.0
const REQUIRED_STREAK: int = 3
const FORAGE_ENERGY_THRESHOLD: int = 13
const HUNGRY_MAX_ENERGY: float = 2.0
const FULL_MIN_ENERGY_EXCLUSIVE: float = 30.0

const SAVE_SECTION: StringName = &"achievements"
const SAVE_KEY_UNLOCKED: StringName = &"unlocked"
const SAVE_KEY_PATROL_STREAK: StringName = &"patrol_streak"
const SAVE_KEY_FORAGE_STREAK: StringName = &"forage_streak"

const DEFINITION_PATHS: Array[String] = [
	"res://data/achievements/extreme_dry_eye.tres",
	"res://data/achievements/survival_skill.tres",
	"res://data/achievements/delicious_shellfish.tres",
	"res://data/achievements/fish_spring.tres",
	"res://data/achievements/fish_hungry.tres",
	"res://data/achievements/fish_full.tres",
	"res://data/achievements/fish_gone.tres",
]

var _unlocked_ids: PackedStringArray = PackedStringArray()
var _patrol_streak: int = 0
var _forage_streak: int = 0
var _definitions: Array[AchievementDefinition] = []


func _ready() -> void:
	_load_definitions()
	SaveService.erase_section(SAVE_SECTION)
	reset_session_progress()


func reload_from_save() -> void:
	reset_session_progress()


func reset_session_progress() -> void:
	_unlocked_ids = PackedStringArray()
	_patrol_streak = 0
	_forage_streak = 0


func unlock(achievement_id: StringName) -> bool:
	if get_definition(achievement_id) == null:
		push_error("Unknown achievement ID: %s" % String(achievement_id))
		return false
	var stored_id: String = String(achievement_id)
	if _unlocked_ids.has(stored_id):
		return false
	_unlocked_ids.append(stored_id)
	achievement_unlocked.emit(achievement_id)
	return true


func evaluate_run(result: RunResult) -> Array[StringName]:
	var new_unlocks: Array[StringName] = []
	if result == null:
		return new_unlocks
	match result.outcome:
		RunResult.Outcome.NATURAL_FINISH:
			_set_streak(result.mode, 0)
			if result.energy <= HUNGRY_MAX_ENERGY and unlock(ACHIEVEMENT_FISH_HUNGRY):
				new_unlocks.append(ACHIEVEMENT_FISH_HUNGRY)
			if result.energy > FULL_MIN_ENERGY_EXCLUSIVE and unlock(ACHIEVEMENT_FISH_FULL):
				new_unlocks.append(ACHIEVEMENT_FISH_FULL)
		RunResult.Outcome.FAILURE:
			_set_streak(result.mode, 0)
			if unlock(ACHIEVEMENT_FISH_GONE):
				new_unlocks.append(ACHIEVEMENT_FISH_GONE)
		RunResult.Outcome.ABANDONED:
			_set_streak(result.mode, 0)
		_:
			pass
	result.streak_count = get_streak(result.mode)
	return new_unlocks


func qualifies_for_extreme_dry_eye(exposed_seconds: float) -> bool:
	return exposed_seconds >= EXTREME_DRY_EYE_SECONDS


func is_unlocked(achievement_id: StringName) -> bool:
	return _unlocked_ids.has(String(achievement_id))


func get_unlocked_ids() -> PackedStringArray:
	return _unlocked_ids.duplicate()


func get_definitions() -> Array[AchievementDefinition]:
	var result: Array[AchievementDefinition] = []
	result.append_array(_definitions)
	return result


func get_definition(achievement_id: StringName) -> AchievementDefinition:
	for definition: AchievementDefinition in _definitions:
		if definition.achievement_id == achievement_id:
			return definition
	return null


func get_streak(mode: int) -> int:
	if mode == AppFlow.GameMode.PATROL:
		return _patrol_streak
	if mode == AppFlow.GameMode.FORAGE:
		return _forage_streak
	return 0


func _set_streak(mode: int, value: int) -> void:
	var safe_value: int = clampi(value, 0, REQUIRED_STREAK)
	if mode == AppFlow.GameMode.PATROL:
		if _patrol_streak == safe_value:
			return
		_patrol_streak = safe_value
		streak_changed.emit(mode, _patrol_streak)
	elif mode == AppFlow.GameMode.FORAGE:
		if _forage_streak == safe_value:
			return
		_forage_streak = safe_value
		streak_changed.emit(mode, _forage_streak)


func _load_definitions() -> void:
	_definitions.clear()
	for path: String in DEFINITION_PATHS:
		var definition: AchievementDefinition = load(path) as AchievementDefinition
		if definition == null or not definition.is_valid():
			push_error("Could not load a valid achievement definition: %s" % path)
			continue
		_definitions.append(definition)
