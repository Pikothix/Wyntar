extends "res://tests/phase3e_benchmark.gd"
## Matched graphical benchmark for all Phase 3F height profiles.

const PHASE3F_OUTPUT_PATH := "res://screenshots/phase3f_benchmark_graphical.json"
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")


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
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(true)
	var center := Vector2i(10200, 5100)
	_build_fixture(center)
	await _move_camera(center)
	var baseline: Dictionary = await _measure_phase3f_profile(
		TerrainRenderer.CliffHeightProfile.BASELINE)
	var moderate: Dictionary = await _measure_phase3f_profile(
		TerrainRenderer.CliffHeightProfile.MODERATE)
	var prominent: Dictionary = await _measure_phase3f_profile(
		TerrainRenderer.CliffHeightProfile.PROMINENT)
	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact", "viewport": [1280, 720],
		"baseline": baseline, "moderate": moderate, "prominent": prominent,
	}
	var file := FileAccess.open(PHASE3F_OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 3F benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE3F_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)


func _measure_phase3f_profile(profile: int) -> Dictionary:
	terrain.set_cliff_height_profile(profile)
	await _wait_until_ready()
	await _wait_frames(120)
	var frame_samples: Array[float] = []
	var stream_runs: Array[Dictionary] = []
	for _run_index in range(RUNS):
		for _frame in range(STEADY_FRAMES):
			var started: int = Time.get_ticks_usec()
			await process_frame
			frame_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		terrain.reset_incremental_cliff_scheduler_metrics()
		terrain._invalidate_streamed_chunks()
		demo._update_visible_world_region()
		stream_runs.append(await _sample_until_settled())
	return {
		"profile": profile,
		"height_step": terrain.get_cliff_height_step(),
		"steady": _summarize(frame_samples),
		"streaming_runs": stream_runs,
		"streaming_aggregate": _aggregate(stream_runs),
		"geometry": _geometry_totals(),
	}
