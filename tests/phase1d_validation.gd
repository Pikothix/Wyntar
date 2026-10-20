extends SceneTree
## Phase 1D validates the optional, presentation-only replacement for legacy
## cliff lips, side returns, and contact shadows. TerrainWorld remains the sole
## authority; tests compare only generated mesh batches and layer visibility.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_component_builder()
	await _test_renderer_rollback_and_editing()
	if failures.is_empty():
		print("PHASE1D_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1D_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_component_builder() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(4, 12):
		for x in range(25, 40):
			heights[Vector2i(x, y)] = 3
			materials[Vector2i(x, y)] = 4 if x < 34 else 2
	# A recess exercises internal concave north/east/west boundaries.
	for y in range(6, 9):
		for x in range(30, 34):
			heights[Vector2i(x, y)] = 0
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var legacy: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup, {0: true}, false)
	var first: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup, {0: true}, true)
	var second: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup, {0: true}, true)
	var neighbor: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(1, 0), 3, 84521, world_lookup, height_lookup, {0: true}, true)
	_expect(int(legacy.edge_component_count) == 0 and int(legacy.shadow_count) == 0,
		"Phase 1B mode does not build Phase 1D components")
	_expect(int(first.edge_component_count) > 0,
		"fixture builds northern lips and east/west returns")
	_expect(int(first.shadow_count) > 0,
		"fixture builds contour-following contact shadows")
	_expect(int(first.vertex_count) > int(legacy.vertex_count),
		"unified mode adds genuine polygon geometry")
	_expect(int(first.vertex_count) == int(second.vertex_count)
		and int(first.triangle_count) == int(second.triangle_count),
		"repeated unified builds have deterministic counts")
	var first_edges: ArrayMesh = first.edge_meshes[2]
	var second_edges: ArrayMesh = second.edge_meshes[2]
	_expect(first_edges != null and second_edges != null,
		"height-three edge batch exists")
	if first_edges != null and second_edges != null:
		_expect(hash(first_edges.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			== hash(second_edges.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
			"unified edge vertices are byte-identical across repeated builds")
		var neighbor_edges: ArrayMesh = neighbor.edge_meshes[2]
		_expect(neighbor_edges != null, "adjacent chunk owns continuing edge geometry")
		if neighbor_edges != null:
			_expect(_boundary_y_values(first_edges, 32 * 32)
				== _boundary_y_values(neighbor_edges, 0),
				"north lips share exact vertices across the positive chunk seam")
	var first_shadows: ArrayMesh = first.shadow_meshes[2]
	var neighbor_shadows: ArrayMesh = neighbor.shadow_meshes[2]
	_expect(first_shadows != null and neighbor_shadows != null,
		"both chunk owners build the continuing shadow batch")
	if first_shadows != null and neighbor_shadows != null:
		_expect(_boundary_y_values(first_shadows, 32 * 32)
			== _boundary_y_values(neighbor_shadows, 0),
			"contact shadows share exact vertices across the positive chunk seam")
	_test_negative_chunk_seam()
	_test_material_encoding()


func _test_negative_chunk_seam() -> void:
	var heights: Dictionary = {}
	var materials: Dictionary = {}
	for y in range(4, 12):
		for x in range(-39, -24):
			heights[Vector2i(x, y)] = 2
			materials[Vector2i(x, y)] = 2
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 3))
	var left: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(-2, 0), 3, 84521, world_lookup, height_lookup, {0: true}, true)
	var right: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i(-1, 0), 3, 84521, world_lookup, height_lookup, {0: true}, true)
	var left_edges: ArrayMesh = left.edge_meshes[1]
	var right_edges: ArrayMesh = right.edge_meshes[1]
	_expect(left_edges != null and right_edges != null,
		"negative-boundary fixture creates both edge batches")
	if left_edges != null and right_edges != null:
		_expect(_boundary_y_values(left_edges, 32 * 32)
			== _boundary_y_values(right_edges, 0),
			"north lips share exact vertices across the negative chunk seam")


func _test_material_encoding() -> void:
	var heights := {Vector2i.ZERO: 2}
	var materials := {Vector2i.ZERO: 4}
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var world_lookup := func(pos: Vector2i) -> int: return int(materials.get(pos, 0))
	var shoreline: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, world_lookup, height_lookup, {0: true}, true)
	var edge_mesh: ArrayMesh = shoreline.edge_meshes[1]
	_expect(edge_mesh != null, "shoreline fixture creates an edge batch")
	if edge_mesh != null:
		var colors: PackedColorArray = edge_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var shoreline_stone_encoded: bool = false
		for color in colors:
			if is_equal_approx(color.g, 1.0):
				shoreline_stone_encoded = true
				break
		_expect(shoreline_stone_encoded,
			"shoreline stone components retain their distinct material source")


func _test_renderer_rollback_and_editing() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(5)
	terrain = demo.terrain
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	# Isolate the Phase 1D component path now that main.tscn selects Phase 3E.
	terrain.set_unified_cliff_contours_enabled(false)
	for y in range(2, 12):
		for x in range(24, 41):
			terrain.world.set_override(Vector2i(x, y), 4)
			terrain.world.set_elevation_override(Vector2i(x, y), 3)
	for y in range(5, 8):
		for x in range(29, 34):
			terrain.world.set_elevation_override(Vector2i(x, y), 0)
	terrain._invalidate_streamed_chunks()
	demo.camera.position = Vector2(Vector2i(32, 8) * terrain.TILE_SIZE)
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()

	var authority_before: String = JSON.stringify(terrain.export_authoritative_snapshot())
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	_expect(terrain.is_unified_cliff_components_enabled(),
		"Phase 1D is separately selectable")
	_expect(JSON.stringify(terrain.export_authoritative_snapshot()) == authority_before,
		"selecting Phase 1D does not mutate authoritative terrain")
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		_expect(terrain.loaded_chunks.has(coord), "fixture loads chunk %s" % coord)
		if not terrain.loaded_chunks.has(coord):
			continue
		var chunk = terrain.loaded_chunks[coord]
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		_expect(int(stats.edge_mesh_count) <= 3 and int(stats.shadow_mesh_count) <= 3,
			"chunk %s keeps components batched by elevation" % coord)
		_expect(int(stats.edge_component_count) > 0,
			"chunk %s contains procedural edge components" % coord)
		for layer in chunk.cliff_edge_layers:
			if layer != null:
				_expect(not layer.visible, "legacy cliff edge overlay is hidden")
		for layer in chunk.cliff_shadow_layers:
			if layer != null:
				_expect(not layer.visible, "legacy rectangular shadow is hidden")

	var edited_chunk = terrain.loaded_chunks[Vector2i(1, 0)]
	var edge_mesh_before: int = edited_chunk.organic_cliff_edge_mesh_layers[2].mesh.get_instance_id()
	var edits: Array[Dictionary] = [{
		"cell": Vector2i(38, 6), "kind": "elevation",
		"state": {"has_override": true, "value": 0},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	await _wait_until_idle()
	var edge_mesh_after: int = edited_chunk.organic_cliff_edge_mesh_layers[2].mesh.get_instance_id()
	_expect(changed == 1, "editing applies one authoritative elevation change")
	_expect(edge_mesh_after != edge_mesh_before,
		"editing rebuilds the affected unified edge batch")

	terrain.set_unified_cliff_components_enabled(false)
	_expect(not terrain.is_unified_cliff_components_enabled(),
		"Phase 1B rollback is immediate")
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		if not terrain.loaded_chunks.has(coord):
			continue
		var chunk = terrain.loaded_chunks[coord]
		for layer in chunk.cliff_edge_layers:
			if layer != null:
				_expect(layer.visible, "rollback restores the legacy cliff edge layer")
		for layer in chunk.cliff_shadow_layers:
			if layer != null:
				_expect(layer.visible, "rollback restores the legacy shadow layer")


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


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1D validation streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
