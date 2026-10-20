extends SceneTree
## Phase A paired benchmark. Baseline and enhanced modes share one scene,
## fixture, camera path, and material count; only the shader toggle changes.

const SAMPLE_FRAMES := 180
const WARMUP_FRAMES := 30

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
	await _wait_frames(6)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2i(2048, 2048))
	results.baseline = await _sample_mode(false)
	await _move_camera(Vector2i(2048, 2048))
	results.enhanced = await _sample_mode(true)
	results.comparison = _compare(results.baseline, results.enhanced)
	var path := "res://.artifacts/phase_a_water_benchmark.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not write %s" % path)
	file.store_string(JSON.stringify(results, "\t"))
	print("PHASE_A_WATER_BENCHMARK baseline=%s" % JSON.stringify(results.baseline))
	print("PHASE_A_WATER_BENCHMARK enhanced=%s" % JSON.stringify(results.enhanced))
	print("PHASE_A_WATER_BENCHMARK comparison=%s" % JSON.stringify(results.comparison))
	print("PHASE_A_WATER_BENCHMARK: PASS path=%s" % path)
	quit(0)


func _sample_mode(enabled: bool) -> Dictionary:
	terrain.set_experimental_water_enhancement_enabled(enabled)
	terrain.set_water_enhancement_controls(0.32, 2.4, 0.55, 0.14, 0.38)
	await _wait_frames(WARMUP_FRAMES)
	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var previous_usec: int = Time.get_ticks_usec()
	for _frame in range(SAMPLE_FRAMES):
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		frame_ms.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		draw_calls.append(float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	frame_ms.sort()
	process_ms.sort()
	draw_calls.sort()
	return {
		"frames": SAMPLE_FRAMES,
		"mean_frame_ms": _mean(frame_ms),
		"p95_frame_ms": _percentile(frame_ms, 0.95),
		"worst_frame_ms": frame_ms[-1],
		"mean_process_cpu_ms": _mean(process_ms),
		"p95_process_cpu_ms": _percentile(process_ms, 0.95),
		"gpu_frame_time_ms": null,
		"mean_draw_calls": _mean(draw_calls),
		"material_count": terrain.visual_material_by_id.size(),
		"loaded_chunks": terrain.loaded_chunks.size(),
		"pending_chunks": terrain.get_pending_chunk_count(),
		"streaming_cpu_ms_this_frame": float(
			terrain.chunk_processing_usec_this_frame) / 1000.0,
	}


func _compare(baseline: Dictionary, enhanced: Dictionary) -> Dictionary:
	return {
		"mean_frame_regression_percent": _percent_change(
			float(baseline.mean_frame_ms), float(enhanced.mean_frame_ms)),
		"p95_frame_regression_percent": _percent_change(
			float(baseline.p95_frame_ms), float(enhanced.p95_frame_ms)),
		"worst_frame_regression_percent": _percent_change(
			float(baseline.worst_frame_ms), float(enhanced.worst_frame_ms)),
		"gpu_measurement_reliable": false,
		"draw_call_delta": float(enhanced.mean_draw_calls) - float(baseline.mean_draw_calls),
		"material_count_delta": int(enhanced.material_count) - int(baseline.material_count),
	}


func _build_fixture() -> void:
	var center := Vector2i(2048, 2048)
	for y in range(center.y - 56, center.y + 56):
		for x in range(center.x - 88, center.x + 88):
			var edge: float = Vector2(x - center.x, y - center.y).length()
			var water: bool = edge < 70.0 + sin(float(y) * 0.23) * 5.0
			terrain.world.set_override(Vector2i(x, y), 0 if water else 1)
			terrain.world.set_elevation_override(Vector2i(x, y), 2 if water else 0)


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
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase A benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]


func _percent_change(baseline: float, enhanced: float) -> float:
	return 0.0 if baseline <= 0.0 else (enhanced - baseline) / baseline * 100.0
