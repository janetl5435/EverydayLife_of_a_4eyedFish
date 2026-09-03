extends Node


func _ready() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	var intro_scene: PackedScene = load("res://scenes/ui/intro.tscn") as PackedScene
	var intro: Control = intro_scene.instantiate() as Control
	intro.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(intro)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://intro_preview.png"
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save intro preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("INTRO_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
