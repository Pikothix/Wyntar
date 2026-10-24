extends "res://tests/phase_c4f_grid_cliff_benchmark.gd"
## Matched dense-fixture cost comparison for all C4G renderer modes.

const C4G_OUTPUT_PATH := "res://.artifacts/c4g_cliff_renderer_benchmark.json"


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
	terrain.set_water_animation_time_override(0.0)
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(true)
	terrain.set_directional_cliff_projection_enabled(true)
	terrain.set_grid_aligned_cliff_rim_enabled(false)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.PROMINENT)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	var center := Vector2i(10200, 5100)
	_build_fixture(center)
	await _move_camera(center)
	var results := {}
	for mode in [
			TerrainRenderer.CliffRenderingMode.LEGACY,
			TerrainRenderer.CliffRenderingMode.GRID,
			TerrainRenderer.CliffRenderingMode.UNIFIED,
			TerrainRenderer.CliffRenderingMode.STYLISED]:
		var label: String = ["legacy", "grid", "unified", "stylised"][mode]
		print("PHASE_C4G_BENCHMARK: measuring %s" % label)
		results[label] = await _measure_c4g_mode(mode)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact", "seed": terrain.world_seed,
		"viewport": [1280, 720], "runs": RUNS,
		"steady_frames_per_run": STEADY_FRAMES, "results": results,
	}
	var file := FileAccess.open(C4G_OUTPUT_PATH, FileAccess.WRITE)
	assert(file != null, "Could not write C4G benchmark")
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_C4G_BENCHMARK: PASS")
	quit(0)


func _measure_c4g_mode(mode: int) -> Dictionary:
	terrain.set_cliff_rendering_mode(mode)
	await _wait_until_ready()
	await _wait_frames(120)
	var frame_samples: Array[float] = []
	var stream_runs: Array[Dictionary] = []
	var draw_calls_total: float = 0.0
	for _run_index in range(RUNS):
		for _frame in range(STEADY_FRAMES):
			var started: int = Time.get_ticks_usec()
			await process_frame
			frame_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
			draw_calls_total += Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		terrain.reset_incremental_cliff_scheduler_metrics()
		terrain._invalidate_streamed_chunks()
		demo._update_visible_world_region()
		stream_runs.append(await _sample_until_settled())
	var shared_surface_cells: int = 0
	var shared_surface_layers: int = 0
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null and layer.visible:
				shared_surface_layers += 1
				shared_surface_cells += layer.get_used_cells().size()
	return {
		"mode": mode, "steady": _summarize(frame_samples),
		"streaming_runs": stream_runs, "streaming_aggregate": _aggregate(stream_runs),
		"geometry": _geometry_totals(),
		"shared_surface_cells": shared_surface_cells,
		"shared_surface_layers": shared_surface_layers,
		"average_draw_calls": draw_calls_total / frame_samples.size(),
		"gpu_frame_ms": null,
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}
