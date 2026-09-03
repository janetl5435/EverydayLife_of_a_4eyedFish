class_name WorldConfig extends Resource

@export_group("Map")
@export_range(0.1, 1.0, 0.01) var map_display_scale: float = 0.4

@export_group("Player")
@export var player_start_x: float = 410.0
@export var forward_speed: float = 180.0
@export_range(1.0, 3.0, 0.05) var speed_boost_multiplier: float = 2.0
@export var region_move_duration: float = 0.1

@export_group("Run")
@export_range(100.0, 50000.0, 100.0) var run_finish_distance: float = 10000.0

@export_group("Energy")
@export_range(0.1, 1000.0, 0.1) var initial_energy: float = 20.0
@export_range(0.0, 100.0, 0.1) var normal_energy_drain_per_second: float = 1.0
@export_range(0.0, 100.0, 0.1) var boosted_energy_drain_per_second: float = 2.5

@export_group("Forage jump")
@export_range(100.0, 1200.0, 10.0) var jump_speed: float = 650.0
@export_range(100.0, 2400.0, 10.0) var jump_gravity: float = 980.0

@export_group("Camera")
@export var camera_horizontal_look_ahead: float = 230.0
@export var camera_vertical_transition_duration: float = 0.5

@export_group("Wet eye task")
@export_range(1.0, 120.0, 0.5) var wet_eye_duration: float = 10.0
@export_range(0.0, 10.0, 0.5) var wet_eye_warning_duration: float = 3.0

@export_group("Failure")
@export_range(0.0, 5.0, 0.1) var death_animation_duration: float = 0.8


func _init() -> void:
	pass
