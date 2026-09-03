extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_check_audio_buses()
	_check_loaded_streams_and_loops()
	_check_music_and_warning_lifecycle()
	_check_one_shot_entry_points()
	_finish()


func _check_audio_buses() -> void:
	for bus_name: StringName in [&"Master", &"Ambient", &"Music", &"SFX", &"UI"]:
		_expect_true(
			AudioServer.get_bus_index(bus_name) >= 0,
			"Missing audio bus: %s" % String(bus_name)
		)


func _check_loaded_streams_and_loops() -> void:
	var ambient_player: AudioStreamPlayer = AudioService.get_node("AmbientPlayer") as AudioStreamPlayer
	var music_player: AudioStreamPlayer = AudioService.get_node("MusicPlayer") as AudioStreamPlayer
	var warning_player: AudioStreamPlayer = AudioService.get_node("WarningPlayer") as AudioStreamPlayer
	_expect_true(ambient_player != null and ambient_player.stream != null, "Sea ambience must load.")
	_expect_true(music_player != null and music_player.stream != null, "Exploration music must load.")
	_expect_true(warning_player != null and warning_player.stream != null, "Warning sound must load.")
	if DisplayServer.get_name() != "headless":
		_expect_true(AudioService.is_ambient_playing(), "Sea ambience must start with the application.")
	if ambient_player != null and ambient_player.stream is AudioStreamOggVorbis:
		var ambient_stream: AudioStreamOggVorbis = ambient_player.stream as AudioStreamOggVorbis
		_expect_true(ambient_stream.loop, "Sea ambience must loop.")
	if music_player != null and music_player.stream is AudioStreamMP3:
		var music_stream: AudioStreamMP3 = music_player.stream as AudioStreamMP3
		_expect_true(music_stream.loop, "Exploration music must loop.")
	if warning_player != null and warning_player.stream is AudioStreamWAV:
		var warning_stream: AudioStreamWAV = warning_player.stream as AudioStreamWAV
		_expect_true(
			warning_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"Predator warning must loop while tracking is active."
		)


func _check_music_and_warning_lifecycle() -> void:
	AudioService.stop_exploration_music()
	AppFlow.mode_started.emit(AppFlow.GameMode.FORAGE)
	_expect_true(
		AudioService.is_exploration_music_requested(),
		"Starting the journey must start exploration music."
	)
	AudioService.start_warning_loop()
	AudioService.start_warning_loop()
	_expect_true(
		AudioService.is_warning_loop_requested(),
		"Predator tracking must start one warning loop."
	)
	AppFlow.scene_changed.emit(AppFlow.RESULT_SCENE)
	_expect_true(
		not AudioService.is_exploration_music_requested(),
		"Leaving gameplay must stop exploration music."
	)
	_expect_true(
		not AudioService.is_warning_loop_requested(),
		"Leaving gameplay must stop the predator warning."
	)
	AppFlow.scene_changed.emit(AppFlow.GAMEPLAY_SCENE)
	_expect_true(
		AudioService.is_exploration_music_requested(),
		"Retrying into gameplay must restart exploration music."
	)
	AudioService.stop_exploration_music()
	if DisplayServer.get_name() != "headless":
		_expect_true(AudioService.is_ambient_playing(), "Sea ambience must survive scene changes.")


func _check_one_shot_entry_points() -> void:
	AudioService.play_ui_click()
	AudioService.play_bite()
	AudioService.play_energy_gain()
	AudioService.play_game_success()
	AudioService.play_jump()
	AudioService.play_dive_splash()
	var loaded_streams: Array[AudioStream] = [
		AudioService.CLICK_SFX,
		AudioService.BITE_SFX,
		AudioService.ENERGY_GAIN_SFX,
		AudioService.GAME_SUCCESS_SFX,
		AudioService.JUMP_SFX,
		AudioService.DIVE_SPLASH_SFX,
	]
	for stream: AudioStream in loaded_streams:
		_expect_true(stream != null, "Every one-shot sound must load.")


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for child: Node in AudioService.get_children():
		if child is AudioStreamPlayer:
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			player.stop()
			player.stream = null
	if _failures.is_empty():
		print("AUDIO_INTEGRATION_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)
