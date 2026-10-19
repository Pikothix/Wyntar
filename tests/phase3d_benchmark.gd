extends "res://tests/phase1g_benchmark.gd"
## Paired Phase 3C/3D graphical benchmark on the accepted dense fixture.

const OUTPUT_PATH := "res://screenshots/phase3d_benchmark_graphical.json"
const RUNS := 3
const STEADY_FRAMES := 240


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
	var baseline: Dictionary = await _measure_mode(false)
	var prototype: Dictionary = await _measure_mode(true)
	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact",
		"viewport": [1280, 720],
		"baseline_phase3c": baseline,
		"prototype_phase3d": prototype,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 3D benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE3D_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)


func _measure_mode(connected: bool) -> Dictionary:
	terrain.set_connected_cliff_contours_enabled(connected)
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
	var geometry := _geometry_totals()
	return {
		"connected_contours": connected,
		"steady": _summarize(frame_samples),
		"streaming_runs": stream_runs,
		"streaming_aggregate": _aggregate(stream_runs),
		"geometry": geometry,
	}


func _geometry_totals() -> Dictionary:
	var vertices: int = 0
	var triangles: int = 0
	var faces: int = 0
	var nodes: int = 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		vertices += int(stats.vertex_count)
		triangles += int(stats.triangle_count)
		faces += int(stats.face_count)
		nodes += int(stats.mesh_count) + int(stats.edge_mesh_count) + int(stats.shadow_mesh_count)
	return {
		"vertices": vertices,
		"triangles": triangles,
		"faces": faces,
		"mesh_nodes": nodes,
	}
