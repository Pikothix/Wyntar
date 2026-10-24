extends SceneTree
## C4E.1 guards the near-vertical contour case that previously rendered as
## disconnected pointed fragments even though raw crest endpoints matched.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_near_vertical_side_return()
	_test_shared_endpoint_continuity()
	if failures.is_empty():
		print("PHASE_C4E1_CLIFF_CONTINUITY_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_C4E1_CLIFF_CONTINUITY_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_near_vertical_side_return() -> void:
	var buffer: Dictionary = OrganicCliffMeshBuilder._new_buffer()
	var path := PackedVector2Array([
		Vector2(32, 0), Vector2(34, 16), Vector2(32, 32)])
	OrganicCliffMeshBuilder._append_unified_offset_strip(
		buffer, path, -16, 33, 5, 0.96, 0, 0, 1.0, 17, {}, true)
	var vertices: PackedVector2Array = buffer.vertices
	_expect(vertices.size() == 4,
		"near-vertical path emits one continuous canonical side-return quad")
	if vertices.size() != 4:
		return
	var side_return: Vector2 = vertices[3] - vertices[0]
	_expect(absf(side_return.x) >= 5.0 and absf(side_return.y) <= 1.0,
		"near-vertical run uses a lateral side return, not a pointed projection")
	_expect(vertices[1] - vertices[0] == path[2] - path[0],
		"side-return strip preserves canonical shared endpoints")


func _test_shared_endpoint_continuity() -> void:
	for boundary_x in [32, -32]:
		var left_coord := Vector2i(floori(float(boundary_x - 1) / 32.0), 0)
		var right_coord := Vector2i(floori(float(boundary_x) / 32.0), 0)
		for y in range(2, 28):
			var left: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
				1, 31, y, Vector2i(boundary_x - 1, y), 84521)
			var right: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
				3, 0, y, Vector2i(boundary_x, y), 84521)
			left += Vector2(left_coord.x * 32 * 32, 0)
			right += Vector2(right_coord.x * 32 * 32, 0)
			_expect(left == right,
				"raw contour endpoints remain canonical across signed chunk seams")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
