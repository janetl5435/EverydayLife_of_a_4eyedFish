class_name ThreatPool extends Node

signal threat_bite_started(threat: PatrolThreat)

@export var bird_scene: PackedScene = preload("res://scenes/actors/bird_threat.tscn")
@export var predator_fish_scene: PackedScene = preload("res://scenes/actors/predator_fish_threat.tscn")
@export_range(1, 6, 1) var bird_capacity: int = 2
@export_range(2, 10, 1) var predator_fish_capacity: int = 4

var _active_root: Node2D
var _birds: Array[PatrolThreat] = []
var _predator_fish: Array[PatrolThreat] = []


func configure(active_root: Node2D) -> void:
	_active_root = active_root
	if _active_root == null:
		push_error("ThreatPool requires an ActiveThreats root.")
		return
	_prewarm(ThreatEntry.AnimalType.BIRD, bird_capacity)
	_prewarm(ThreatEntry.AnimalType.PREDATOR_FISH, predator_fish_capacity)


func acquire(animal_type: ThreatEntry.AnimalType) -> PatrolThreat:
	var bucket: Array[PatrolThreat] = _get_bucket(animal_type)
	for threat: PatrolThreat in bucket:
		if not threat.is_pool_active():
			return threat
	push_warning("ThreatPool expanded because every %s instance was active." % ThreatEntry.AnimalType.keys()[animal_type])
	return _create_threat(animal_type)


func release(threat: PatrolThreat) -> void:
	if threat == null:
		return
	if not _birds.has(threat) and not _predator_fish.has(threat):
		push_error("ThreatPool cannot release an instance it does not own.")
		return
	threat.deactivate()


func release_all() -> void:
	for threat: PatrolThreat in _birds:
		threat.deactivate()
	for threat: PatrolThreat in _predator_fish:
		threat.deactivate()


func freeze_non_attacker(attacker: PatrolThreat) -> void:
	for threat: PatrolThreat in _birds:
		if threat.is_pool_active() and threat != attacker:
			threat.freeze_for_capture()
	for threat: PatrolThreat in _predator_fish:
		if threat.is_pool_active() and threat != attacker:
			threat.freeze_for_capture()


func get_active_threats() -> Array[PatrolThreat]:
	var active_threats: Array[PatrolThreat] = []
	for threat: PatrolThreat in _birds:
		if threat.is_pool_active():
			active_threats.append(threat)
	for threat: PatrolThreat in _predator_fish:
		if threat.is_pool_active():
			active_threats.append(threat)
	return active_threats


func get_active_count() -> int:
	return get_active_threats().size()


func get_total_capacity() -> int:
	return _birds.size() + _predator_fish.size()


func _prewarm(animal_type: ThreatEntry.AnimalType, capacity: int) -> void:
	var bucket: Array[PatrolThreat] = _get_bucket(animal_type)
	while bucket.size() < capacity:
		if _create_threat(animal_type) == null:
			return


func _create_threat(animal_type: ThreatEntry.AnimalType) -> PatrolThreat:
	if _active_root == null:
		return null
	var scene: PackedScene = bird_scene if animal_type == ThreatEntry.AnimalType.BIRD else predator_fish_scene
	if scene == null:
		push_error("ThreatPool is missing a threat scene.")
		return null
	var threat: PatrolThreat = scene.instantiate() as PatrolThreat
	if threat == null:
		push_error("Threat scene root must use PatrolThreat.")
		return null
	_active_root.add_child(threat)
	threat.release_requested.connect(_on_release_requested)
	threat.bite_started.connect(_on_threat_bite_started)
	_get_bucket(animal_type).append(threat)
	return threat


func _get_bucket(animal_type: ThreatEntry.AnimalType) -> Array[PatrolThreat]:
	if animal_type == ThreatEntry.AnimalType.BIRD:
		return _birds
	return _predator_fish


func _on_release_requested(threat: PatrolThreat) -> void:
	release(threat)


func _on_threat_bite_started(threat: PatrolThreat) -> void:
	threat_bite_started.emit(threat)
