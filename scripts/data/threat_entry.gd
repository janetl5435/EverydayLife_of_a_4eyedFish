class_name ThreatEntry extends Resource

enum AnimalType {
	BIRD,
	PREDATOR_FISH,
}

const BIRD_WORLD_REGION: int = 3
const BIRD_DANGER_REGION: int = 5
const PATROL_MIN_REGION: int = 5
const PATROL_MAX_REGION: int = 7

@export var animal_type: AnimalType = AnimalType.BIRD
@export_range(1, RegionLayout.REGION_COUNT, 1) var world_region: int = BIRD_WORLD_REGION
@export_enum("向左:-1", "向右:1") var direction: int = -1
@export_range(1.0, 1000.0, 1.0) var speed: float = 320.0
@export_range(0.1, 10.0, 0.1) var active_time: float = 2.4


func _init() -> void:
	pass


func is_valid() -> bool:
	if direction != -1 and direction != 1:
		return false
	if speed <= 0.0 or active_time <= 0.0:
		return false
	match animal_type:
		AnimalType.BIRD:
			return world_region == BIRD_WORLD_REGION
		AnimalType.PREDATOR_FISH:
			return world_region >= PATROL_MIN_REGION and world_region <= PATROL_MAX_REGION
		_:
			return false


func get_danger_region() -> int:
	if animal_type == AnimalType.BIRD:
		return BIRD_DANGER_REGION
	return world_region


func get_animal_label() -> String:
	if animal_type == AnimalType.BIRD:
		return "鸟类"
	return "捕食鱼"
