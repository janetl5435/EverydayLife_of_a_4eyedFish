extends Node


func _ready() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	var result: RunResult = RunResult.new()
	result.mode = AppFlow.GameMode.FORAGE
	result.outcome = RunResult.Outcome.NATURAL_FINISH
	result.success = true
	result.travelled_distance = 5000.0
	result.energy = 18
	result.streak_count = 2
	result.add_new_unlock(AchievementService.ACHIEVEMENT_DELICIOUS_SHELLFISH)
	result.add_new_unlock(AchievementService.ACHIEVEMENT_FISH_SPRING)
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	AppFlow.store_run_result(result)
	var result_scene: PackedScene = load(
		"res://scenes/ui/result_screen.tscn"
	) as PackedScene
	var result_screen: Control = result_scene.instantiate() as Control
	add_child(result_screen)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://result_screen_preview.png"
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save result preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("RESULT_SCREEN_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
