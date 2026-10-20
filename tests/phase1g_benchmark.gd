extends SceneTree
## Repeated Phase 1G streaming, retirement, mode-switch and edit benchmark.

const OUTPUT_PATH_HEADLESS := "res://.artifacts/phase1g_benchmark_headless.json"
const OUTPUT_PATH_GRAPHICAL := "res://.artifacts/phase1g_benchmark_graphical.json"

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

	# Same runtime, fixture and stream sequence with Phase 1F-style recursive
	# chunk release. This gives a paired baseline without engine/version drift.
	terrain.incremental_chunk_retirement_enabled = false
	terrain.max_chunk_retirements_per_frame = 100000
	var baseline_streams: Array[Dictionary] = []
	for _run_index in range(3):
		terrain.reset_incremental_cliff_scheduler_metrics()
		terrain._invalidate_streamed_chunks()
		demo._update_visible_world_region()
		baseline_streams.append(await _sample_until_settled())
	terrain.incremental_chunk_retirement_enabled = true
	terrain.max_chunk_retirements_per_frame = 1

	var streams: Array[Dictionary] = []
	for _run_index in range(3):
		terrain.reset_incremental_cliff_scheduler_metrics()
		terrain._invalidate_streamed_chunks()
		demo._update_visible_world_region()
		streams.append(await _sample_until_settled())

	var baseline_mode_switches: Array[Dictionary] = []
	for _run_index in range(3):
		terrain.set_refined_cliff_silhouettes_enabled(false)
		await _wait_until_ready()
		terrain._organic_halo_cache.clear()
		terrain.reset_incremental_cliff_scheduler_metrics()
		var started: int = Time.get_ticks_usec()
		terrain.set_refined_cliff_silhouettes_enabled(true)
		var sample: Dictionary = await _sample_until_ready()
		sample.wall_ms = float(Time.get_ticks_usec() - started) / 1000.0
		sample.additional_halo_queries = _organic_query_total()
		baseline_mode_switches.append(sample)

	var mode_switches: Array[Dictionary] = []
	for _run_index in range(3):
		terrain.set_refined_cliff_silhouettes_enabled(false)
		await _wait_until_ready()
		terrain.reset_incremental_cliff_scheduler_metrics()
		var started: int = Time.get_ticks_usec()
		terrain.set_refined_cliff_silhouettes_enabled(true)
		var sample: Dictionary = await _sample_until_ready()
		sample.wall_ms = float(Time.get_ticks_usec() - started) / 1000.0
		sample.additional_halo_queries = _organic_query_total()
		mode_switches.append(sample)

	var rapid_frames: Array[float] = []
	var rapid_centers: Array[Vector2i] = [
		center + Vector2i(160, 0), center - Vector2i(160, 0),
		center + Vector2i(0, 160), center - Vector2i(0, 160), center,
	]
	terrain.reset_incremental_cliff_scheduler_metrics()
	for target in rapid_centers:
		_set_camera(target)
		for _frame in range(2):
			var frame_started: int = Time.get_ticks_usec()
			await process_frame
			rapid_frames.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
	var rapid_tail: Dictionary = await _sample_until_settled()
	var rapid := _summarize(rapid_frames)
	rapid.tail = rapid_tail
	rapid.lifecycle = terrain.get_incremental_cliff_scheduler_metrics()

	await _move_camera(center)
	var edit_frames: Array[float] = []
	for edit_index in range(8):
		var cell: Vector2i = center + Vector2i(edit_index % 4, edit_index / 4)
		terrain.set_world_elevation(cell, 0 if edit_index % 2 == 0 else 3)
		var frame_started: int = Time.get_ticks_usec()
		await process_frame
		edit_frames.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
	var edit_tail: Dictionary = await _sample_until_ready()
	var editing := _summarize(edit_frames)
	editing.tail = edit_tail

	await _wait_for_retirements()
	await _wait_frames(30)
	var result := {
		"display_server": DisplayServer.get_name(),
		"paired_baseline_streaming_runs": baseline_streams,
		"paired_baseline_streaming_aggregate": _aggregate(baseline_streams),
		"streaming_runs": streams,
		"streaming_aggregate": _aggregate(streams),
		"paired_baseline_mode_switch_runs": baseline_mode_switches,
		"paired_baseline_mode_switch_aggregate": _aggregate(baseline_mode_switches),
		"mode_switch_runs": mode_switches,
		"mode_switch_aggregate": _aggregate(mode_switches),
		"rapid_camera": rapid,
		"repeated_editing": editing,
		"steady_static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"final_nodes": roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"final_resources": roundi(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}
	var output_path: String = (OUTPUT_PATH_HEADLESS
		if DisplayServer.get_name() == "headless" else OUTPUT_PATH_GRAPHICAL)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 1G benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE1G_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)


func _sample_until_settled(max_frames: int = 3000) -> Dictionary:
	var values: Array[float] = []
	var cpu_total_ms: float = 0.0
	var draw_total: float = 0.0
	var visible_ready_frame: int = -1
	var ready_frame: int = -1
	for frame_index in range(max_frames):
		var started: int = Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		cpu_total_ms += float(terrain.chunk_processing_usec_this_frame) / 1000.0
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		if visible_ready_frame < 0 and terrain.get_pending_visible_chunk_count() == 0:
			visible_ready_frame = frame_index + 1
		if ready_frame < 0 and _is_ready():
			ready_frame = frame_index + 1
		if _is_ready() and terrain.get_pending_chunk_retirement_count() == 0:
			var result: Dictionary = _summarize(values)
			result.visible_ready_frame = visible_ready_frame
			result.replacement_ready_frame = ready_frame
			result.total_cpu_ms = cpu_total_ms
			result.average_draw_calls = draw_total / values.size()
			result.lifecycle = terrain.get_incremental_cliff_scheduler_metrics()
			result.static_memory_mib = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
			return result
	assert(false, "Phase 1G benchmark did not settle")
	return {}


func _sample_until_ready(max_frames: int = 3000) -> Dictionary:
	var values: Array[float] = []
	var cpu_total_ms: float = 0.0
	var draw_total: float = 0.0
	for _frame in range(max_frames):
		var started: int = Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		cpu_total_ms += float(terrain.chunk_processing_usec_this_frame) / 1000.0
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		if _is_ready():
			var result: Dictionary = _summarize(values)
			result.total_cpu_ms = cpu_total_ms
			result.average_draw_calls = draw_total / values.size()
			return result
	assert(false, "Phase 1G benchmark did not become ready")
	return {}


func _summarize(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"frames": 0}
	values.sort()
	var total: float = 0.0
	for value in values:
		total += value
	return {
		"frames": values.size(),
		"average_frame_ms": total / values.size(),
		"p95_frame_ms": _percentile(values, 0.95),
		"p99_frame_ms": _percentile(values, 0.99),
		"worst_frame_ms": values[-1],
	}


func _aggregate(samples: Array[Dictionary]) -> Dictionary:
	var averages: Array[float] = []
	var p95s: Array[float] = []
	var p99s: Array[float] = []
	var worsts: Array[float] = []
	var cpu_total: float = 0.0
	for sample in samples:
		averages.append(float(sample.average_frame_ms))
		p95s.append(float(sample.p95_frame_ms))
		p99s.append(float(sample.p99_frame_ms))
		worsts.append(float(sample.worst_frame_ms))
		cpu_total += float(sample.get("total_cpu_ms", 0.0))
	return {
		"runs": samples.size(),
		"mean_average_frame_ms": _mean(averages),
		"mean_p95_frame_ms": _mean(p95s),
		"mean_p99_frame_ms": _mean(p99s),
		"worst_frame_ms": worsts.max(),
		"mean_total_cpu_ms": cpu_total / samples.size(),
	}


func _organic_query_total() -> int:
	var total: int = 0
	for chunk in terrain.loaded_chunks.values():
		total += int(chunk.get_organic_cliff_geometry_stats().height_query_count)
	return total


func _is_ready() -> bool:
	return (terrain.get_pending_chunk_count() == 0
		and terrain.get_pending_edit_cell_count() == 0
		and terrain.get_pending_edit_environment_chunk_count() == 0)


func _wait_until_ready(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		await process_frame
		if _is_ready():
			return
	assert(false, "Phase 1G wait did not become ready")


func _wait_for_retirements(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		if terrain.get_pending_chunk_retirement_count() == 0:
			return
		await process_frame
	assert(false, "Phase 1G retirements did not drain")


func _move_camera(cell: Vector2i) -> void:
	_set_camera(cell)
	await _wait_until_ready()
	await _wait_for_retirements()


func _set_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()


func _build_fixture(center: Vector2i) -> void:
	for y in range(-42, 42):
		for x in range(-54, 54):
			var pos: Vector2i = center + Vector2i(x, y)
			var ridge: float = sin(float(x) * 0.28) + cos(float(y) * 0.23)
			var height: int = clampi(floori((ridge + 2.0) * 0.99), 0, 3)
			terrain.world.set_override(pos, 4 if (x + y) % 4 else 2)
			terrain.world.set_elevation_override(pos, height)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for value in values:
		total += value
	return total / values.size()
