extends RefCounted
## Builds one deterministic, presentation-only oblique mesh for a loaded chunk.
## Shared absolute-coordinate edge samples keep adjacent chunk silhouettes equal.

const ObliqueProjection = preload("res://scripts/oblique_projection.gd")

const CHUNK_SIZE := 32
const MATERIAL_COUNT := 8


static func build(
		chunk_coord: Vector2i, world_seed: int,
		material_lookup: Callable, height_lookup: Callable,
		liquid_by_id: Dictionary, refined: bool = false) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var origin_cell := chunk_coord * CHUNK_SIZE
	var origin_screen := ObliqueProjection.project_grid_point(Vector2(origin_cell), 0)
	var face_count := 0
	var cached_heights: Dictionary = {}
	var build_height_lookup := height_lookup
	if refined:
		build_height_lookup = func(pos: Vector2i) -> int:
			if not cached_heights.has(pos):
				cached_heights[pos] = int(height_lookup.call(pos))
			return int(cached_heights[pos])

	# Back-to-front cell submission gives the single opaque surface a stable
	# painter order while retaining one mesh node per streamed chunk.
	for diagonal in range(CHUNK_SIZE * 2 - 1):
		for local_y in range(CHUNK_SIZE):
			var local_x: int = diagonal - local_y
			if local_x < 0 or local_x >= CHUNK_SIZE:
				continue
			var cell := origin_cell + Vector2i(local_x, local_y)
			var elevation: int = int(build_height_lookup.call(cell))
			var material_id: int = clampi(int(material_lookup.call(cell)), 0, MATERIAL_COUNT - 1)
			for direction in range(4):
				var neighbor: Vector2i = cell + ObliqueProjection.edge_neighbor(direction)
				var neighbor_height: int = int(build_height_lookup.call(neighbor))
				if elevation <= neighbor_height:
					continue
				var shoreline: bool = bool(liquid_by_id.get(
					int(material_lookup.call(neighbor)), false))
				_append_face(
					vertices, colors, uvs, indices, origin_screen,
					cell, direction, elevation, neighbor_height,
					material_id, shoreline, world_seed, refined, build_height_lookup)
				face_count += 1
			_append_top(
				vertices, colors, uvs, indices, origin_screen,
				cell, elevation, material_id, world_seed, refined, build_height_lookup)

	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {
		"mesh": mesh,
		"origin": origin_screen,
		"build_usec": Time.get_ticks_usec() - started_usec,
		"vertex_count": vertices.size(),
		"triangle_count": indices.size() / 3,
		"face_count": face_count,
	}


static func _append_top(
		vertices: PackedVector2Array, colors: PackedColorArray,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		origin_screen: Vector2, cell: Vector2i, elevation: int,
		material_id: int, world_seed: int, refined: bool,
		height_lookup: Callable) -> void:
	var polygon := ObliqueProjection.cell_polygon(
		cell, elevation, world_seed, refined, height_lookup)
	var local_uvs := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0),
		Vector2(1.0, 0.5), Vector2(1.0, 1.0), Vector2(0.5, 1.0),
		Vector2(0.0, 1.0), Vector2(0.0, 0.5),
	])
	var center: Vector2 = ObliqueProjection.project_cell_center(cell, elevation)
	var base: int = vertices.size()
	vertices.append(center - origin_screen)
	colors.append(Color(
		_surface_value(center, world_seed) if refined else 1.0,
		0.0, 0.0, 1.0))
	uvs.append(_atlas_uv(material_id, Vector2(0.5, 0.5)))
	for index in range(polygon.size()):
		vertices.append(polygon[index] - origin_screen)
		colors.append(Color(
			_surface_value(polygon[index], world_seed) if refined else 1.0,
			0.0, 0.0, 1.0))
		uvs.append(_atlas_uv(material_id, local_uvs[index]))
	for index in range(polygon.size()):
		indices.append_array(PackedInt32Array([
			base, base + 1 + index, base + 1 + (index + 1) % polygon.size()]))


static func _append_face(
		vertices: PackedVector2Array, colors: PackedColorArray,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		origin_screen: Vector2, cell: Vector2i, direction: int,
		top_elevation: int, bottom_elevation: int, material_id: int,
		shoreline: bool, world_seed: int, refined: bool,
		height_lookup: Callable) -> void:
	var top := ObliqueProjection.edge_points(
		cell, direction, top_elevation, world_seed, refined, height_lookup)
	var bottom := ObliqueProjection.edge_points(
		cell, direction, bottom_elevation, world_seed, refined, height_lookup)
	var direction_shades := [0.74, 0.88, 0.80, 0.66]
	var shade: float = direction_shades[direction]
	for segment in range(2):
		var base: int = vertices.size()
		vertices.append_array(PackedVector2Array([
			top[segment] - origin_screen,
			top[segment + 1] - origin_screen,
			bottom[segment + 1] - origin_screen,
			bottom[segment] - origin_screen,
		]))
		var encoded := Color(shade, 1.0, 1.0 if shoreline else 0.0, 1.0)
		colors.append_array(PackedColorArray([encoded, encoded, encoded, encoded]))
		var u0: float = float(segment) * 0.5
		var u1: float = float(segment + 1) * 0.5
		uvs.append_array(PackedVector2Array([
			_atlas_uv(material_id, Vector2(u0, 0.02)),
			_atlas_uv(material_id, Vector2(u1, 0.02)),
			_atlas_uv(material_id, Vector2(u1, 0.98)),
			_atlas_uv(material_id, Vector2(u0, 0.98)),
		]))
		indices.append_array(PackedInt32Array([
			base, base + 1, base + 2, base, base + 2, base + 3]))


static func _atlas_uv(material_id: int, local_uv: Vector2) -> Vector2:
	var bounded := Vector2(
		clampf(local_uv.x, 0.01, 0.99), clampf(local_uv.y, 0.01, 0.99))
	return Vector2(
		(float(material_id) + bounded.x) / float(MATERIAL_COUNT),
		bounded.y)


static func _surface_value(point: Vector2, world_seed: int) -> float:
	const SPAN := 112.0
	var logical := Vector2(
		(point.x + point.y * 0.35) / SPAN,
		(point.y - point.x * 0.18) / SPAN)
	var base := Vector2i(floori(logical.x), floori(logical.y))
	var blend := Vector2(fposmod(logical.x, 1.0), fposmod(logical.y, 1.0))
	blend = Vector2(
		blend.x * blend.x * (3.0 - 2.0 * blend.x),
		blend.y * blend.y * (3.0 - 2.0 * blend.y))
	var north_west := _surface_hash(base.x, base.y, world_seed)
	var north_east := _surface_hash(base.x + 1, base.y, world_seed)
	var south_west := _surface_hash(base.x, base.y + 1, world_seed)
	var south_east := _surface_hash(base.x + 1, base.y + 1, world_seed)
	return lerpf(
		lerpf(north_west, north_east, blend.x),
		lerpf(south_west, south_east, blend.x), blend.y)


static func _surface_hash(x: int, y: int, world_seed: int) -> float:
	var value: int = x * 73856093 ^ y * 19349663 ^ world_seed * 83492791
	value = (value ^ (value >> 13)) * 1274126177
	value ^= value >> 16
	return float(posmod(value, 1024)) / 1023.0
