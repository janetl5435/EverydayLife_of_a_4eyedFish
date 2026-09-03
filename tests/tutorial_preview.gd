extends Control


func _ready() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	await get_tree().process_frame
	var tutorial_button: Button = $MainMenu/MenuColumn/TutorialButton as Button
	tutorial_button.pressed.emit()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://tutorial_preview.png"
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save tutorial preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("TUTORIAL_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
