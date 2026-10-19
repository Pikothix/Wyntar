extends SceneTree
## Phase 3D validates connected southern contour profiles while retaining the
## Phase 3C watertight-boundary contract and incremental/chunk determinism.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_connected_run_profile()
	_test_mixed_height_fallback()
	_test_incremental_determinism()
	_test_chunk_seams()
	if failures.is_empty():
		print("PHASE3D_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE3D_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_connected_run_profile() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for x in range(4, 20):
		heights[Vector2i(x, 8)] = 3
		materials[Vector2i(x, 8)] = 4
	var baseline: Dictionary = _build_fixture(
		Vector2i.ZERO, heights, materials, false)
	var prototype: Dictionary = _build_fixture(
		Vector2i.ZERO, heights, materials, true)
	_expect(int(prototype.face_count) == int(baseline.face_count),
		"connected profiling does not change authoritative face ownership")
	_expect(int(prototype.vertex_count) > int(baseline.vertex_count),
		"long connected runs receive the denser eight-pixel profile")
	var mesh: ArrayMesh = prototype.meshes[2]
	_expect(mesh != null, "long height-three run creates a face batch")
	if mesh == null:
		return
	var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var crest := PackedVector2Array()
	for vertex in vertices:
		if vertex.x >= 5 * 32 and vertex.x <= 19 * 32 and vertex.y <= 9 * 32 - 3 * 16:
			crest.append(vertex)
	var y_values: Array[int] = []
	for vertex in crest:
		var y: int = roundi(vertex.y)
		if not y_values.has(y):
			y_values.append(y)
	_expect(y_values.size() >= 3,
		"formation and rock fields create coherent non-flat run variation")


func _test_mixed_height_fallback() -> void:
	var left := Vector2i(10, 10)
	var right := Vector2i(11, 10)
	var heights := {left: 3, right: 3, right + Vector2i.DOWN: 1}
	var materials := {left: 2, right: 2, right + Vector2i.DOWN: 2}
	var baseline: Dictionary = _build_fixture(
		Vector2i.ZERO, heights, materials, false)
	var prototype: Dictionary = _build_fixture(
		Vector2i.ZERO, heights, materials, true)
	_expect(int(prototype.vertex_count) == int(baseline.vertex_count)
		and int(prototype.triangle_count) == int(baseline.triangle_count),
		"mixed-height junction retains conservative Phase 3C topology")
	var vertices: PackedVector2Array = prototype.meshes[2].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(vertices[5] == vertices[24] and vertices[6] == vertices[27],
		"mixed-height upper band remains watertight")
	_expect(vertices[13] == vertices[32] and vertices[14] == vertices[35],
		"mixed-height lower shared band remains watertight")
	_expect(vertices[21] == vertices[14],
		"mixed-height exposed cap begins at the shared endpoint")


func _test_incremental_determinism() -> void:
	var heights := PackedByteArray()
	var materials := PackedInt32Array()
	heights.resize(34 * 34)
	materials.resize(34 * 34)
	materials.fill(3)
	for x in range(1, 33):
		var index: int = (12 + 1) * 34 + x
		heights[index] = 2
		materials[index] = 4
	var state: Dictionary = OrganicCliffMeshBuilder.create_incremental(
		Vector2i.ZERO, 3, 84521, materials, heights, {0: true},
		true, true, true)
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
		{0: true}, true, true, true)
	_expect(_geometry_signature(incremental) == _geometry_signature(synchronous),
		"incremental and synchronous connected builds are byte-identical")


func _test_chunk_seams() -> void:
	for boundary_x in [32, -32]:
		var heights: Dictionary = {}
		var materials: Dictionary = {}
		for x in range(boundary_x - 8, boundary_x + 8):
			heights[Vector2i(x, 6)] = 2
			materials[Vector2i(x, 6)] = 4
		var left_coord := Vector2i(floori(float(boundary_x - 1) / 32.0), 0)
		var right_coord := Vector2i(floori(float(boundary_x) / 32.0), 0)
		var left: Dictionary = _build_fixture(left_coord, heights, materials, true)
		var right: Dictionary = _build_fixture(right_coord, heights, materials, true)
		var left_mesh: ArrayMesh = left.meshes[1]
		var right_mesh: ArrayMesh = right.meshes[1]
		_expect(left_mesh != null and right_mesh != null,
			"seam fixture creates both chunk face batches at x=%d" % boundary_x)
		if left_mesh == null or right_mesh == null:
			continue
		_expect(_boundary_y_values(left_mesh, 32 * 32)
			== _boundary_y_values(right_mesh, 0),
			"positive/negative chunk seam shares exact connected vertices at x=%d" % boundary_x)


func _build_fixture(
		chunk_coord: Vector2i, heights: Dictionary, materials: Dictionary,
		connected: bool) -> Dictionary:
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	return OrganicCliffMeshBuilder.build(
		chunk_coord, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true, connected)


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


func _boundary_y_values(mesh: ArrayMesh, local_x: int) -> Array[int]:
	var values: Array[int] = []
	for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if roundi(vertex.x) != local_x:
			continue
		var y: int = roundi(vertex.y)
		if not values.has(y):
			values.append(y)
	values.sort()
	return values


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
