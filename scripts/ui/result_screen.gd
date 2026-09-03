extends Control

const ACHIEVEMENT_CARD_SCENE: PackedScene = preload("res://scenes/ui/achievement_card.tscn")

@onready var success_animation: AnimatedSprite2D = %SuccessAnimation
@onready var mode_label: Label = %ModeLabel
@onready var distance_label: Label = %DistanceLabel
@onready var energy_texture: TextureRect = %ResultEnergyTexture
@onready var energy_label: Label = %EnergyLabel
@onready var streak_label: Label = %StreakLabel
@onready var new_achievements_title: Label = %NewAchievementsTitle
@onready var new_achievements: VBoxContainer = %NewAchievements
@onready var replay_button: Button = %ReplayButton
@onready var menu_button: Button = %MenuButton

func _ready() -> void:
	var result: RunResult = AppFlow.last_run_result
	if result == null:
		mode_label.text = "%s完成" % AppFlow.get_current_mode_label()
		distance_label.text = "前进距离：未记录"
		energy_texture.visible = false
		energy_label.visible = false
		streak_label.text = "终点能量判定：未记录"
		new_achievements_title.text = "本局没有新解锁图鉴"
	else:
		_populate_result(result)
	replay_button.pressed.connect(_on_replay_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_configure_focus_chain()
	_start_success_animation()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_menu_pressed()
		get_viewport().set_input_as_handled()
		return
	if replay_button.has_focus() or menu_button.has_focus():
		return
	if event.is_action_pressed(&"ui_down"):
		replay_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		menu_button.grab_focus()
		get_viewport().set_input_as_handled()


func _configure_focus_chain() -> void:
	replay_button.focus_neighbor_top = replay_button.get_path_to(menu_button)
	replay_button.focus_neighbor_bottom = replay_button.get_path_to(menu_button)
	menu_button.focus_neighbor_top = menu_button.get_path_to(replay_button)
	menu_button.focus_neighbor_bottom = menu_button.get_path_to(replay_button)


func _start_success_animation() -> void:
	success_animation.play(&"congrats")


func _populate_result(result: RunResult) -> void:
	mode_label.text = "%s完成" % AppFlow.get_mode_label(result.mode)
	distance_label.text = "前进距离：%d px" % roundi(result.travelled_distance)
	energy_texture.visible = result.mode == AppFlow.GameMode.FORAGE
	energy_label.visible = result.mode == AppFlow.GameMode.FORAGE
	energy_label.text = "%d" % floori(maxf(result.energy, 0.0))
	if result.mode == AppFlow.GameMode.PATROL:
		streak_label.text = "本局已完成"
	elif result.is_natural_finish():
		streak_label.text = "终点能量判定：≤2 解锁鱼好饿，>30 解锁鱼好撑"
	else:
		streak_label.text = "调试完成不触发终点能量图鉴"
	if result.newly_unlocked_ids.is_empty():
		new_achievements_title.text = "本局没有新解锁图鉴"
		return
	new_achievements_title.text = "本局新解锁"
	for achievement_id: StringName in result.newly_unlocked_ids:
		var definition: AchievementDefinition = AchievementService.get_definition(achievement_id)
		if definition == null:
			continue
		var card: AchievementCard = ACHIEVEMENT_CARD_SCENE.instantiate() as AchievementCard
		if card == null:
			continue
		new_achievements.add_child(card)
		card.configure(definition, true)


func _on_replay_pressed() -> void:
	AppFlow.retry_current_mode()


func _on_menu_pressed() -> void:
	AppFlow.open_main_menu()
