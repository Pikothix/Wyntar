extends SceneTree
## Phase 3F validates the shared presentation-height profile. TerrainRenderer
## owns profile selection; TerrainWorld remains authoritative for elevations.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_steps_and_geometry()
	_test_deterministic_mixed_height_and_seams()
	await _test_runtime_projection_picking_and_rollback()
	if failures.is_empty():
		print("PHASE3F_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE3F_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_profile_steps_and_geometry() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(5, 22):
		for x in range(4, 20):
			var height: int = 1 if y < 10 else (2 if y < 16 else 3)
			heights[Vector2i(x, y)] = height
			materials[Vector2i(x, y)] = 4
	var baseline: Dictionary = _build_fixture(heights, materials, 16)
	var moderate: Dictionary = _build_fixture(heights, materials, 24)
	var prominent: Dictionary = _build_fixture(heights, materials, 32)
	_expect(int(baseline.face_count) == int(moderate.face_count)
		and int(moderate.face_count) == int(prominent.face_count),
		"height profiles preserve deterministic contour ownership")
	_expect(_vertical_span(moderate.meshes) > _vertical_span(baseline.meshes),
		"moderate profile increases visible cliff depth")
	_expect(_vertical_span(prominent.meshes) > _vertical_span(moderate.meshes),
		"prominent profile increases visible cliff depth beyond moderate")
	var path: PackedVector2Array = OrganicCliffMeshBuilder._unified_contour_path(
		[0, 1], 8, 8, 8, Vector2i(8, 8), 2, 84521, 32)
	var unprojected: PackedVector2Array = OrganicCliffMeshBuilder._unified_contour_path(
		[0, 1], 8, 8, 8, Vector2i(8, 8), 2, 84521, 16)
	for index in range(path.size()):
		_expect(roundi(unprojected[index].y - path[index].y) == 32,
			"crest displacement equals the shared profile delta")


func _test_deterministic_mixed_height_and_seams() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(3, 29):
		for x in range(2, 30):
			if x <= y + 2:
				heights[Vector2i(x, y)] = 1 + posmod(floori(float(y) / 6.0), 3)
				materials[Vector2i(x, y)] = 3
	var first: Dictionary = _build_fixture(heights, materials, 32)
	var second: Dictionary = _build_fixture(heights, materials, 32)
	_expect(_geometry_signature(first) == _geometry_signature(second),
		"prominent mixed-height generation is byte-deterministic")
	for boundary_x in [32, -32]:
		var left_coord := Vector2i(floori(float(boundary_x - 1) / 32.0), 0)
		var right_coord := Vector2i(floori(float(boundary_x) / 32.0), 0)
		var left: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
			1, 31, 12, Vector2i(boundary_x - 1, 12), 84521)
		var right: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
			3, 0, 12, Vector2i(boundary_x, 12), 84521)
		left += Vector2(left_coord.x * 32 * 32, 0)
		right += Vector2(right_coord.x * 32 * 32, 0)
		_expect(left == right, "prominent profile preserves signed chunk seam endpoints")


func _test_runtime_projection_picking_and_rollback() -> void:
	var terrain = TerrainRenderer.new()
	terrain.organic_cliff_geometry_enabled = true
	terrain.unified_cliff_components_enabled = true
	terrain.connected_cliff_contours_enabled = true
	terrain.unified_cliff_contours_enabled = true
	root.add_child(terrain)
	await process_frame
	terrain.apply_world_edit_states([{
		"cell": Vector2i.ZERO, "kind": "elevation",
		"state": {"has_override": true, "value": 3},
	}])
	terrain.update_visible_world_rect(Rect2(Vector2(-320, -320), Vector2(640, 640)))
	await _wait_until_idle(terrain)
	var baseline_rect: Rect2 = terrain.get_projected_cell_rect(Vector2i.ZERO)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.PROMINENT)
	await _wait_until_idle(terrain)
	var prominent_rect: Rect2 = terrain.get_projected_cell_rect(Vector2i.ZERO)
	_expect(roundi(baseline_rect.position.y - prominent_rect.position.y) == 48,
		"three-level top surface follows the prominent 32-pixel projection")
	var pick: Dictionary = terrain.pick_world_position(prominent_rect.get_center())
	_expect(pick.cell == Vector2i.ZERO and int(pick.elevation) == 3,
		"picking follows the displaced top surface")
	_expect(terrain.get_world_elevation(Vector2i.ZERO) == 3,
		"profile switching does not mutate authoritative elevation")
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.BASELINE)
	await _wait_until_idle(terrain)
	_expect(terrain.get_projected_cell_rect(Vector2i.ZERO) == baseline_rect,
		"baseline rollback restores the accepted Phase 3E projection")
	terrain.queue_free()


func _build_fixture(heights: Dictionary, materials: Dictionary, height_step: int) -> Dictionary:
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	return OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true, true, true, height_step)


func _vertical_span(meshes: Array) -> int:
	var minimum: float = INF
	var maximum: float = -INF
	for mesh in meshes:
		if mesh == null:
			continue
		for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			minimum = minf(minimum, vertex.y)
			maximum = maxf(maximum, vertex.y)
	return roundi(maximum - minimum)


func _geometry_signature(result: Dictionary) -> Array:
	var signature: Array = [
		int(result.face_count), int(result.vertex_count), int(result.triangle_count)]
	for key in ["meshes", "edge_meshes", "shadow_meshes"]:
		for mesh in result[key]:
			signature.append(null if mesh == null else hash(mesh.surface_get_arrays(0)))
	return signature


func _wait_until_idle(terrain, max_frames: int = 1800) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("Phase 3F runtime rebuild did not become idle")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
