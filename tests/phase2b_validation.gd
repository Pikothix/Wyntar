extends SceneTree
## Phase 2B validation for coherent refined profiles, unchanged mesh topology,
## presentation-only toggling, projected picking, edits, and Phase 2A rollback.

const ObliqueProjection = preload("res://scripts/oblique_projection.gd")
const ObliqueTerrainMeshBuilder = preload("res://scripts/oblique_terrain_mesh_builder.gd")

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_refined_profiles()
	_test_builder_determinism_and_cost_shape()
	await _test_main_scene_integration()
	if failures.is_empty():
		print("PHASE2B_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE2B_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_refined_profiles() -> void:
	for boundary in [-64, -32, 0, 32, 64]:
		var west := Vector2i(boundary - 1, -7)
		var east := Vector2i(boundary, -7)
		var west_edge := ObliqueProjection.edge_points(
			west, ObliqueProjection.EAST, 3, 84521, true)
		var east_edge := ObliqueProjection.edge_points(
			east, ObliqueProjection.WEST, 3, 84521, true)
		_expect(_point_set(west_edge) == _point_set(east_edge),
			"refined owners share exact edge points at x=%d" % boundary)

	var offsets: Array[int] = []
	for x in range(-48, 49):
		var edge := ObliqueProjection.edge_points(
			Vector2i(x, 5), ObliqueProjection.NORTH, 2, 84521, true)
		var linear_midpoint: Vector2 = (edge[0] + edge[2]) * 0.5
		offsets.append(roundi(edge[1].y - linear_midpoint.y))
	var transitions := 0
	for index in range(1, offsets.size()):
		if offsets[index] != offsets[index - 1]:
			transitions += 1
	_expect(transitions > 0, "refined profile retains visible variation")
	_expect(transitions < offsets.size() * 3 / 4,
		"refined offsets form coherent runs instead of cell-by-cell sawteeth")

	var negative := ObliqueProjection.cell_polygon(Vector2i(-33, -32), 2, 84521, true)
	var repeated := ObliqueProjection.cell_polygon(Vector2i(-33, -32), 2, 84521, true)
	_expect(hash(negative) == hash(repeated),
		"refined negative-coordinate geometry is deterministic")
	for point in negative:
		_expect(point == point.round(), "refined vertices remain pixel-quantised")


func _test_builder_determinism_and_cost_shape() -> void:
	var height_lookup := func(cell: Vector2i) -> int:
		if cell.y < 4 and cell.x >= -8 and cell.x < 40:
			return 3 if cell.y < -3 else 2
		return 0
	var material_lookup := func(cell: Vector2i) -> int:
		return 4 if cell.x < 18 else 2
	var phase2a: Dictionary = ObliqueTerrainMeshBuilder.build(
		Vector2i.ZERO, 84521, material_lookup, height_lookup, {0: true}, false)
	var first: Dictionary = ObliqueTerrainMeshBuilder.build(
		Vector2i.ZERO, 84521, material_lookup, height_lookup, {0: true}, true)
	var second: Dictionary = ObliqueTerrainMeshBuilder.build(
		Vector2i.ZERO, 84521, material_lookup, height_lookup, {0: true}, true)
	_expect(int(first.vertex_count) == int(phase2a.vertex_count)
		and int(first.triangle_count) == int(phase2a.triangle_count),
		"refinement changes positions without growing Phase 2A topology")
	_expect(int(first.vertex_count) == int(second.vertex_count),
		"refined geometry counts are deterministic")
	var first_mesh: ArrayMesh = first.mesh
	var second_mesh: ArrayMesh = second.mesh
	_expect(hash(first_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		== hash(second_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]),
		"identical seeds produce identical refined vertices")


func _test_main_scene_integration() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	_expect(not terrain.is_oblique_presentation_enabled(),
		"Phase 2A remains disabled by default")
	_expect(not terrain.is_organic_oblique_refinement_enabled(),
		"Phase 2B remains disabled by default")
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	terrain.set_oblique_presentation_enabled(true)
	await _move_camera(Vector2i(16, 2))

	var terrain_snapshot := JSON.stringify(terrain.world.export_override_snapshot())
	var target := Vector2i(12, 0)
	var chunk_coord: Vector2i = terrain.world_cell_to_chunk(target)
	var mesh_layer: MeshInstance2D = terrain.oblique_renderer.chunk_meshes[chunk_coord]
	var phase2a_mesh_id := mesh_layer.mesh.get_instance_id()
	var phase2a_polygon: PackedVector2Array = terrain.get_projected_cell_polygon(target)

	terrain.set_organic_oblique_refinement_enabled(true)
	await _wait_frames(3)
	_expect(terrain.is_organic_oblique_refinement_enabled(),
		"Phase 2B is independently selectable")
	_expect(mesh_layer.mesh.get_instance_id() != phase2a_mesh_id,
		"enabling Phase 2B rebuilds retained oblique chunks")
	_expect(JSON.stringify(terrain.world.export_override_snapshot()) == terrain_snapshot,
		"Phase 2B toggle does not mutate authoritative terrain")

	var polygon: PackedVector2Array = terrain.get_projected_cell_polygon(target)
	_expect(hash(polygon) != hash(phase2a_polygon),
		"refinement changes the presented cell silhouette")
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	center /= float(polygon.size())
	var pick: Dictionary = terrain.pick_world_position(center)
	_expect(pick.cell == target, "refined projected picking resolves the logical cell")

	var before_edit_id := mesh_layer.mesh.get_instance_id()
	var edits: Array[Dictionary] = [{
		"cell": target, "kind": "elevation",
		"state": {"has_override": true, "value": 1},
	}]
	_expect(terrain.apply_world_edit_states(edits) == 1,
		"editing applies while Phase 2B is active")
	await _wait_until_idle()
	_expect(mesh_layer.mesh.get_instance_id() != before_edit_id,
		"editing rebuilds refined geometry")

	terrain.set_organic_oblique_refinement_enabled(false)
	await _wait_frames(3)
	_expect(not terrain.is_organic_oblique_refinement_enabled(),
		"Phase 2A rollback remains immediate")
	_expect(terrain.is_oblique_presentation_enabled(),
		"Phase 2B rollback does not disable Phase 2A")


func _build_fixture() -> void:
	for y in range(-18, 19):
		for x in range(-8, 41):
			var material_id := 3
			var elevation := 0
			if y < 8 and x >= 0 and x < 32:
				material_id = 4 if x < 17 else 2
				elevation = 3 if y < 0 else 2
			terrain.world.set_override(Vector2i(x, y), material_id)
			terrain.world.set_elevation_override(Vector2i(x, y), elevation)


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = ObliqueProjection.project_cell_center(
		cell, terrain.get_world_surface_elevation(cell))
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
	assert(false, "Phase 2B validation streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
