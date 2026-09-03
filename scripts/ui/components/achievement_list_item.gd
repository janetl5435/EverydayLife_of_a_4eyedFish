class_name AchievementListItem extends PanelContainer

@onready var icon_rect: TextureRect = %IconRect
@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var condition_label: Label = %ConditionLabel


func configure(definition: AchievementDefinition, unlocked: bool) -> void:
	if definition == null:
		push_error("AchievementListItem requires a definition.")
		return
	icon_rect.texture = definition.icon
	icon_rect.modulate = (
		Color.WHITE
		if unlocked
		else Color(0.18, 0.22, 0.24, 0.34)
	)
	title_label.text = definition.display_name
	status_label.text = "已解锁" if unlocked else "未解锁"
	status_label.modulate = (
		Color(0.08, 0.5, 0.3, 1.0)
		if unlocked
		else Color(0.34, 0.39, 0.4, 1.0)
	)
	condition_label.text = definition.condition_text
