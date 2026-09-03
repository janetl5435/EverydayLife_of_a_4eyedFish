class_name EcologyEventDefinition extends RefCounted


class FoodSpawn extends RefCounted:
	var food_id: StringName
	var world_region: int
	var horizontal_offset: float
	var world_velocity_override: float


	func _init(
		id: StringName,
		region: int,
		offset: float = 0.0,
		velocity_override: float = INF
	) -> void:
		food_id = id
		world_region = region
		horizontal_offset = offset
		world_velocity_override = velocity_override


class ThreatSpawn extends RefCounted:
	var animal_type: ThreatEntry.AnimalType
	var world_region: int
	var direction: int
	var speed: float
	var horizontal_offset: float


	func _init(
		type: ThreatEntry.AnimalType,
		region: int,
		travel_direction: int,
		travel_speed: float,
		offset: float = 0.0
	) -> void:
		animal_type = type
		world_region = region
		direction = travel_direction
		speed = travel_speed
		horizontal_offset = offset


class Batch extends RefCounted:
	var distance_offset: float
	var foods: Array[FoodSpawn] = []
	var threats: Array[ThreatSpawn] = []


	func _init(offset: float) -> void:
		distance_offset = offset


var event_id: int
var length: float
var batches: Array[Batch] = []


func _init(id: int, event_length: float) -> void:
	event_id = id
	length = event_length
