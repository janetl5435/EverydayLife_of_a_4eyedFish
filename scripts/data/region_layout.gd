class_name RegionLayout extends Resource

enum ViewProfile {
	FORAGE_SURFACE,
	FORAGE_DEEP,
	PATROL,
}

enum RegionMedium {
	SKY,
	WATER,
	SOIL,
}

const REGION_COUNT: int = 9
const BOUNDARY_COUNT: int = REGION_COUNT + 1

@export_group("Global region boundaries")
@export var region_boundaries: PackedFloat32Array = PackedFloat32Array([
	0.0,
	108.9,
	217.8,
	326.7,
	435.6,
	563.7,
	691.8,
	819.9,
	948.0,
	1066.5,
])

@export_group("Camera visible ranges")
@export_range(1, REGION_COUNT, 1) var forage_surface_camera_min_region: int = 1
@export_range(1, REGION_COUNT, 1) var forage_surface_camera_max_region: int = 6
@export_range(1, REGION_COUNT, 1) var forage_deep_camera_min_region: int = 4
@export_range(1, REGION_COUNT, 1) var forage_deep_camera_max_region: int = 9
@export_range(1, REGION_COUNT, 1) var patrol_camera_min_region: int = 2
@export_range(1, REGION_COUNT, 1) var patrol_camera_max_region: int = 7

@export_group("Player swimming ranges")
@export_range(1, REGION_COUNT, 1) var forage_surface_swim_min_region: int = 5
@export_range(1, REGION_COUNT, 1) var forage_surface_swim_max_region: int = 6
@export_range(1, REGION_COUNT, 1) var forage_surface_start_region: int = 5
@export_range(1, REGION_COUNT, 1) var forage_deep_swim_min_region: int = 5
@export_range(1, REGION_COUNT, 1) var forage_deep_swim_max_region: int = 8
@export_range(1, REGION_COUNT, 1) var forage_deep_start_region: int = 6
@export_range(1, REGION_COUNT, 1) var patrol_swim_min_region: int = 5
@export_range(1, REGION_COUNT, 1) var patrol_swim_max_region: int = 7
@export_range(1, REGION_COUNT, 1) var patrol_start_region: int = 5

@export_group("Wet eye exposure")
@export_range(1, REGION_COUNT, 1) var surface_exposed_region: int = 5


func _init() -> void:
	pass


func is_valid() -> bool:
	if region_boundaries.size() != BOUNDARY_COUNT:
		return false
	for index: int in range(1, region_boundaries.size()):
		if region_boundaries[index] <= region_boundaries[index - 1]:
			return false
	return (
		_is_region_range_valid(forage_surface_camera_min_region, forage_surface_camera_max_region)
		and _is_region_range_valid(forage_deep_camera_min_region, forage_deep_camera_max_region)
		and _is_region_range_valid(patrol_camera_min_region, patrol_camera_max_region)
		and _is_water_swim_range_valid(forage_surface_swim_min_region, forage_surface_swim_max_region)
		and _is_water_swim_range_valid(forage_deep_swim_min_region, forage_deep_swim_max_region)
		and _is_water_swim_range_valid(patrol_swim_min_region, patrol_swim_max_region)
		and _is_start_region_valid(
			forage_surface_start_region,
			forage_surface_swim_min_region,
			forage_surface_swim_max_region
		)
		and _is_start_region_valid(
			forage_deep_start_region,
			forage_deep_swim_min_region,
			forage_deep_swim_max_region
		)
		and _is_start_region_valid(
			patrol_start_region,
			patrol_swim_min_region,
			patrol_swim_max_region
		)
		and get_region_medium(surface_exposed_region) == RegionMedium.WATER
		and _is_start_region_valid(
			surface_exposed_region,
			forage_surface_swim_min_region,
			forage_surface_swim_max_region
		)
		and _is_start_region_valid(
			surface_exposed_region,
			patrol_swim_min_region,
			patrol_swim_max_region
		)
	)


func is_valid_region(region_id: int) -> bool:
	return region_id >= 1 and region_id <= REGION_COUNT


func get_region_top_y(region_id: int) -> float:
	if not is_valid_region(region_id):
		_report_invalid_region(region_id)
		return 0.0
	return region_boundaries[region_id - 1]


func get_region_bottom_y(region_id: int) -> float:
	if not is_valid_region(region_id):
		_report_invalid_region(region_id)
		return 0.0
	return region_boundaries[region_id]


func get_region_center_y(region_id: int) -> float:
	return (get_region_top_y(region_id) + get_region_bottom_y(region_id)) * 0.5


func get_region_height(region_id: int) -> float:
	return get_region_bottom_y(region_id) - get_region_top_y(region_id)


func get_region_medium(region_id: int) -> RegionMedium:
	if region_id <= 4:
		return RegionMedium.SKY
	if region_id <= 8:
		return RegionMedium.WATER
	return RegionMedium.SOIL


func get_region_medium_label(region_id: int) -> String:
	match get_region_medium(region_id):
		RegionMedium.SKY:
			return "天空"
		RegionMedium.WATER:
			return "水体"
		RegionMedium.SOIL:
			return "泥沙"
		_:
			return "未知"


func get_water_surface_y() -> float:
	return get_region_bottom_y(4)


func get_soil_surface_y() -> float:
	return get_region_bottom_y(8)


func get_unassigned_bottom_height(map_display_height: float) -> float:
	return maxf(map_display_height - get_region_bottom_y(9), 0.0)


func get_safe_center_y(region_id: int, body_half_height: float) -> float:
	var top_limit: float = get_region_top_y(region_id) + body_half_height
	var bottom_limit: float = get_region_bottom_y(region_id) - body_half_height
	if top_limit > bottom_limit:
		push_error("Player body is too tall for global region %d." % region_id)
		return get_region_center_y(region_id)
	return (top_limit + bottom_limit) * 0.5


func clamp_body_center_to_region(center_y: float, region_id: int, body_half_height: float) -> float:
	var min_center_y: float = get_region_top_y(region_id) + body_half_height
	var max_center_y: float = get_region_bottom_y(region_id) - body_half_height
	if min_center_y > max_center_y:
		return get_region_center_y(region_id)
	return clampf(center_y, min_center_y, max_center_y)


func is_body_inside_region(center_y: float, region_id: int, body_half_height: float) -> bool:
	return (
		center_y - body_half_height >= get_region_top_y(region_id)
		and center_y + body_half_height <= get_region_bottom_y(region_id)
	)


func get_camera_min_region(profile: ViewProfile) -> int:
	match profile:
		ViewProfile.FORAGE_SURFACE:
			return forage_surface_camera_min_region
		ViewProfile.FORAGE_DEEP:
			return forage_deep_camera_min_region
		ViewProfile.PATROL:
			return patrol_camera_min_region
		_:
			return forage_surface_camera_min_region


func get_camera_max_region(profile: ViewProfile) -> int:
	match profile:
		ViewProfile.FORAGE_SURFACE:
			return forage_surface_camera_max_region
		ViewProfile.FORAGE_DEEP:
			return forage_deep_camera_max_region
		ViewProfile.PATROL:
			return patrol_camera_max_region
		_:
			return forage_surface_camera_max_region


func get_swim_min_region(profile: ViewProfile) -> int:
	match profile:
		ViewProfile.FORAGE_SURFACE:
			return forage_surface_swim_min_region
		ViewProfile.FORAGE_DEEP:
			return forage_deep_swim_min_region
		ViewProfile.PATROL:
			return patrol_swim_min_region
		_:
			return forage_surface_swim_min_region


func get_swim_max_region(profile: ViewProfile) -> int:
	match profile:
		ViewProfile.FORAGE_SURFACE:
			return forage_surface_swim_max_region
		ViewProfile.FORAGE_DEEP:
			return forage_deep_swim_max_region
		ViewProfile.PATROL:
			return patrol_swim_max_region
		_:
			return forage_surface_swim_max_region


func get_swim_start_region(profile: ViewProfile) -> int:
	match profile:
		ViewProfile.FORAGE_SURFACE:
			return forage_surface_start_region
		ViewProfile.FORAGE_DEEP:
			return forage_deep_start_region
		ViewProfile.PATROL:
			return patrol_start_region
		_:
			return forage_surface_start_region


func is_wet_eye_exposed(profile: ViewProfile, region_id: int) -> bool:
	return profile != ViewProfile.FORAGE_DEEP and region_id == surface_exposed_region


func get_profile_label(profile: ViewProfile) -> String:
	match profile:
		ViewProfile.FORAGE_SURFACE:
			return "相机可见：全局区域1–6（旅程水面）"
		ViewProfile.FORAGE_DEEP:
			return "相机可见：全局区域4–9（旅程水下）"
		ViewProfile.PATROL:
			return "相机可见：全局区域2–7（巡游）"
		_:
			return "未知相机范围"


func get_profile_camera_y(
	profile: ViewProfile,
	viewport_height: float,
	map_display_height: float
) -> float:
	var visible_top_y: float = get_region_top_y(get_camera_min_region(profile))
	var visible_bottom_y: float = get_region_bottom_y(get_camera_max_region(profile))
	var desired_y: float = (visible_top_y + visible_bottom_y) * 0.5
	if map_display_height <= viewport_height:
		return map_display_height * 0.5
	var half_viewport: float = viewport_height * 0.5
	return clampf(desired_y, half_viewport, map_display_height - half_viewport)


func _is_region_range_valid(min_region: int, max_region: int) -> bool:
	return is_valid_region(min_region) and is_valid_region(max_region) and min_region <= max_region


func _is_water_swim_range_valid(min_region: int, max_region: int) -> bool:
	return (
		_is_region_range_valid(min_region, max_region)
		and get_region_medium(min_region) == RegionMedium.WATER
		and get_region_medium(max_region) == RegionMedium.WATER
	)


func _is_start_region_valid(start_region: int, min_region: int, max_region: int) -> bool:
	return start_region >= min_region and start_region <= max_region


func _report_invalid_region(region_id: int) -> void:
	push_error("Global region must be between 1 and %d; received %d." % [REGION_COUNT, region_id])
