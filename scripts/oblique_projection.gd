extends RefCounted
## Shared presentation-only projection contract for the Phase 2A prototype.
## Logical terrain coordinates and elevation remain owned by TerrainWorld.

const HALF_WIDTH := 32
const HALF_HEIGHT := 16
const HEIGHT_STEP := 16
const EDGE_JITTER := 2
const REFINED_VERTEX_SPAN := 6
const REFINED_EDGE_SPAN := 5

const NORTH := 0
const EAST := 1
const SOUTH := 2
const WEST := 3


static func project_grid_point(point: Vector2, elevation: float = 0.0) -> Vector2:
	return Vector2(
		(point.x - point.y) * HALF_WIDTH,
		(point.x + point.y) * HALF_HEIGHT - elevation * HEIGHT_STEP).round()


static func project_cell_center(cell: Vector2i, elevation: int) -> Vector2:
	return project_grid_point(Vector2(cell) + Vector2.ONE * 0.5, elevation)


static func inverse_ground_point(screen_position: Vector2, elevation: float = 0.0) -> Vector2:
	var difference: float = screen_position.x / float(HALF_WIDTH)
	var total: float = (
		screen_position.y + elevation * HEIGHT_STEP) / float(HALF_HEIGHT)
	return Vector2((total + difference) * 0.5, (total - difference) * 0.5)


static func cell_polygon(
		cell: Vector2i, elevation: int, world_seed: int,
		refined: bool = false, height_lookup: Callable = Callable()) -> PackedVector2Array:
	var corners := _cell_grid_corners(cell)
	if refined:
		var projected_corners := PackedVector2Array([
			_refined_grid_point(corners[0], elevation, world_seed, height_lookup),
			_refined_grid_point(corners[1], elevation, world_seed, height_lookup),
			_refined_grid_point(corners[2], elevation, world_seed, height_lookup),
			_refined_grid_point(corners[3], elevation, world_seed, height_lookup),
		])
		return PackedVector2Array([
			projected_corners[0],
			_refined_edge_midpoint(corners[0], corners[1], projected_corners[0], projected_corners[1], world_seed),
			projected_corners[1],
			_refined_edge_midpoint(corners[1], corners[2], projected_corners[1], projected_corners[2], world_seed),
			projected_corners[2],
			_refined_edge_midpoint(corners[2], corners[3], projected_corners[2], projected_corners[3], world_seed),
			projected_corners[3],
			_refined_edge_midpoint(corners[3], corners[0], projected_corners[3], projected_corners[0], world_seed),
		])
	return PackedVector2Array([
		project_grid_point(corners[0], elevation),
		project_edge_midpoint(corners[0], corners[1], elevation, world_seed),
		project_grid_point(corners[1], elevation),
		project_edge_midpoint(corners[1], corners[2], elevation, world_seed),
		project_grid_point(corners[2], elevation),
		project_edge_midpoint(corners[2], corners[3], elevation, world_seed),
		project_grid_point(corners[3], elevation),
		project_edge_midpoint(corners[3], corners[0], elevation, world_seed),
	])


static func edge_points(
		cell: Vector2i, direction: int, elevation: int,
		world_seed: int, refined: bool = false,
		height_lookup: Callable = Callable()) -> PackedVector2Array:
	var polygon := cell_polygon(
		cell, elevation, world_seed, refined, height_lookup)
	match direction:
		NORTH:
			return PackedVector2Array([polygon[0], polygon[1], polygon[2]])
		EAST:
			return PackedVector2Array([polygon[2], polygon[3], polygon[4]])
		SOUTH:
			return PackedVector2Array([polygon[4], polygon[5], polygon[6]])
		_:
			return PackedVector2Array([polygon[6], polygon[7], polygon[0]])


static func project_edge_midpoint(
		first: Vector2, second: Vector2, elevation: int,
		world_seed: int) -> Vector2:
	var first_i := Vector2i(roundi(first.x), roundi(first.y))
	var second_i := Vector2i(roundi(second.x), roundi(second.y))
	var minimum := first_i
	var maximum := second_i
	if second_i.x < first_i.x or (second_i.x == first_i.x and second_i.y < first_i.y):
		minimum = second_i
		maximum = first_i
	var jitter: int = posmod(_hash_int(
		minimum.x, minimum.y, maximum.x * 31 + maximum.y,
		world_seed, 47), EDGE_JITTER * 2 + 1) - EDGE_JITTER
	var projected: Vector2 = (
		project_grid_point(first, elevation)
		+ project_grid_point(second, elevation)) * 0.5
	if first_i.y == second_i.y:
		projected += Vector2(-jitter, jitter * 2)
	else:
		projected += Vector2(jitter, jitter * 2)
	return projected.round()


static func visible_cell_bounds(screen_rect: Rect2, max_elevation: int) -> Rect2i:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var corners := [
		screen_rect.position,
		Vector2(screen_rect.end.x, screen_rect.position.y),
		screen_rect.end,
		Vector2(screen_rect.position.x, screen_rect.end.y),
	]
	for elevation in [0, max_elevation]:
		for corner in corners:
			var logical := inverse_ground_point(corner, elevation)
			minimum.x = minf(minimum.x, logical.x)
			minimum.y = minf(minimum.y, logical.y)
			maximum.x = maxf(maximum.x, logical.x)
			maximum.y = maxf(maximum.y, logical.y)
	var first := Vector2i(floori(minimum.x) - 2, floori(minimum.y) - 2)
	var last := Vector2i(ceili(maximum.x) + 2, ceili(maximum.y) + 2)
	return Rect2i(first, last - first + Vector2i.ONE)


static func contains_point(
		cell: Vector2i, elevation: int, screen_position: Vector2,
		world_seed: int, refined: bool = false,
		height_lookup: Callable = Callable()) -> bool:
	return Geometry2D.is_point_in_polygon(
		screen_position, cell_polygon(
			cell, elevation, world_seed, refined, height_lookup))


static func edge_neighbor(direction: int) -> Vector2i:
	return [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][direction]


static func _cell_grid_corners(cell: Vector2i) -> Array[Vector2]:
	return [
		Vector2(cell),
		Vector2(cell + Vector2i.RIGHT),
		Vector2(cell + Vector2i.ONE),
		Vector2(cell + Vector2i.DOWN),
	]


static func _refined_grid_point(
		point: Vector2, elevation: int, world_seed: int,
		height_lookup: Callable = Callable()) -> Vector2:
	var point_i := Vector2i(roundi(point.x), roundi(point.y))
	var shaped_point := point
	if height_lookup.is_valid() and elevation > 0:
		var surrounding := [
			Vector2i(-1, -1), Vector2i(0, -1),
			Vector2i(-1, 0), Vector2i(0, 0),
		]
		var directions := [
			Vector2(-0.5, -0.5), Vector2(0.5, -0.5),
			Vector2(-0.5, 0.5), Vector2(0.5, 0.5),
		]
		var occupied: Array[bool] = []
		var occupied_count := 0
		for neighbor_offset in surrounding:
			var is_occupied := int(
				height_lookup.call(point_i + neighbor_offset)) >= elevation
			occupied.append(is_occupied)
			if is_occupied:
				occupied_count += 1
		if occupied_count == 1 or occupied_count == 3:
			var minority_occupied := occupied_count == 1
			for index in range(4):
				if occupied[index] == minority_occupied:
					# Move minority corners close to the half-cell contour. This
					# converts alternating staircase turns into longer diagonals while
					# retaining a pixel-art shoulder and non-degenerate isolated cells.
					var strength := 0.76 if occupied_count == 1 else 0.68
					shaped_point += directions[index] * strength
					break
	var offset := Vector2(
		_coherent_vertex_offset(point_i, world_seed, 71),
		_coherent_vertex_offset(point_i, world_seed, 89))
	return (project_grid_point(shaped_point, elevation) + offset).round()


static func _refined_edge_midpoint(
		first: Vector2, second: Vector2,
		first_projected: Vector2, second_projected: Vector2,
		world_seed: int) -> Vector2:
	var first_i := Vector2i(roundi(first.x), roundi(first.y))
	var second_i := Vector2i(roundi(second.x), roundi(second.y))
	var minimum := first_i
	var maximum := second_i
	if second_i.x < first_i.x or (second_i.x == first_i.x and second_i.y < first_i.y):
		minimum = second_i
		maximum = first_i
	if minimum != first_i:
		var swap := first_projected
		first_projected = second_projected
		second_projected = swap
	var horizontal := minimum.y == maximum.y
	var run_index: int = minimum.x if horizontal else minimum.y
	var lane: int = minimum.y if horizontal else minimum.x
	var jitter := _coherent_edge_offset(
		run_index, lane, world_seed, 107 if horizontal else 131)
	var normal := Vector2(-1.0, 2.0) if horizontal else Vector2(1.0, 2.0)
	return ((first_projected + second_projected) * 0.5 + normal * jitter).round()


static func _coherent_vertex_offset(
		point: Vector2i, world_seed: int, channel: int) -> int:
	var block_x := floori(float(point.x) / REFINED_VERTEX_SPAN)
	var block_y := floori(float(point.y) / REFINED_VERTEX_SPAN)
	var local_x := float(posmod(point.x, REFINED_VERTEX_SPAN)) / REFINED_VERTEX_SPAN
	var local_y := float(posmod(point.y, REFINED_VERTEX_SPAN)) / REFINED_VERTEX_SPAN
	local_x = local_x * local_x * (3.0 - 2.0 * local_x)
	local_y = local_y * local_y * (3.0 - 2.0 * local_y)
	var north_west := _hash_range(block_x, block_y, world_seed, channel, -1, 1)
	var north_east := _hash_range(block_x + 1, block_y, world_seed, channel, -1, 1)
	var south_west := _hash_range(block_x, block_y + 1, world_seed, channel, -1, 1)
	var south_east := _hash_range(block_x + 1, block_y + 1, world_seed, channel, -1, 1)
	return roundi(lerpf(
		lerpf(north_west, north_east, local_x),
		lerpf(south_west, south_east, local_x), local_y))


static func _coherent_edge_offset(
		run_index: int, lane: int, world_seed: int, channel: int) -> int:
	var block := floori(float(run_index) / REFINED_EDGE_SPAN)
	var local := float(posmod(run_index, REFINED_EDGE_SPAN)) / REFINED_EDGE_SPAN
	local = local * local * (3.0 - 2.0 * local)
	var first := _hash_range(block, lane, world_seed, channel, -1, 1)
	var second := _hash_range(block + 1, lane, world_seed, channel, -1, 1)
	return roundi(lerpf(first, second, local))


static func _hash_range(
		a: int, b: int, seed: int, channel: int,
		minimum: int, maximum: int) -> int:
	return minimum + posmod(
		_hash_int(a, b, a * 17 + b * 31, seed, channel),
		maximum - minimum + 1)


static func _hash_int(a: int, b: int, c: int, seed: int, channel: int) -> int:
	var value: int = a * 73856093 ^ b * 19349663 ^ c * 83492791
	value ^= seed * 2654435761
	value ^= channel * 374761393
	value = (value ^ (value >> 13)) * 1274126177
	return value ^ (value >> 16)
