extends SceneTree
## Phase 2A validation for deterministic oblique projection, chunk-batched
## presentation, picking, edit refresh, overlay isolation, and rollback.

const ObliqueProjection = preload("res://scripts/oblique_projection.gd")
const ObliqueTerrainMeshBuilder = preload("res://scripts/oblique_terrain_mesh_builder.gd")

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_projection_contract()
	_test_mesh_determinism()
	await _test_main_scene_integration()
	if failures.is_empty():
		print("PHASE2A_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE2A_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_projection_contract() -> void:
	for cell in [Vector2i(-65, -33), Vector2i(-1, 0), Vector2i.ZERO,
			Vector2i(31, 32), Vector2i(64, -32)]:
		for elevation in range(4):
			var projected: Vector2 = ObliqueProjection.project_cell_center(cell, elevation)
			var logical: Vector2 = ObliqueProjection.inverse_ground_point(projected, elevation)
			_expect(Vector2i(floori(logical.x), floori(logical.y)) == cell,
				"projection round-trip preserves %s at height %d" % [cell, elevation])
			_expect(projected == projected.round(),
				"projection vertices remain pixel-quantised")

	for boundary in [0, 32, -32]:
		var west := Vector2i(boundary - 1, 7)
		var east := Vector2i(boundary, 7)
		var west_edge := ObliqueProjection.edge_points(
			west, ObliqueProjection.EAST, 2, 84521)
		var east_edge := ObliqueProjection.edge_points(
			east, ObliqueProjection.WEST, 2, 84521)
		_expect(_point_set(west_edge) == _point_set(east_edge),
			"adjacent owners share exact oblique edge points at x=%d" % boundary)


func _test_mesh_determinism() -> void:
	var height_lookup := func(cell: Vector2i) -> int:
		if cell.x < 32 and cell.y >= -8 and cell.y < 12:
			return 3 if cell.y < 3 else 1
		return 0
	var material_lookup := func(cell: Vector2i) -> int:
		return 4 if cell.y < 3 else 2
	var first: Dictionary = ObliqueTerrainMeshBuilder.build(
		Vector2i.ZERO, 84521, material_lookup, height_lookup, {0: true})
	var second: Dictionary = ObliqueTerrainMeshBuilder.build(
		Vector2i.ZERO, 84521, material_lookup, height_lookup, {0: true})
	_expect(int(first.face_count) > 0, "fixture produces exposed oblique faces")
	_expect(int(first.vertex_count) == int(second.vertex_count)
		and int(first.triangle_count) == int(second.triangle_count),
		"repeated oblique builds produce identical geometry counts")
	var first_mesh: ArrayMesh = first.mesh
	var second_mesh: ArrayMesh = second.mesh
	_expect(first_mesh.get_surface_count() == 1,
		"one chunk is submitted as one mesh surface")
	if first_mesh.get_surface_count() == 1 and second_mesh.get_surface_count() == 1:
		_expect(hash(first_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			== hash(second_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
			"repeated oblique builds produce identical vertex positions")
		_expect(hash(first_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])
			== hash(second_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]),
			"repeated oblique builds produce identical topology")


func _test_main_scene_integration() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	_expect(not terrain.is_oblique_presentation_enabled(),
		"Phase 2A remains disabled by default in main.tscn")
	_expect(terrain.is_organic_cliff_geometry_enabled(),
		"Phase 1B remains enabled in the retained renderer")
	_expect(terrain.is_procedural_cliff_materials_enabled(),
		"Phase 1A remains enabled in the retained renderer")
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)

	_build_boundary_fixture()
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2i(16, 4), false)
	var snapshot_before: String = JSON.stringify(terrain.world.export_override_snapshot())

	terrain.set_oblique_presentation_enabled(true)
	await _move_camera(Vector2i(16, 4), true)
	_expect(terrain.is_oblique_presentation_enabled(),
		"experimental oblique mode is separately selectable")
	_expect(terrain.oblique_renderer.visible,
		"oblique mesh root is visible while selected")
	_expect(not terrain.environment_object_renderer.visible,
		"incompatible legacy environmental batches are hidden in oblique mode")
	_expect(JSON.stringify(terrain.world.export_override_snapshot()) == snapshot_before,
		"presentation toggle does not mutate authoritative terrain state")
	var metrics: Dictionary = terrain.get_oblique_metrics()
	_expect(int(metrics.chunk_count) > 0, "loaded chunks produce oblique meshes")
	_expect(int(metrics.vertices) > 0 and int(metrics.triangles) > 0,
		"oblique chunks contain batched geometry")
	for chunk in terrain.loaded_chunks.values():
		_expect(not chunk.visible, "legacy chunk CanvasItems are hidden in oblique mode")

	var target := Vector2i(10, 0)
	var polygon: PackedVector2Array = terrain.get_projected_cell_polygon(target)
	var projected_center := Vector2.ZERO
	for point in polygon:
		projected_center += point
	projected_center /= float(polygon.size())
	var pick: Dictionary = terrain.pick_world_position(projected_center)
	_expect(pick.cell == target,
		"oblique picking resolves the projected top surface to its logical cell")

	var chunk_coord: Vector2i = terrain.world_cell_to_chunk(target)
	var mesh_layer: MeshInstance2D = terrain.oblique_renderer.chunk_meshes[chunk_coord]
	var mesh_before_id: int = mesh_layer.mesh.get_instance_id()
	var edits: Array[Dictionary] = [{
		"cell": target, "kind": "elevation",
		"state": {"has_override": true, "value": 1},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	await _wait_until_idle()
	var mesh_after_id: int = mesh_layer.mesh.get_instance_id()
	_expect(changed == 1, "authoritative edit applies while oblique mode is active")
	_expect(mesh_after_id != mesh_before_id,
		"editing rebuilds the affected oblique chunk mesh")

	terrain.set_oblique_presentation_enabled(false)
	await _move_camera(Vector2i(16, 4), false)
	_expect(not terrain.oblique_renderer.visible,
		"rollback hides the experimental mesh root immediately")
	_expect(terrain.environment_object_renderer.visible,
		"rollback restores the legacy environmental batch root")
	for chunk in terrain.loaded_chunks.values():
		_expect(chunk.visible, "rollback restores legacy terrain chunks")

	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.cliff_edge_layers:
			if layer != null:
				_expect(not layer.visible, "legacy cliff edges have an independent diagnostic toggle")
		for layer in chunk.cliff_shadow_layers:
			if layer != null:
				_expect(not layer.visible, "legacy contact shadows have an independent diagnostic toggle")
	terrain.set_cliff_edge_overlays_visible(true)
	terrain.set_cliff_shadows_visible(true)


func _build_boundary_fixture() -> void:
	for y in range(-18, 19):
		for x in range(-8, 41):
			var material_id := 3
			var elevation := 0
			if y < 8 and x >= 0 and x < 32:
				material_id = 4 if x < 17 else 2
				elevation = 3 if y < 0 else 2
			terrain.world.set_override(Vector2i(x, y), material_id)
			terrain.world.set_elevation_override(Vector2i(x, y), elevation)


func _move_camera(cell: Vector2i, oblique: bool) -> void:
	if oblique:
		demo.camera.position = ObliqueProjection.project_cell_center(
			cell, terrain.get_world_surface_elevation(cell))
	else:
		demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()


func _point_set(points: PackedVector2Array) -> Array[String]:
	var result: Array[String] = []
	for point in points:
		result.append("%d,%d" % [roundi(point.x), roundi(point.y)])
	result.sort()
	return result


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 2A validation streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
