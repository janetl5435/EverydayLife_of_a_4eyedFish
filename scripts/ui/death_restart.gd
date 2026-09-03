extends Control

@onready var failure_sequence: FullScreenSequence = %FailureSequence
@onready var restart_content: CenterContainer = %Center
@onready var mode_label: Label = %ModeLabel
@onready var reason_label: Label = %ReasonLabel
@onready var distance_label: Label = %DistanceLabel
@onready var streak_label: Label = %StreakLabel
@onready var retry_button: Button = %RetryButton
@onready var menu_button: Button = %MenuButton

var _reveal_tween: Tween


func _ready() -> void:
	_populate_hidden_failure_data()
	retry_button.pressed.connect(_on_retry_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	failure_sequence.sequence_finished.connect(_on_failure_sequence_finished)
	_configure_focus_chain()
	restart_content.visible = failure_sequence.has_finished()
	if failure_sequence.has_finished():
		_on_failure_sequence_finished()


func _exit_tree() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()


func _unhandled_input(event: InputEvent) -> void:
	if failure_sequence.is_playing():
		if _is_skip_event(event):
			failure_sequence.skip_to_end()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_menu_pressed()
		get_viewport().set_input_as_handled()
		return
	if retry_button.has_focus() or menu_button.has_focus():
		return
	if event.is_action_pressed(&"ui_down"):
		retry_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		menu_button.grab_focus()
		get_viewport().set_input_as_handled()


func _populate_hidden_failure_data() -> void:
	var result: RunResult = AppFlow.last_run_result
	mode_label.text = "%s失败" % AppFlow.get_current_mode_label()
	reason_label.text = AppFlow.get_last_failure_reason_label()
	if result == null:
		distance_label.text = "前进距离：未记录"
	else:
		distance_label.text = "前进距离：%d px" % roundi(result.travelled_distance)
	streak_label.text = "失败已结算；首次失败会解锁“鱼已逝”。"


func _configure_focus_chain() -> void:
	retry_button.focus_neighbor_top = retry_button.get_path_to(menu_button)
	retry_button.focus_neighbor_bottom = retry_button.get_path_to(menu_button)
	menu_button.focus_neighbor_top = menu_button.get_path_to(retry_button)
	menu_button.focus_neighbor_bottom = menu_button.get_path_to(retry_button)


func _is_skip_event(event: InputEvent) -> bool:
	return (
		event.is_action_pressed(&"ui_accept")
		or event.is_action_pressed(&"ui_cancel")
		or (event is InputEventMouseButton and event.pressed)
	)


func _on_failure_sequence_finished() -> void:
	restart_content.visible = true
	restart_content.modulate.a = 0.0
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(restart_content, ^"modulate:a", 1.0, 0.18)


func _on_retry_pressed() -> void:
	AppFlow.retry_current_mode()


func _on_menu_pressed() -> void:
	AppFlow.open_main_menu()
