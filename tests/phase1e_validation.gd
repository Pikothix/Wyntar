extends SceneTree
## Phase 1E validates the refined top-down return ribbon, bounded halo sampling,
## seam continuity, rollback, and edit-driven chunk-batch replacement.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_refined_geometry()
	_test_horizontal_chunk_seam()
	_test_negative_chunk_seam()
	await _test_runtime_selection_and_editing()
	if failures.is_empty():
		print("PHASE1E_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1E_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_refined_geometry() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(4, 12):
		for x in range(25, 40):
			heights[Vector2i(x, y)] = 3
			materials[Vector2i(x, y)] = 4 if x < 34 else 2
	for y in range(6, 9):
		for x in range(30, 34):
			heights[Vector2i(x, y)] = 0
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var phase1d: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup,
		{0: true}, true, false)
	var first: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup,
		{0: true}, true, true)
	var second: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup,
		{0: true}, true, true)
	_expect(int(first.edge_component_count) == int(phase1d.edge_component_count),
		"refinement preserves classified cliff components")
	_expect(int(first.vertex_count) < int(phase1d.vertex_count),
		"refined ribbons reduce duplicated vertices")
	_expect(int(first.triangle_count) < int(phase1d.triangle_count),
		"refined ribbons remove unnecessary return subdivisions")
	_expect(int(first.height_query_count) == 34 * 34
		and int(first.material_query_count) == 34 * 34,
		"one bounded halo supplies all chunk geometry queries")
	_expect(int(first.vertex_count) == int(second.vertex_count)
		and int(first.triangle_count) == int(second.triangle_count),
		"refined builds have deterministic geometry counts")
	var first_edges: ArrayMesh = first.edge_meshes[2]
	var second_edges: ArrayMesh = second.edge_meshes[2]
	_expect(first_edges != null and second_edges != null,
		"fixture produces refined height-three edge batches")
	if first_edges != null and second_edges != null:
		_expect(hash(first_edges.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			== hash(second_edges.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
			"refined return vertices are byte-identical across repeated builds")


func _test_horizontal_chunk_seam() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	# A west-facing formation continues through the y=32 chunk boundary.
	for y in range(25, 40):
		for x in range(4, 11):
			heights[Vector2i(x, y)] = 3
			materials[Vector2i(x, y)] = 2
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var north: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(0, 0), 3, 84521, world_lookup, height_lookup,
		{0: true}, true, true)
	var south: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(0, 1), 3, 84521, world_lookup, height_lookup,
		{0: true}, true, true)
	var north_edges: ArrayMesh = north.edge_meshes[2]
	var south_edges: ArrayMesh = south.edge_meshes[2]
	_expect(north_edges != null and south_edges != null,
		"both y-neighbour chunks own continuing return batches")
	if north_edges != null and south_edges != null:
		_expect(_boundary_x_values(north_edges, 32 * 32 - 3 * 16)
			== _boundary_x_values(south_edges, -3 * 16),
			"east/west returns share exact vertices across a y chunk seam")


func _test_negative_chunk_seam() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(-39, -24):
		for x in range(-11, -4):
			heights[Vector2i(x, y)] = 2
			materials[Vector2i(x, y)] = 4
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var north: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(-1, -2), 3, 84521, world_lookup, height_lookup,
		{0: true}, true, true)
	var south: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(-1, -1), 3, 84521, world_lookup, height_lookup,
		{0: true}, true, true)
	var north_edges: ArrayMesh = north.edge_meshes[1]
	var south_edges: ArrayMesh = south.edge_meshes[1]
	_expect(north_edges != null and south_edges != null,
		"negative y-boundary fixture creates both batches")
	if north_edges != null and south_edges != null:
		_expect(_boundary_x_values(north_edges, 32 * 32 - 2 * 16)
			== _boundary_x_values(south_edges, -2 * 16),
			"refined returns share exact vertices across a negative chunk seam")


func _test_runtime_selection_and_editing() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	for y in range(2, 12):
		for x in range(24, 41):
			terrain.world.set_override(Vector2i(x, y), 2)
			terrain.world.set_elevation_override(Vector2i(x, y), 3)
	terrain._invalidate_streamed_chunks()
	demo.camera.position = Vector2(Vector2i(32, 8) * terrain.TILE_SIZE)
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	var terrain_authority_before: String = JSON.stringify(
		terrain.export_authoritative_snapshot().terrain)
	_expect(terrain.is_refined_cliff_silhouettes_enabled(),
		"main scene enables Phase 1E by default")
	var chunk = terrain.loaded_chunks[Vector2i(1, 0)]
	var refined_mesh_id: int = chunk.organic_cliff_edge_mesh_layers[2].mesh.get_instance_id()
	terrain.set_refined_cliff_silhouettes_enabled(false)
	await _wait_until_idle()
	_expect(not terrain.is_refined_cliff_silhouettes_enabled(),
		"original Phase 1D geometry remains an available rollback")
	var phase1d_mesh_id: int = chunk.organic_cliff_edge_mesh_layers[2].mesh.get_instance_id()
	_expect(phase1d_mesh_id != refined_mesh_id,
		"rollback replaces only the presentation batch")
	terrain.set_refined_cliff_silhouettes_enabled(true)
	await _wait_until_idle()
	_expect(JSON.stringify(terrain.export_authoritative_snapshot().terrain) == terrain_authority_before,
		"silhouette selection does not mutate authoritative terrain")
	var before_edit_id: int = chunk.organic_cliff_edge_mesh_layers[2].mesh.get_instance_id()
	var edits: Array[Dictionary] = [{
		"cell": Vector2i(38, 6), "kind": "elevation",
		"state": {"has_override": true, "value": 0},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	await _wait_until_idle()
	var after_edit_id: int = chunk.organic_cliff_edge_mesh_layers[2].mesh.get_instance_id()
	_expect(changed == 1 and after_edit_id != before_edit_id,
		"terrain editing rebuilds the affected refined batch")
	for layer in chunk.cliff_edge_layers:
		if layer != null:
			_expect(not layer.visible, "legacy edge art remains hidden in Phase 1E")
	for layer in chunk.cliff_shadow_layers:
		if layer != null:
			_expect(not layer.visible, "legacy rectangular shadows remain hidden")


func _boundary_x_values(mesh: ArrayMesh, local_y: int) -> Array[int]:
	var values: Array[int] = []
	var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		if roundi(vertex.y) == local_y:
			var x: int = roundi(vertex.x)
			if not values.has(x):
				values.append(x)
	values.sort()
	return values


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1E validation streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
