extends "res://tests/phase1g_benchmark.gd"
## Reuses the exact Phase 1G fixture and sampling sequence, but preserves the
## Phase 1G evidence by writing Phase 3B-specific output paths.

const PHASE3B_OUTPUT_PATH_HEADLESS := "res://.artifacts/phase3b_benchmark_headless.json"
const PHASE3B_OUTPUT_PATH_GRAPHICAL := "res://.artifacts/phase3b_benchmark_graphical.json"


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
		"comparison_fixture": "phase1g_exact",
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
	var output_path: String = (PHASE3B_OUTPUT_PATH_HEADLESS
		if DisplayServer.get_name() == "headless" else PHASE3B_OUTPUT_PATH_GRAPHICAL)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 3B benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE3B_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)
