class_name RegionGuide extends Node2D

const SKY_FILL: Color = Color(0.34, 0.70, 0.95, 0.035)
const WATER_FILL: Color = Color(0.08, 0.48, 0.72, 0.055)
const SOIL_FILL: Color = Color(0.48, 0.29, 0.13, 0.09)
const CAMERA_FILL: Color = Color(0.46, 0.74, 1.0, 0.065)
const SWIM_FILL: Color = Color(0.30, 1.0, 0.62, 0.12)

var _layout: RegionLayout
var _camera: Camera2D
var _profile: RegionLayout.ViewProfile = RegionLayout.ViewProfile.PATROL
var _map_display_height: float = 0.0
var _line_length: float = 1500.0


func _ready() -> void:
	set_process(false)


func configure(
	layout: RegionLayout,
	camera: Camera2D,
	profile: RegionLayout.ViewProfile,
	map_display_height: float
) -> void:
	_layout = layout
	_camera = camera
	_profile = profile
	_map_display_height = map_display_height
	_line_length = get_viewport_rect().size.x + 240.0
	set_process(true)
	queue_redraw()


func set_active_profile(profile: RegionLayout.ViewProfile) -> void:
	_profile = profile
	queue_redraw()


func _process(_delta: float) -> void:
	if _camera == null:
		return
	position.x = _camera.global_position.x - get_viewport_rect().size.x * 0.5 - 120.0


func _draw() -> void:
	if _layout == null:
		return
	var camera_min_region: int = _layout.get_camera_min_region(_profile)
	var camera_max_region: int = _layout.get_camera_max_region(_profile)
	var swim_min_region: int = _layout.get_swim_min_region(_profile)
	var swim_max_region: int = _layout.get_swim_max_region(_profile)
	for region_id: int in range(1, RegionLayout.REGION_COUNT + 1):
		var top_y: float = _layout.get_region_top_y(region_id)
		var bottom_y: float = _layout.get_region_bottom_y(region_id)
		var band_rect: Rect2 = Rect2(0.0, top_y, _line_length, bottom_y - top_y)
		var camera_visible: bool = region_id >= camera_min_region and region_id <= camera_max_region
		var swimmable: bool = region_id >= swim_min_region and region_id <= swim_max_region
		draw_rect(band_rect, _get_medium_fill(region_id))
		if camera_visible:
			draw_rect(band_rect, CAMERA_FILL)
		if swimmable:
			draw_rect(band_rect, SWIM_FILL)
		var label: String = "全局区域%d · %s" % [
			region_id,
			_layout.get_region_medium_label(region_id),
		]
		if camera_visible:
			label += " · 相机可见"
		if swimmable:
			label += " · 可游泳道"
		var label_color: Color = Color(1.0, 1.0, 1.0, 0.88 if camera_visible else 0.32)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(18.0, top_y + 25.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			17,
			label_color
		)
	for boundary_index: int in range(RegionLayout.BOUNDARY_COUNT):
		var boundary_y: float = _layout.region_boundaries[boundary_index]
		var boundary_color: Color = Color(1.0, 1.0, 1.0, 0.18)
		var boundary_width: float = 1.0
		if is_equal_approx(boundary_y, _layout.get_water_surface_y()):
			boundary_color = Color(0.65, 0.92, 1.0, 0.88)
			boundary_width = 2.5
		elif is_equal_approx(boundary_y, _layout.get_soil_surface_y()):
			boundary_color = Color(0.95, 0.70, 0.34, 0.88)
			boundary_width = 2.5
		draw_line(
			Vector2(0.0, boundary_y),
			Vector2(_line_length, boundary_y),
			boundary_color,
			boundary_width
		)
	_draw_unassigned_soil_strip()


func _draw_unassigned_soil_strip() -> void:
	var strip_top_y: float = _layout.get_region_bottom_y(RegionLayout.REGION_COUNT)
	var strip_height: float = _layout.get_unassigned_bottom_height(_map_display_height)
	if strip_height <= 0.0:
		return
	draw_rect(Rect2(0.0, strip_top_y, _line_length, strip_height), Color(0.35, 0.20, 0.10, 0.16))
	draw_line(
		Vector2(0.0, _map_display_height),
		Vector2(_line_length, _map_display_height),
		Color(0.95, 0.70, 0.34, 0.42),
		1.0
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(18.0, strip_top_y + minf(strip_height * 0.65, 25.0)),
		"区域外泥沙条带（不可游）",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		Color(1.0, 0.82, 0.58, 0.58)
	)


func _get_medium_fill(region_id: int) -> Color:
	match _layout.get_region_medium(region_id):
		RegionLayout.RegionMedium.SKY:
			return SKY_FILL
		RegionLayout.RegionMedium.WATER:
			return WATER_FILL
		RegionLayout.RegionMedium.SOIL:
			return SOIL_FILL
		_:
			return Color.TRANSPARENT
