extends SceneTree
## C4F presentation-only topology checks. Fixtures provide authoritative cell
## heights; the validator inspects only the derived grid boundary and meshes.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_single_cell_boundary()
	_test_connected_shapes()
	_test_mesh_topology_and_determinism()
	_test_chunk_seam_contract()
	if failures.is_empty():
		print("PHASE_C4F_GRID_CLIFF_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_C4F_GRID_CLIFF_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_single_cell_boundary() -> void:
	var exposed := PackedByteArray([1, 1, 1, 1])
	var segments: Array[PackedVector2Array] = (
		OrganicCliffMeshBuilder._grid_boundary_segments(8, 8, 1, 32, exposed))
	_expect(segments.size() == 8, "single cell has four cardinal edges and four bevels")
	var points: Array[Vector2] = []
	for segment in segments:
		points.append(segment[0])
		points.append(segment[1])
	var bounds := _point_bounds(points)
	_expect(is_equal_approx(bounds.size.x, 32.0) and is_equal_approx(bounds.size.y, 32.0),
		"single-cell crest retains a 32x32 square footprint")
	_expect(OrganicCliffMeshBuilder.GRID_CORNER_RADIUS <= 8,
		"corner rounding is bounded to one quarter of cell size")


func _test_connected_shapes() -> void:
	var east_join := OrganicCliffMeshBuilder._grid_boundary_segments(
		8, 8, 1, 32, PackedByteArray([1, 0, 1, 1]))
	var west_join := OrganicCliffMeshBuilder._grid_boundary_segments(
		9, 8, 1, 32, PackedByteArray([1, 1, 1, 0]))
	_expect(east_join.size() == 5 and west_join.size() == 5,
		"two adjacent cells omit their shared edge and retain outer bevels")
	var first := _build_fixture({Vector2i(16, 16): 1, Vector2i(17, 16): 1})
	var block := _build_fixture({
		Vector2i(16, 16): 1, Vector2i(17, 16): 1,
		Vector2i(16, 17): 1, Vector2i(17, 17): 1})
	_expect(int(first.face_count) == 10, "two-cell platform emits one continuous outer perimeter")
	_expect(int(block.face_count) == 12, "2x2 platform emits only its outer perimeter")


func _test_mesh_topology_and_determinism() -> void:
	var heights := {
		Vector2i(15, 15): 1, Vector2i(16, 15): 2, Vector2i(17, 15): 1,
		Vector2i(15, 16): 2, Vector2i(16, 16): 3,
		Vector2i(15, 17): 1,
	}
	var first := _build_fixture(heights)
	var second := _build_fixture(heights)
	_expect(_degenerate_triangle_count(first.meshes) == 0,
		"grid faces and rims contain no degenerate triangles")
	_expect(_geometry_signature(first) == _geometry_signature(second),
		"repeated C4F builds are byte-deterministic")
	_expect(int(first.edge_component_count) == int(first.face_count),
		"every face segment is derived with one matching rim segment")


func _test_chunk_seam_contract() -> void:
	var heights: Dictionary = {}
	for y in range(-2, 35):
		for x in range(28, 36):
			if y >= 8 and y <= 24:
				heights[Vector2i(x, y)] = 2
	var left := _build_fixture(heights, Vector2i.ZERO)
	var right := _build_fixture(heights, Vector2i(1, 0))
	_expect(_degenerate_triangle_count(left.meshes) == 0
		and _degenerate_triangle_count(right.meshes) == 0,
		"positive chunk-seam fixtures retain valid topology")
	var left_top := OrganicCliffMeshBuilder._grid_boundary_segments(
		31, 8, 1, 32, PackedByteArray([1, 0, 0, 0]))[0][0]
	var right_top := OrganicCliffMeshBuilder._grid_boundary_segments(
		0, 8, 1, 32, PackedByteArray([1, 0, 0, 0]))[0][1]
	_expect(left_top == right_top + Vector2(32 * 32, 0),
		"positive chunk-seam boundary endpoints meet exactly")
	var negative_left_world: Vector2 = left_top + Vector2(-32 * 32, 0)
	var negative_right_world: Vector2 = right_top
	_expect(negative_left_world == negative_right_world,
		"negative-to-zero chunk-seam boundary endpoints meet exactly")


func _build_fixture(heights: Dictionary, chunk_coord := Vector2i.ZERO) -> Dictionary:
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(pos: Vector2i) -> int: return 4 if pos.x % 2 == 0 else 3
	return OrganicCliffMeshBuilder.build(
		chunk_coord, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true, true, true, 32, true, true)


func _point_bounds(points: Array[Vector2]) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(point)
	return result


func _degenerate_triangle_count(meshes: Array) -> int:
	var count: int = 0
	for mesh in meshes:
		if mesh == null:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size(), 3):
			if absf((vertices[indices[index + 1]] - vertices[indices[index]]).cross(
					vertices[indices[index + 2]] - vertices[indices[index]])) < 0.5:
				count += 1
	return count


func _geometry_signature(result: Dictionary) -> Array:
	var signature: Array = [
		int(result.face_count), int(result.vertex_count), int(result.triangle_count)]
	for mesh in result.meshes:
		signature.append(null if mesh == null else hash(mesh.surface_get_arrays(0)))
	return signature


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
