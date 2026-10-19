extends SceneTree
## Phase 3C validates that independently emitted face rows share exact cap
## endpoints and that refined returns meet the corrected face corners.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_exposed_corner_continuity()
	_test_partial_height_connection()
	if failures.is_empty():
		print("PHASE3C_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE3C_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_exposed_corner_continuity() -> void:
	var owner := Vector2i(10, 10)
	var heights := {owner: 3}
	var materials := {owner: 2}
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var first: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true)
	var second: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true)
	var face: ArrayMesh = first.meshes[2]
	var edges: ArrayMesh = first.edge_meshes[2]
	_expect(face != null and edges != null,
		"isolated height-three fixture creates face and edge batches")
	if face == null or edges == null:
		return
	var face_vertices: PackedVector2Array = face.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var edge_vertices: PackedVector2Array = edges.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(face_vertices.size() == 24,
		"three-row isolated face retains six batched quads")
	_expect(edge_vertices.size() == 20,
		"isolated corner retains one lip and two three-point return strips")
	if face_vertices.size() != 24 or edge_vertices.size() != 20:
		return
	_expect(face_vertices[5].x - face_vertices[0].x >= 28.0,
		"corrected crest still covers the full 32-pixel south face")
	_expect(face_vertices[22].x - face_vertices[19].x >= 28.0,
		"corrected foot still covers the full 32-pixel south face")

	# Two quads are emitted per row. Their exposed left/right bottom vertices
	# must be the exact top vertices of the following row.
	for row in range(2):
		var first_quad: int = row * 8
		var second_quad: int = first_quad + 4
		var next_first_quad: int = (row + 1) * 8
		var next_second_quad: int = next_first_quad + 4
		_expect(face_vertices[first_quad + 3] == face_vertices[next_first_quad],
			"west face cap is continuous between rows %d and %d" % [row, row + 1])
		_expect(face_vertices[second_quad + 2] == face_vertices[next_second_quad + 1],
			"east face cap is continuous between rows %d and %d" % [row, row + 1])

	# Lip vertices occupy 0..7, west-return vertices 8..13, and east-return
	# vertices 14..19. Each return's final outer point meets the face crest.
	_expect(edge_vertices[12] == face_vertices[0],
		"west return terminates on the corrected west face corner")
	_expect(edge_vertices[18] == face_vertices[5],
		"east return terminates on the corrected east face corner")

	var second_face: ArrayMesh = second.meshes[2]
	var second_edges: ArrayMesh = second.edge_meshes[2]
	_expect(hash(face_vertices) == hash(
		second_face.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
		"corrected face corners remain deterministic")
	_expect(hash(edge_vertices) == hash(
		second_edges.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
		"corrected return joints remain deterministic")


func _test_partial_height_connection() -> void:
	var left := Vector2i(10, 10)
	var right := Vector2i(11, 10)
	var heights := {left: 3, right: 3, right + Vector2i.DOWN: 1}
	var materials := {left: 2, right: 2, right + Vector2i.DOWN: 2}
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var result: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true)
	var face: ArrayMesh = result.meshes[2]
	_expect(face != null, "mixed-drop fixture creates the height-three face batch")
	if face == null:
		return
	var vertices: PackedVector2Array = face.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(vertices.size() == 40,
		"mixed-drop fixture retains three left rows and two right rows")
	if vertices.size() != 40:
		return
	# The two common bands connect exactly. The unmatched lowest band begins at
	# the same endpoint, then receives its own material-coloured exposed cap.
	_expect(vertices[5] == vertices[24] and vertices[6] == vertices[27],
		"upper shared band connects without overlap")
	_expect(vertices[13] == vertices[32] and vertices[14] == vertices[35],
		"lower shared band connects without overlap")
	_expect(vertices[21] == vertices[14],
		"newly exposed lower cap begins at the shared face endpoint")
	_expect(vertices[22].x == 11.0 * 32.0 + roundi(
		OrganicCliffMeshBuilder._face_cap_offset(left, 1.0, 84521, false)),
		"unmatched lower band ends on its deterministic exposed cap")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
