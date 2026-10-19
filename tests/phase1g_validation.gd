extends SceneTree
## Phase 1G validates bounded retirement, bounded halo reuse, edit
## invalidation, atomic replacement and pending mode-change cancellation.

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	var center := Vector2i(10200, 5100)
	_build_fixture(center)
	await _move_camera(center)

	var loaded_count: int = terrain.loaded_chunks.size()
	_expect(terrain._organic_halo_cache.size() == loaded_count,
		"Halo snapshots must be bounded to loaded chunks")
	terrain.set_refined_cliff_silhouettes_enabled(false)
	await _wait_until_ready()
	_expect(_query_total() == 0,
		"Presentation-only mode changes must reuse unchanged halo snapshots")

	var edited_chunk: Vector2i = terrain.world_cell_to_chunk(center)
	var old_mesh_id: int = _first_mesh_id(terrain.loaded_chunks[edited_chunk])
	terrain.set_world_elevation(center, 0)
	_expect(_first_mesh_id(terrain.loaded_chunks[edited_chunk]) == old_mesh_id,
		"A pending edit must preserve the previous complete mesh")
	# Supersede the edit job while it is pending. The final revision must win.
	terrain.set_refined_cliff_silhouettes_enabled(true)
	await _wait_until_ready()
	_expect(_query_total() > 0,
		"An edited terrain revision must not reuse its stale halo snapshot")
	_expect(terrain.get_pending_chunk_count() == 0,
		"Superseded organic jobs must be cancelled cleanly")

	var old_chunks: Array = terrain.loaded_chunks.values()
	terrain._invalidate_streamed_chunks()
	_expect(terrain.get_pending_chunk_retirement_count() == old_chunks.size(),
		"Invalidation must enqueue every old chunk for retirement")
	for chunk in old_chunks:
		_expect(not chunk.visible, "Retiring chunks must be hidden immediately")
	await process_frame
	_expect(terrain.get_pending_chunk_retirement_count() == old_chunks.size(),
		"A retirement quantum must not recursively release a whole populated chunk")
	await _wait_until_ready()
	await _wait_for_retirements()
	_expect(terrain._organic_halo_cache.size() == terrain.loaded_chunks.size(),
		"Replacement halos must not retain unloaded chunk entries")

	if failures.is_empty():
		print("PHASE1G_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1G_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _query_total() -> int:
	var total: int = 0
	for chunk in terrain.loaded_chunks.values():
		total += int(chunk.get_organic_cliff_geometry_stats().height_query_count)
	return total


func _first_mesh_id(chunk) -> int:
	for layer in chunk.organic_cliff_mesh_layers:
		if layer != null and layer.mesh != null:
			return layer.mesh.get_instance_id()
	return 0


func _build_fixture(center: Vector2i) -> void:
	for y in range(-38, 39):
		for x in range(-50, 51):
			var pos: Vector2i = center + Vector2i(x, y)
			var ridge: float = sin(float(x) * 0.28) + cos(float(y) * 0.23)
			var height: int = clampi(floori((ridge + 2.0) * 0.99), 0, 3)
			terrain.world.set_override(pos, 4 if (x + y) % 4 else 2)
			terrain.world.set_elevation_override(pos, height)


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_ready()
	await _wait_for_retirements()


func _wait_until_ready(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1G validation did not become ready")


func _wait_for_retirements(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		if terrain.get_pending_chunk_retirement_count() == 0:
			return
		await process_frame
	assert(false, "Phase 1G validation retirements did not drain")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
