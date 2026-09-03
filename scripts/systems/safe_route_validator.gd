class_name SafeRouteValidator extends RefCounted


static func find_safe_route(
	pattern: EncounterPattern,
	start_region: int,
	min_region: int,
	max_region: int,
	lane_move_duration: float
) -> PackedInt32Array:
	var no_route: PackedInt32Array = PackedInt32Array()
	if (
		pattern == null
		or not pattern.is_valid()
		or lane_move_duration <= 0.0
		or start_region < min_region
		or start_region > max_region
	):
		return no_route
	var initial_route: PackedInt32Array = PackedInt32Array([start_region])
	if not pattern.is_region_threatened(start_region, 0.0):
		return initial_route
	var maximum_steps: int = floori(pattern.warning_duration / lane_move_duration)
	var routes: Array[PackedInt32Array] = [initial_route]
	for step: int in range(1, maximum_steps + 1):
		var sample_time: float = float(step) * lane_move_duration
		var next_routes: Array[PackedInt32Array] = []
		var visited_regions: Array[int] = []
		for route: PackedInt32Array in routes:
			var current_region: int = route[route.size() - 1]
			for offset: int in [0, -1, 1]:
				var candidate_region: int = current_region + offset
				if (
					candidate_region < min_region
					or candidate_region > max_region
					or visited_regions.has(candidate_region)
				):
					continue
				visited_regions.append(candidate_region)
				var candidate_route: PackedInt32Array = route.duplicate()
				candidate_route.append(candidate_region)
				if not pattern.is_region_threatened(candidate_region, sample_time):
					return candidate_route
				next_routes.append(candidate_route)
		routes = next_routes
		if routes.is_empty():
			break
	return no_route


static func get_route_move_count(route: PackedInt32Array) -> int:
	var move_count: int = 0
	for index: int in range(1, route.size()):
		if route[index] != route[index - 1]:
			move_count += 1
	return move_count


static func is_declared_minimum_route_valid(
	pattern: EncounterPattern,
	min_region: int,
	max_region: int,
	lane_move_duration: float,
	maximum_moves: int = 3
) -> bool:
	if pattern == null or not pattern.is_valid() or lane_move_duration <= 0.0:
		return false
	var route: PackedInt32Array = pattern.minimum_safe_route
	if route.is_empty() or get_route_move_count(route) > maximum_moves:
		return false
	for index: int in range(route.size()):
		if route[index] < min_region or route[index] > max_region:
			return false
		if index > 0 and absi(route[index] - route[index - 1]) > 1:
			return false
	var arrival_time: float = float(route.size() - 1) * lane_move_duration
	if arrival_time > pattern.warning_duration:
		return false
	return not pattern.is_region_threatened(route[route.size() - 1], arrival_time)


static func is_pattern_fair_for_threatened_starts(
	pattern: EncounterPattern,
	min_region: int,
	max_region: int,
	lane_move_duration: float,
	maximum_moves: int = 3
) -> bool:
	if pattern == null or not pattern.is_valid():
		return false
	var threatened_start_count: int = 0
	for start_region: int in range(min_region, max_region + 1):
		if not pattern.is_region_threatened(start_region, 0.0):
			continue
		threatened_start_count += 1
		var route: PackedInt32Array = find_safe_route(
			pattern,
			start_region,
			min_region,
			max_region,
			lane_move_duration
		)
		if route.is_empty() or get_route_move_count(route) > maximum_moves:
			return false
	return threatened_start_count > 0
