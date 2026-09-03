class_name SeaBackdrop extends Control

enum FishPose {
	SWIMMING,
	DEAD,
}

@export var fish_pose: FishPose = FishPose.SWIMMING
@export var animate_swimming_fish: bool = true
@export var fish_position: Vector2 = Vector2(332.0, 458.0)
@export var fish_scale: Vector2 = Vector2(1.35, 1.35)
@export_range(0.0, 24.0, 0.5) var bob_distance: float = 6.0
@export_range(0.1, 8.0, 0.1) var bob_duration: float = 2.4
@export_group("Map Motion")
@export var animate_map: bool = false
@export_range(0.0, 360.0, 1.0, "or_greater") var map_scroll_speed: float = 60.0

@onready var decorative_fish: PlayerFish = %DecorativeFish
@onready var map_track: Node2D = %MapTrack
@onready var map_primary: Sprite2D = %MapPrimary
@onready var map_repeat: Sprite2D = %MapRepeat

var _bob_tween: Tween
var _map_cycle_width: float = 0.0
var _map_scroll_offset: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	decorative_fish.position = fish_position
	decorative_fish.scale = fish_scale
	_configure_map_motion()
	_apply_fish_pose()


func _process(delta: float) -> void:
	if not animate_map or _map_cycle_width <= 0.0:
		return
	_map_scroll_offset = fposmod(
		_map_scroll_offset + map_scroll_speed * delta,
		_map_cycle_width
	)
	map_track.position.x = -_map_scroll_offset


func _exit_tree() -> void:
	_stop_bob()


func set_fish_pose(pose: FishPose) -> void:
	fish_pose = pose
	if is_node_ready():
		_apply_fish_pose()


func _apply_fish_pose() -> void:
	_stop_bob()
	match fish_pose:
		FishPose.SWIMMING:
			decorative_fish.rotation = 0.0
			if animate_swimming_fish:
				_start_bob()
		FishPose.DEAD:
			decorative_fish.play_death_animation(
				decorative_fish.global_position.y,
				0.0
			)


func _start_bob() -> void:
	var resting_y: float = decorative_fish.position.y
	_bob_tween = create_tween().set_loops()
	_bob_tween.set_trans(Tween.TRANS_SINE)
	_bob_tween.set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(
		decorative_fish,
		^"position:y",
		resting_y - bob_distance,
		bob_duration
	)
	_bob_tween.tween_property(
		decorative_fish,
		^"position:y",
		resting_y + bob_distance,
		bob_duration * 2.0
	)
	_bob_tween.tween_property(
		decorative_fish,
		^"position:y",
		resting_y,
		bob_duration
	)


func _stop_bob() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	_bob_tween = null


func _configure_map_motion() -> void:
	_map_scroll_offset = 0.0
	map_track.position.x = 0.0
	if map_primary.texture == null:
		_map_cycle_width = 0.0
		map_repeat.visible = false
		set_process(false)
		return
	_map_cycle_width = map_primary.texture.get_width() * absf(map_primary.scale.x)
	map_repeat.position = map_primary.position + Vector2(_map_cycle_width, 0.0)
	map_repeat.visible = animate_map and _map_cycle_width > 0.0
	set_process(map_repeat.visible and map_scroll_speed > 0.0)
