class_name AchievementDefinition extends Resource

@export var achievement_id: StringName = &""
@export var display_name: String = ""
@export_multiline var condition_text: String = ""
@export var icon: Texture2D


func _init() -> void:
	pass


func is_valid() -> bool:
	return (
		not String(achievement_id).is_empty()
		and not display_name.is_empty()
		and not condition_text.is_empty()
		and icon != null
	)
