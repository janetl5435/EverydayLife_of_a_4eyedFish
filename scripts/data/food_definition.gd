class_name FoodDefinition extends Resource

enum CollectionMethod {
	CONTACT,
	INTERACT,
}

@export var food_id: StringName = &""
@export var display_name: String = ""
@export_range(1, 100, 1) var energy_value: int = 1
@export_range(1, RegionLayout.REGION_COUNT, 1) var spawn_region: int = 5
@export var collection_method: CollectionMethod = CollectionMethod.INTERACT
@export var scene: PackedScene
@export_range(-500.0, 500.0, 5.0) var world_velocity_x: float = 0.0
@export_range(24.0, 320.0, 4.0) var interaction_distance: float = 140.0


func _init() -> void:
	pass


func is_valid() -> bool:
	return (
		not String(food_id).is_empty()
		and not display_name.is_empty()
		and energy_value > 0
		and spawn_region >= 1
		and spawn_region <= RegionLayout.REGION_COUNT
		and scene != null
		and interaction_distance > 0.0
	)
