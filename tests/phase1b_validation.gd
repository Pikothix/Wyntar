extends SceneTree
## Phase 1B validates deterministic chunk-batched geometry, seam sampling,
## rollback, presentation ownership, and editing-triggered mesh rebuilds.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_world_coordinate_profiles()
	_test_builder_determinism()
	await _test_renderer_and_editing()
	if failures.is_empty():
		print("PHASE1B_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1B_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_world_coordinate_profiles() -> void:
	for boundary_x in [32 * 32, -32 * 32, 0]:
		for channel in range(2):
			var left_value: int = OrganicCliffMeshBuilder.outline_offset(
				boundary_x, 17, 2, 84521, channel)
			var right_value: int = OrganicCliffMeshBuilder.outline_offset(
				boundary_x, 17, 2, 84521, channel)
			_expect(left_value == right_value,
				"both chunk owners derive the same outline at x=%d" % boundary_x)
			_expect(left_value >= -3 and left_value <= 3,
				"outline remains pixel-quantised and bounded")


func _test_builder_determinism() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(4, 11):
		for x in range(25, 40):
			heights[Vector2i(x, y)] = 3 if x < 34 else 2
			materials[Vector2i(x, y)] = 4
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var first: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup,
		{0: true})
	var second: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup,
		{0: true})
	var neighbor: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(1, 0), 3, 84521, world_lookup, height_lookup,
		{0: true})
	_expect(int(first.face_count) > 0, "fixture produces organic cliff faces")
	_expect(int(first.vertex_count) > int(first.face_count) * 4,
		"faces contain internal fractured polygon topology")
	_expect(int(first.vertex_count) == int(second.vertex_count)
		and int(first.triangle_count) == int(second.triangle_count),
		"repeated builds produce identical geometry counts")
	var first_mesh: ArrayMesh = first.meshes[2]
	var second_mesh: ArrayMesh = second.meshes[2]
	_expect(first_mesh != null and second_mesh != null,
		"multilevel fixture creates a height-three batch")
	if first_mesh != null and second_mesh != null:
		_expect(hash(first_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			== hash(second_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
			"repeated builds produce byte-identical vertex positions")
		var neighbor_mesh: ArrayMesh = neighbor.meshes[2]
		_expect(neighbor_mesh != null, "adjacent chunk owns the continuing face")
		if neighbor_mesh != null:
			_expect(_boundary_y_values(first_mesh, 32 * 32)
				== _boundary_y_values(neighbor_mesh, 0),
				"adjacent chunk meshes share exact boundary vertices")


func _test_renderer_and_editing() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(5)
	terrain = demo.terrain
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	for y in range(2, 11):
		for x in range(24, 41):
			terrain.world.set_override(Vector2i(x, y), 4)
			terrain.world.set_elevation_override(Vector2i(x, y), 3)
	terrain._invalidate_streamed_chunks()
	demo.camera.position = Vector2(Vector2i(32, 8) * terrain.TILE_SIZE)
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()

	var snapshot_before: String = JSON.stringify(terrain.export_authoritative_snapshot())
	terrain.set_organic_cliff_geometry_enabled(true)
	_expect(terrain.is_organic_cliff_geometry_enabled(),
		"experimental mode is separately selectable")
	_expect(JSON.stringify(terrain.export_authoritative_snapshot()) == snapshot_before,
		"selecting geometry mode does not mutate authoritative state")
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		_expect(terrain.loaded_chunks.has(coord),
			"boundary fixture loads chunk %s" % coord)
		if not terrain.loaded_chunks.has(coord):
			continue
		var chunk = terrain.loaded_chunks[coord]
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		_expect(int(stats.mesh_count) <= 3,
			"chunk %s uses at most one mesh per elevation" % coord)
		_expect(int(stats.face_count) > 0,
			"chunk %s contains batched faces" % coord)
		for layer in chunk.cliff_layers:
			if layer != null:
				_expect(not layer.visible,
					"legacy face layer is hidden only while experimental mode is active")

	var edited_chunk = terrain.loaded_chunks[Vector2i(1, 0)]
	var mesh_before_id: int = edited_chunk.organic_cliff_mesh_layers[2].mesh.get_instance_id()
	var edits: Array[Dictionary] = [{
		"cell": Vector2i(38, 5), "kind": "elevation",
		"state": {"has_override": true, "value": 0},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	await _wait_until_idle()
	var mesh_after_id: int = edited_chunk.organic_cliff_mesh_layers[2].mesh.get_instance_id()
	_expect(changed == 1, "editing fixture applies one authoritative change")
	_expect(mesh_after_id != mesh_before_id,
		"editing rebuilds the affected chunk-batched geometry")

	terrain.set_organic_cliff_geometry_enabled(false)
	_expect(not terrain.is_organic_cliff_geometry_enabled(),
		"legacy mode is restored immediately")
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		if not terrain.loaded_chunks.has(coord):
			continue
		var chunk = terrain.loaded_chunks[coord]
		for layer in chunk.cliff_layers:
			if layer != null:
				_expect(layer.visible, "rollback restores legacy face layers")


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1B validation streaming did not become idle")


func _boundary_y_values(mesh: ArrayMesh, local_x: int) -> Array[int]:
	var values: Array[int] = []
	var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		if roundi(vertex.x) == local_x:
			var y: int = roundi(vertex.y)
			if not values.has(y):
				values.append(y)
	values.sort()
	return values


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
