extends Control

const ACHIEVEMENT_CARD_SCENE: PackedScene = preload("res://scenes/ui/achievement_card.tscn")

@onready var achievement_list: GridContainer = %AchievementList
@onready var back_button: Button = %BackButton


func _ready() -> void:
	_populate_achievements()
	back_button.pressed.connect(AppFlow.open_main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		AppFlow.open_main_menu()
		get_viewport().set_input_as_handled()


func _populate_achievements() -> void:
	var definitions: Array[AchievementDefinition] = AchievementService.get_definitions()
	for definition: AchievementDefinition in definitions:
		var card: AchievementCard = (
			ACHIEVEMENT_CARD_SCENE.instantiate() as AchievementCard
		)
		if card == null:
			continue
		achievement_list.add_child(card)
		card.configure(
			definition,
			AchievementService.is_unlocked(definition.achievement_id)
		)
