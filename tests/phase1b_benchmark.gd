extends SceneTree
## Phase 1B compares retained Phase 1A geometry with the experimental
## chunk-batched mesh under static, streaming, and editing workloads.

const SAMPLE_FRAMES := 180
const WARMUP_FRAMES := 30

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_dense_fixture(Vector2i(10200, 5100))
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2i(10200, 5100))

	await _sample_mode("phase1a_static", false, false)
	await _sample_mode("phase1b_static", true, false)
	_print_geometry_totals()
	await _move_camera(Vector2i(10200, 5100))
	await _sample_mode("phase1a_streaming", false, true)
	await _move_camera(Vector2i(10200, 5100))
	await _sample_mode("phase1b_streaming", true, true)
	await _sample_editing()
	print("PHASE1B_BENCHMARK: PASS")
	quit(0)


func _build_dense_fixture(center: Vector2i) -> void:
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


func _sample_mode(label: String, organic: bool, streaming: bool) -> void:
	var toggle_started: int = Time.get_ticks_usec()
	terrain.set_organic_cliff_geometry_enabled(organic)
	var toggle_ms: float = float(Time.get_ticks_usec() - toggle_started) / 1000.0
	await _wait_frames(WARMUP_FRAMES)
	var values: Array[float] = []
	var draw_total: float = 0.0
	var previous: int = Time.get_ticks_usec()
	for _frame in range(SAMPLE_FRAMES):
		if streaming:
			demo.camera.position += Vector2(22.0, 7.0)
			demo.camera.force_update_scroll()
			demo._update_visible_world_region()
		await process_frame
		var now: int = Time.get_ticks_usec()
		values.append(float(now - previous) / 1000.0)
		previous = now
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	values.sort()
	var total: float = 0.0
	for value in values:
		total += value
	print("PHASE1B_MODE mode=%s toggle_ms=%.3f avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f avg_draw_calls=%.1f memory_mib=%.2f" % [
		label, toggle_ms, total / values.size(), _percentile(values, 0.95),
		_percentile(values, 0.99), values[-1], draw_total / values.size(),
		Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)])


func _sample_editing() -> void:
	await _move_camera(Vector2i(10200, 5100))
	terrain.set_organic_cliff_geometry_enabled(true)
	var started: int = Time.get_ticks_usec()
	var edits: Array[Dictionary] = [{
		"cell": Vector2i(10200, 5100), "kind": "elevation",
		"state": {"has_override": true, "value": 3},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	await _wait_until_idle()
	print("PHASE1B_EDIT changed=%d elapsed_ms=%.3f dirty_chunks=%d refresh_ms=%.3f" % [
		changed, float(Time.get_ticks_usec() - started) / 1000.0,
		terrain.last_edit_dirty_chunk_count,
		float(terrain.last_edit_refresh_usec) / 1000.0])


func _print_geometry_totals() -> void:
	var build_usec: int = 0
	var meshes: int = 0
	var faces: int = 0
	var vertices: int = 0
	var triangles: int = 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		build_usec += int(stats.build_usec)
		meshes += int(stats.mesh_count)
		faces += int(stats.face_count)
		vertices += int(stats.vertex_count)
		triangles += int(stats.triangle_count)
	print("PHASE1B_GEOMETRY chunks=%d build_ms=%.3f meshes=%d faces=%d vertices=%d triangles=%d" % [
		terrain.loaded_chunks.size(), float(build_usec) / 1000.0,
		meshes, faces, vertices, triangles])


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	await _wait_frames(3)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1B benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]
