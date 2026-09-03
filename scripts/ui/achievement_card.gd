class_name AchievementCard extends PanelContainer

@onready var icon_rect: TextureRect = %IconRect
@onready var title_label: Label = %TitleLabel
@onready var condition_label: Label = %ConditionLabel


func configure(definition: AchievementDefinition, unlocked: bool) -> void:
	if definition == null:
		push_error("AchievementCard requires a definition.")
		return
	icon_rect.texture = definition.icon
	icon_rect.modulate = Color.WHITE
	var icon_material: ShaderMaterial = icon_rect.material as ShaderMaterial
	if icon_material != null:
		icon_material.set_shader_parameter(&"saturation", 1.0 if unlocked else 0.0)
	title_label.text = definition.display_name
	condition_label.text = definition.condition_text
