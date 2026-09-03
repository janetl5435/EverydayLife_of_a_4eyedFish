extends Node


func _ready() -> void:
	SaveService.erase_section(AchievementService.SAVE_SECTION)
	SaveService.erase_section(SettingsService.SAVE_SECTION)
	AchievementService.reload_from_save()
	SettingsService.reload_from_save()
	AchievementService.unlock(AchievementService.ACHIEVEMENT_DELICIOUS_SHELLFISH)
	for _index: int in range(2):
		var result: RunResult = RunResult.new()
		result.mode = AppFlow.GameMode.PATROL
		result.outcome = RunResult.Outcome.NATURAL_FINISH
		result.success = true
		AchievementService.evaluate_run(result)
	SettingsService.set_audio_enabled(false)
	SettingsService.set_fullscreen_enabled(true)
	print("STEP6_PERSISTENCE_WRITE_OK")
	get_tree().quit(0)
