extends SceneTree
## Phase 1A A/B benchmark. Both modes render the same loaded chunks; only the
## shared cliff material rollback flag changes.

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
	_build_dense_fixture(Vector2i(8200, 4100))
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2i(8200, 4100))

	await _sample_mode("legacy_static", false, false)
	await _sample_mode("procedural_static", true, false)
	await _move_camera(Vector2i(8200, 4100))
	await _sample_mode("legacy_streaming", false, true)
	await _move_camera(Vector2i(8200, 4100))
	await _sample_mode("procedural_streaming", true, true)
	print("PHASE1A_BENCHMARK: PASS")
	quit(0)


func _build_dense_fixture(center: Vector2i) -> void:
	_fill(center - Vector2i(52, 40), Vector2i(104, 80), 3, 0)
	for y in range(-36, 37):
		for x in range(-48, 49):
			var ridge: float = sin(float(x) * 0.31) + cos(float(y) * 0.27)
			var height: int = clampi(floori((ridge + 2.0) * 0.99), 0, 3)
			if height > 0:
				_set_cell(center + Vector2i(x, y), 4 if (x + y) % 3 else 2, height)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _sample_mode(label: String, procedural: bool, streaming: bool) -> void:
	terrain.set_procedural_cliff_materials_enabled(procedural)
	await _wait_frames(WARMUP_FRAMES)
	var values: Array[float] = []
	var draw_total: float = 0.0
	var previous: int = Time.get_ticks_usec()
	for frame in range(SAMPLE_FRAMES):
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
	print("PHASE1A_MODE mode=%s avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f avg_draw_calls=%.1f memory_mib=%.2f" % [
		label, total / values.size(), _percentile(values, 0.95),
		_percentile(values, 0.99), values[-1], draw_total / values.size(),
		Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)])


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
	assert(false, "Phase 1A benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]
