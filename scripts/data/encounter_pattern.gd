class_name EncounterPattern extends Resource

@export var pattern_id: StringName = &""
@export_range(0.1, 10.0, 0.1) var warning_duration: float = 1.0
@export var threat_entries: Array[ThreatEntry] = []
@export var minimum_safe_route: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	pass


func is_valid() -> bool:
	if String(pattern_id).is_empty() or not is_equal_approx(warning_duration, 1.0):
		return false
	if threat_entries.is_empty() or threat_entries.size() > 3:
		return false
	var bird_count: int = 0
	var predator_regions: Array[int] = []
	for entry: ThreatEntry in threat_entries:
		if entry == null or not entry.is_valid():
			return false
		if entry.animal_type == ThreatEntry.AnimalType.BIRD:
			bird_count += 1
		else:
			if predator_regions.has(entry.world_region):
				return false
			predator_regions.append(entry.world_region)
	var supported_combination: bool = (
		(bird_count == 1 and predator_regions.is_empty() and threat_entries.size() == 1)
		or (bird_count == 0 and predator_regions.size() == 1 and threat_entries.size() == 1)
		or (bird_count == 1 and predator_regions.size() == 1 and threat_entries.size() == 2)
		or (bird_count == 1 and predator_regions.size() == 2 and threat_entries.size() == 3)
		or (bird_count == 0 and predator_regions.size() == 2 and threat_entries.size() == 2)
	)
	return supported_combination and _is_minimum_route_valid()


func is_simple() -> bool:
	return threat_entries.size() == 1


func is_region_threatened(region_id: int, sample_time: float) -> bool:
	for entry: ThreatEntry in threat_entries:
		if _is_entry_active_at_time(entry, sample_time) and entry.get_danger_region() == region_id:
			return true
	return false


func get_threatening_entries(region_id: int, sample_time: float) -> Array[ThreatEntry]:
	var threatening_entries: Array[ThreatEntry] = []
	for entry: ThreatEntry in threat_entries:
		if _is_entry_active_at_time(entry, sample_time) and entry.get_danger_region() == region_id:
			threatening_entries.append(entry)
	return threatening_entries


func has_bird() -> bool:
	for entry: ThreatEntry in threat_entries:
		if entry.animal_type == ThreatEntry.AnimalType.BIRD:
			return true
	return false


func _is_minimum_route_valid() -> bool:
	if minimum_safe_route.is_empty():
		return false
	for index: int in range(minimum_safe_route.size()):
		var region_id: int = minimum_safe_route[index]
		if region_id < ThreatEntry.PATROL_MIN_REGION or region_id > ThreatEntry.PATROL_MAX_REGION:
			return false
		if index > 0 and absi(region_id - minimum_safe_route[index - 1]) > 1:
			return false
	return true


func _is_entry_active_at_time(entry: ThreatEntry, sample_time: float) -> bool:
	return sample_time < entry.active_time and not is_equal_approx(sample_time, entry.active_time)
