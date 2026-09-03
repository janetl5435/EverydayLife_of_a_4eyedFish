class_name RunResult extends Resource

enum Outcome {
	NONE,
	NATURAL_FINISH,
	FAILURE,
	ABANDONED,
	DEBUG_FINISH,
}

var mode: int = 0
var start_world_x: float = 0.0
var travelled_distance: float = 0.0
var energy: float = 0.0
var success: bool = false
var outcome: Outcome = Outcome.NONE
var failure_reason: StringName = &""
var streak_count: int = 0
var newly_unlocked_ids: Array[StringName] = []


func add_new_unlock(achievement_id: StringName) -> void:
	if achievement_id == &"" or newly_unlocked_ids.has(achievement_id):
		return
	newly_unlocked_ids.append(achievement_id)


func is_natural_finish() -> bool:
	return outcome == Outcome.NATURAL_FINISH


func is_failure() -> bool:
	return outcome == Outcome.FAILURE


func is_abandoned() -> bool:
	return outcome == Outcome.ABANDONED
