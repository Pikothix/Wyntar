extends SceneTree
## Phase 3E validates bounded marching contours, shared absolute endpoints,
## incremental determinism, mixed-height safety, and the Phase 3D rollback.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_diagonal_contour_change()
	_test_corner_and_mixed_height_geometry()
	_test_incremental_determinism()
	_test_chunk_seams()
	await _test_runtime_rollback_and_edit_regeneration()
	if failures.is_empty():
		print("PHASE3E_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE3E_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_diagonal_contour_change() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(3, 25):
		for x in range(3, 25):
			if x <= y:
				heights[Vector2i(x, y)] = 2
				materials[Vector2i(x, y)] = 4
	var phase3d: Dictionary = _build_fixture(Vector2i.ZERO, heights, materials, false)
	var phase3e: Dictionary = _build_fixture(Vector2i.ZERO, heights, materials, true)
	_expect(_geometry_signature(phase3d) != _geometry_signature(phase3e),
		"Phase 3E changes the contour topology rather than only shading Phase 3D")
	var vertices: PackedVector2Array = _all_vertices(phase3e.meshes)
	var diagonal_edges: int = 0
	for index in range(0, vertices.size() - 2, 6):
		var delta: Vector2 = vertices[index + 2] - vertices[index]
		if not is_zero_approx(delta.x) and not is_zero_approx(delta.y):
			diagonal_edges += 1
	_expect(diagonal_edges > 8,
		"diagonal staircase is represented by actual diagonal face edges")


func _test_corner_and_mixed_height_geometry() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(6, 18):
		for x in range(6, 18):
			var height: int = 3 if x < 12 else (2 if y < 12 else 1)
			heights[Vector2i(x, y)] = height
			materials[Vector2i(x, y)] = 2 if x < 14 else 4
	# Concave notch and isolated saddle exercise turns and ambiguous cases.
	heights.erase(Vector2i(8, 16))
	heights[Vector2i(18, 18)] = 3
	heights[Vector2i(19, 19)] = 3
	var result: Dictionary = _build_fixture(Vector2i.ZERO, heights, materials, true)
	_expect(int(result.face_count) > 0 and int(result.edge_component_count) > 0,
		"mixed-height turns create unified batched components")
	for key in ["meshes", "edge_meshes", "shadow_meshes"]:
		for mesh in result[key]:
			if mesh == null:
				continue
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var a: Vector2 = vertices[indices[index]]
				var b: Vector2 = vertices[indices[index + 1]]
				var c: Vector2 = vertices[indices[index + 2]]
				_expect(not is_zero_approx((b - a).cross(c - a)),
					"unified contour contains no degenerate triangles")


func _test_incremental_determinism() -> void:
	var heights := PackedByteArray()
	var materials := PackedInt32Array()
	heights.resize(34 * 34)
	materials.resize(34 * 34)
	materials.fill(3)
	for y in range(1, 33):
		for x in range(1, 33):
			if x <= y + 3:
				heights[y * 34 + x] = 1 + int(posmod(y / 7, 3))
				materials[y * 34 + x] = 4
	var state: Dictionary = OrganicCliffMeshBuilder.create_incremental(
		Vector2i.ZERO, 3, 84521, materials, heights, {0: true},
		true, true, true, true)
	while not OrganicCliffMeshBuilder.is_incremental_ready(state):
		OrganicCliffMeshBuilder.process_incremental(state, 7)
	var incremental: Dictionary = OrganicCliffMeshBuilder.finalize_incremental(state)
	var height_lookup := func(pos: Vector2i) -> int:
		var local := pos + Vector2i.ONE
		return int(heights[local.y * 34 + local.x])
	var material_lookup := func(pos: Vector2i) -> int:
		var local := pos + Vector2i.ONE
		return int(materials[local.y * 34 + local.x])
	var synchronous: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true, true, true)
	_expect(_geometry_signature(incremental) == _geometry_signature(synchronous),
		"incremental and synchronous Phase 3E builds are byte-identical")


func _test_chunk_seams() -> void:
	for boundary_x in [32, -32]:
		var left_coord := Vector2i(floori(float(boundary_x - 1) / 32.0), 0)
		var right_coord := Vector2i(floori(float(boundary_x) / 32.0), 0)
		for y in range(2, 28):
			var left_point: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
				1, 31, y, Vector2i(boundary_x - 1, y), 84521)
			left_point += Vector2(left_coord.x * 32 * 32, 0)
			var right_point: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
				3, 0, y, Vector2i(boundary_x, y), 84521)
			right_point += Vector2(right_coord.x * 32 * 32, 0)
			_expect(left_point == right_point,
				"positive/negative Phase 3E seam shares exact endpoint at %s"
				% Vector2i(boundary_x, y))


func _test_runtime_rollback_and_edit_regeneration() -> void:
	var terrain = TerrainRenderer.new()
	terrain.organic_cliff_geometry_enabled = true
	terrain.connected_cliff_contours_enabled = true
	terrain.unified_cliff_contours_enabled = false
	root.add_child(terrain)
	await process_frame
	terrain.update_visible_world_rect(Rect2(Vector2(-320, -320), Vector2(640, 640)))
	await _wait_until_idle(terrain)
	terrain.set_unified_cliff_contours_enabled(true)
	_expect(terrain.is_unified_cliff_contours_enabled(),
		"runtime switch enables Phase 3E")
	terrain.apply_world_edit_states([{
		"cell": Vector2i.ZERO, "kind": "elevation",
		"state": {"has_override": true, "value": 3},
	}])
	await _wait_until_idle(terrain)
	_expect(terrain.get_world_elevation(Vector2i.ZERO) == 3,
		"authoritative terrain edit survives Phase 3E contour regeneration")
	terrain.set_unified_cliff_contours_enabled(false)
	await _wait_until_idle(terrain)
	_expect(not terrain.is_unified_cliff_contours_enabled(),
		"runtime rollback restores the Phase 3D mode")
	terrain.queue_free()


func _build_fixture(
		chunk_coord: Vector2i, heights: Dictionary, materials: Dictionary,
		unified: bool) -> Dictionary:
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	return OrganicCliffMeshBuilder.build(
		chunk_coord, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true, true, unified)


func _all_vertices(meshes: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for mesh in meshes:
		if mesh != null:
			result.append_array(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	return result


func _boundary_y_values(result: Dictionary, local_x: int) -> Array[int]:
	var values: Array[int] = []
	for key in ["meshes", "edge_meshes", "shadow_meshes"]:
		for vertex in _all_vertices(result[key]):
			if roundi(vertex.x) == local_x and not values.has(roundi(vertex.y)):
				values.append(roundi(vertex.y))
	values.sort()
	return values


func _geometry_signature(result: Dictionary) -> Array:
	var signature: Array = [
		int(result.face_count), int(result.edge_component_count),
		int(result.shadow_count), int(result.vertex_count), int(result.triangle_count)]
	for key in ["meshes", "edge_meshes", "shadow_meshes"]:
		for mesh in result[key]:
			if mesh == null:
				signature.append(null)
				continue
			signature.append(hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]))
			signature.append(hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]))
			signature.append(hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]))
	return signature


func _wait_until_idle(terrain, max_frames: int = 1600) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("Phase 3E streaming/edit rebuild did not become idle")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
