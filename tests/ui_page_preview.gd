extends Control

@export var output_filename: String = "ui_page_preview.png"


func _ready() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://%s" % output_filename
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save UI page preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("UI_PAGE_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
