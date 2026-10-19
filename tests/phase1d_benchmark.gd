extends SceneTree
## Reproducible Phase 1B/1D comparison on identical top-down terrain data.

const OUTPUT_PATH := "res://screenshots/phase1d_benchmark.json"
const SAMPLE_FRAMES := 120

var demo
var terrain
var results: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_organic_cliff_geometry_enabled(true)
	_build_fixture(Vector2i(12400, 6200))
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2i(12400, 6200))

	terrain.set_unified_cliff_components_enabled(false)
	await _wait_frames(5)
	results.phase1b = await _sample()
	results.phase1b.geometry = _geometry_totals()
	var toggle_started: int = Time.get_ticks_usec()
	terrain.set_unified_cliff_components_enabled(true)
	results.phase1d_toggle_rebuild_ms = (
		float(Time.get_ticks_usec() - toggle_started) / 1000.0)
	await _wait_frames(5)
	results.phase1d = await _sample()
	results.phase1d.geometry = _geometry_totals()
	results.phase1d_edit = await _sample_edit()

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 1D benchmark result")
		quit(1)
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PHASE1D_BENCHMARK: %s" % JSON.stringify(results))
	quit(0)


func _build_fixture(center: Vector2i) -> void:
	_fill(center - Vector2i(54, 42), Vector2i(108, 84), 3, 0)
	for y in range(-38, 39):
		for x in range(-50, 51):
			var ridge: float = sin(float(x) * 0.28) + cos(float(y) * 0.23)
			var height: int = clampi(floori((ridge + 2.0) * 0.99), 0, 3)
			if height > 0:
				_set_cell(center + Vector2i(x, y), 4 if (x + y) % 4 else 2, height)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _sample() -> Dictionary:
	var values: Array[float] = []
	var draw_total: float = 0.0
	for _frame in range(SAMPLE_FRAMES):
		var started: int = Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	values.sort()
	var total: float = 0.0
	for value in values:
		total += value
	return {
		"average_frame_ms": total / values.size(),
		"p95_frame_ms": _percentile(values, 0.95),
		"p99_frame_ms": _percentile(values, 0.99),
		"worst_frame_ms": values[-1],
		"average_draw_calls": draw_total / values.size(),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


func _geometry_totals() -> Dictionary:
	var totals := {
		"build_ms": 0.0, "face_meshes": 0, "edge_meshes": 0,
		"shadow_meshes": 0, "faces": 0, "edge_components": 0,
		"shadows": 0, "vertices": 0, "triangles": 0,
	}
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		totals.build_ms += float(stats.build_usec) / 1000.0
		totals.face_meshes += int(stats.mesh_count)
		totals.edge_meshes += int(stats.edge_mesh_count)
		totals.shadow_meshes += int(stats.shadow_mesh_count)
		totals.faces += int(stats.face_count)
		totals.edge_components += int(stats.edge_component_count)
		totals.shadows += int(stats.shadow_count)
		totals.vertices += int(stats.vertex_count)
		totals.triangles += int(stats.triangle_count)
	return totals


func _sample_edit() -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var edits: Array[Dictionary] = [{
		"cell": Vector2i(12400, 6200), "kind": "elevation",
		"state": {"has_override": true, "value": 0},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	await _wait_until_idle()
	return {
		"changed": changed,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"dirty_chunks": terrain.last_edit_dirty_chunk_count,
		"refresh_ms": float(terrain.last_edit_refresh_usec) / 1000.0,
	}


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1D benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]
