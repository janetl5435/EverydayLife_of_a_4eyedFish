extends Node


func _ready() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(
		"res://scenes/gameplay/gameplay_root.tscn"
	) as PackedScene
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var preview_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	preview_config.run_finish_distance = 100000.0
	gameplay.world_config = preview_config
	gameplay.route_scenes_after_settlement = false
	add_child(gameplay)
	await get_tree().process_frame
	var forage: ForageModeController = gameplay.get_node(
		"ModeHost/ForageModeController"
	) as ForageModeController
	forage.energy_changed.emit(18)
	var wet_eye: WetEyeController = gameplay.get_node(
		"Systems/WetEyeController"
	) as WetEyeController
	wet_eye.set_process(false)
	wet_eye.advance_time(7.2)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = "user://gameplay_hud_preview.png"
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Failed to save gameplay HUD preview (error %d)." % error)
		get_tree().quit(1)
		return
	print("GAMEPLAY_HUD_PREVIEW=", ProjectSettings.globalize_path(output_path))
	get_tree().quit(0)
