class_name LoopingSeaBackground extends Node2D

signal panel_recycled(panel_name: StringName, new_x: float)

@onready var map_a: Sprite2D = %MapA
@onready var map_b: Sprite2D = %MapB

var _camera: Camera2D
var _panels: Array[Sprite2D] = []
var _panel_width: float = 0.0
var _display_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	_panels = [map_a, map_b]
	set_process(false)


func configure(config: WorldConfig) -> void:
	if map_a.texture == null or map_b.texture == null:
		push_error("Looping sea background requires textures on both map panels.")
		return
	var texture_size: Vector2 = map_a.texture.get_size()
	_display_size = texture_size * config.map_display_scale
	_panel_width = _display_size.x
	for panel: Sprite2D in _panels:
		panel.centered = false
		panel.scale = Vector2.ONE * config.map_display_scale
	map_a.position = Vector2.ZERO
	map_b.position = Vector2(_panel_width, 0.0)


func track_camera(camera: Camera2D) -> void:
	_camera = camera
	set_process(_camera != null and _panel_width > 0.0)


func get_display_size() -> Vector2:
	return _display_size


func _process(_delta: float) -> void:
	if _camera == null or _panel_width <= 0.0:
		return
	var half_view_width: float = get_viewport_rect().size.x * 0.5 / _camera.zoom.x
	var camera_left: float = _camera.global_position.x - half_view_width
	for panel: Sprite2D in _panels:
		if panel.global_position.x + _panel_width >= camera_left:
			continue
		var right_edge: float = -INF
		for other_panel: Sprite2D in _panels:
			if other_panel == panel:
				continue
			right_edge = maxf(right_edge, other_panel.position.x + _panel_width)
		panel.position.x = right_edge
		panel_recycled.emit(panel.name, panel.position.x)
