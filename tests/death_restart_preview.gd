extends Node


func _ready() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	var result: RunResult = RunResult.new()
	result.mode = AppFlow.GameMode.FORAGE
	result.outcome = RunResult.Outcome.FAILURE
	result.failure_reason = AppFlow.FAILURE_DRY_EYES
	result.travelled_distance = 1520.0
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	AppFlow.store_run_result(result)
	var death_scene: PackedScene = load(
		"res://scenes/ui/death_restart.tscn"
	) as PackedScene
	var death: Control = death_scene.instantiate() as Control
	add_child(death)
	await get_tree().process_frame
	var sequence: FullScreenSequence = death.get_node(
		"FailureSequence"
	) as FullScreenSequence
	sequence.skip_to_end()
	await get_tree().create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://death_restart_preview.png"
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save death/restart preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("DEATH_RESTART_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
