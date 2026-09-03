extends Control

@onready var focus_button: Button = %FocusButton
@onready var achievement_item: AchievementCard = %AchievementItem


func _ready() -> void:
	var definitions: Array[AchievementDefinition] = AchievementService.get_definitions()
	if not definitions.is_empty():
		achievement_item.configure(definitions[0], true)
	focus_button.grab_focus()
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://ui_foundation_preview.png"
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save UI foundation preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("UI_FOUNDATION_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
