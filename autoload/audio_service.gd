extends Node

const SFX_POOL_SIZE: int = 6
const GAMEPLAY_SCENE: String = "res://scenes/gameplay/gameplay_root.tscn"

const SEA_AMBIENCE: AudioStream = preload("res://assets/audio/sea.ogg")
const EXPLORATION_MUSIC: AudioStream = preload("res://assets/audio/four_eyed_adventure.mp3")
const CLICK_SFX: AudioStream = preload("res://assets/audio/click.ogg")
const BITE_SFX: AudioStream = preload("res://assets/audio/bite.wav")
const ENERGY_GAIN_SFX: AudioStream = preload("res://assets/audio/exp_up.wav")
const GAME_SUCCESS_SFX: AudioStream = preload("res://assets/audio/game_success.wav")
const JUMP_SFX: AudioStream = preload("res://assets/audio/jump_out_of_water.wav")
const DIVE_SPLASH_SFX: AudioStream = preload("res://assets/audio/dive_splash.wav")
const WARNING_SFX: AudioStream = preload("res://assets/audio/warning_sound.wav")

var _ambient_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _warning_player: AudioStreamPlayer
var _ui_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _playback_available: bool = true
var _exploration_music_requested: bool = false
var _warning_loop_requested: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_playback_available = DisplayServer.get_name() != "headless"
	_ambient_player = _create_player(&"AmbientPlayer", &"Ambient")
	_music_player = _create_player(&"MusicPlayer", &"Music")
	_warning_player = _create_player(&"WarningPlayer", &"SFX")
	_ui_player = _create_player(&"UIPlayer", &"UI")
	for index: int in range(SFX_POOL_SIZE):
		var player: AudioStreamPlayer = _create_player(
			StringName("SFXPlayer%d" % index),
			&"SFX"
		)
		_sfx_players.append(player)
	_ambient_player.stream = _make_looping_stream(SEA_AMBIENCE)
	_music_player.stream = _make_looping_stream(EXPLORATION_MUSIC)
	_warning_player.stream = _make_looping_stream(WARNING_SFX)
	_ambient_player.finished.connect(_on_ambient_finished)
	_music_player.finished.connect(_on_music_finished)
	_warning_player.finished.connect(_on_warning_finished)
	if _playback_available:
		_ambient_player.play()
	AppFlow.mode_started.connect(_on_mode_started)
	AppFlow.scene_changed.connect(_on_scene_changed)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	while hovered_control != null:
		if hovered_control is BaseButton:
			var button: BaseButton = hovered_control as BaseButton
			if not button.disabled and button.visible:
				play_ui_click()
			return
		hovered_control = hovered_control.get_parent() as Control


func play_music(stream: AudioStream) -> void:
	if stream == null:
		return
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	if _playback_available:
		_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func play_exploration_music() -> void:
	_exploration_music_requested = true
	_ensure_ambient_playing()
	if _playback_available and not _music_player.playing:
		_music_player.play()


func stop_exploration_music() -> void:
	_exploration_music_requested = false
	_music_player.stop()


func play_sfx(stream: AudioStream) -> void:
	if stream == null or not _playback_available:
		return
	for player: AudioStreamPlayer in _sfx_players:
		if player.playing:
			continue
		player.stream = stream
		player.play()
		return
	push_warning("All SFX players are busy; the sound was skipped.")


func play_ui_click() -> void:
	if not _playback_available:
		return
	_ui_player.stream = CLICK_SFX
	_ui_player.play()


func play_bite() -> void:
	play_sfx(BITE_SFX)


func play_energy_gain() -> void:
	play_sfx(ENERGY_GAIN_SFX)


func play_game_success() -> void:
	play_sfx(GAME_SUCCESS_SFX)


func play_jump() -> void:
	play_sfx(JUMP_SFX)


func play_dive_splash() -> void:
	play_sfx(DIVE_SPLASH_SFX)


func start_warning_loop() -> void:
	_warning_loop_requested = true
	if _playback_available and not _warning_player.playing:
		_warning_player.play()


func stop_warning_loop() -> void:
	_warning_loop_requested = false
	_warning_player.stop()


func is_ambient_playing() -> bool:
	return _ambient_player != null and _ambient_player.playing


func is_exploration_music_playing() -> bool:
	return _music_player != null and _music_player.playing


func is_warning_loop_playing() -> bool:
	return _warning_player != null and _warning_player.playing


func is_exploration_music_requested() -> bool:
	return _exploration_music_requested


func is_warning_loop_requested() -> bool:
	return _warning_loop_requested


func _create_player(player_name: StringName, bus_name: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus_name
	add_child(player)
	return player


func _make_looping_stream(source: AudioStream) -> AudioStream:
	var stream: AudioStream = source.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		var ogg_stream: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
		ogg_stream.loop = true
	elif stream is AudioStreamMP3:
		var mp3_stream: AudioStreamMP3 = stream as AudioStreamMP3
		mp3_stream.loop = true
	elif stream is AudioStreamWAV:
		var wav_stream: AudioStreamWAV = stream as AudioStreamWAV
		wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _ensure_ambient_playing() -> void:
	if _playback_available and not _ambient_player.playing:
		_ambient_player.play()


func _on_ambient_finished() -> void:
	_ensure_ambient_playing()


func _on_music_finished() -> void:
	if _exploration_music_requested and _playback_available:
		_music_player.play()


func _on_warning_finished() -> void:
	if _warning_loop_requested and _playback_available:
		_warning_player.play()


func _on_mode_started(_mode: AppFlow.GameMode) -> void:
	play_exploration_music()


func _on_scene_changed(scene_path: String) -> void:
	if scene_path == GAMEPLAY_SCENE:
		play_exploration_music()
		return
	stop_exploration_music()
	stop_warning_loop()
