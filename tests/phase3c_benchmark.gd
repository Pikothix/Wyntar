extends "res://tests/phase1g_benchmark.gd"
## Phase 3C steady rendering and incremental rebuild check using the exact
## Phase 1G dense fixture used by the accepted Phase 3B.1 measurement.

const OUTPUT_PATH := "res://.artifacts/phase3c_benchmark_graphical.json"
const RUN_COUNT := 5
const FRAMES_PER_RUN := 240


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
	await _wait_frames(180)

	var frame_samples: Array[float] = []
	var run_means: Array[float] = []
	var draw_calls: float = 0.0
	var primitives: float = 0.0
	for _run_index in range(RUN_COUNT):
		var run_samples: Array[float] = []
		for _frame in range(FRAMES_PER_RUN):
			var started := Time.get_ticks_usec()
			await process_frame
			var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
			run_samples.append(elapsed)
			frame_samples.append(elapsed)
			draw_calls += Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives += Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		run_means.append(float(_phase3c_summarize(run_samples).mean_frame_ms))

	var stream_runs: Array[Dictionary] = []
	for _run_index in range(3):
		terrain.reset_incremental_cliff_scheduler_metrics()
		terrain._invalidate_streamed_chunks()
		demo._update_visible_world_region()
		var geometry_cpu_ms: float = 0.0
		var chunk_cpu_ms: float = 0.0
		var frames: int = 0
		for _frame in range(3000):
			await process_frame
			frames += 1
			geometry_cpu_ms += float(
				terrain.organic_geometry_processing_usec_this_frame) / 1000.0
			chunk_cpu_ms += float(terrain.chunk_processing_usec_this_frame) / 1000.0
			if _is_ready() and terrain.get_pending_chunk_retirement_count() == 0:
				break
		stream_runs.append({
			"frames": frames,
			"geometry_cpu_ms": geometry_cpu_ms,
			"chunk_cpu_ms": chunk_cpu_ms,
		})

	var summary: Dictionary = _phase3c_summarize(frame_samples)
	var frame_count: int = RUN_COUNT * FRAMES_PER_RUN
	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact",
		"viewport": [1280, 720],
		"warmup_frames": 180,
		"runs": RUN_COUNT,
		"frames_per_run": FRAMES_PER_RUN,
		"run_mean_ms": run_means,
		"steady": {
			"mean_frame_ms": summary.mean_frame_ms,
			"median_frame_ms": summary.median_frame_ms,
			"p95_frame_ms": summary.p95_frame_ms,
			"worst_frame_ms": summary.worst_frame_ms,
			"average_draw_calls": draw_calls / frame_count,
			"average_primitives": primitives / frame_count,
		},
		"stream_runs": stream_runs,
		"mean_geometry_cpu_ms": _mean_stream_value(stream_runs, "geometry_cpu_ms"),
		"mean_chunk_cpu_ms": _mean_stream_value(stream_runs, "chunk_cpu_ms"),
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 3C benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE3C_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)


func _mean_stream_value(runs: Array[Dictionary], key: String) -> float:
	var total: float = 0.0
	for run in runs:
		total += float(run[key])
	return total / runs.size()


func _phase3c_summarize(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value in sorted:
		total += value
	return {
		"mean_frame_ms": total / sorted.size(),
		"median_frame_ms": _percentile(sorted, 0.5),
		"p95_frame_ms": _percentile(sorted, 0.95),
		"worst_frame_ms": sorted[-1],
	}
