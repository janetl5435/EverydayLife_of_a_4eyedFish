extends Node


func _ready() -> void:
	var failures: Array[String] = []
	if AchievementService.is_unlocked(AchievementService.ACHIEVEMENT_DELICIOUS_SHELLFISH):
		failures.append("Achievement unlock must reset in a new process.")
	if AchievementService.get_streak(AppFlow.GameMode.PATROL) != 0:
		failures.append("Patrol streak must reset in a new process.")
	if SettingsService.is_audio_enabled():
		failures.append("Audio setting did not survive a new process.")
	if not SettingsService.is_fullscreen_enabled():
		failures.append("Fullscreen setting did not survive a new process.")
	if failures.is_empty():
		print("STEP6_PERSISTENCE_READ_OK")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	get_tree().quit(1)
