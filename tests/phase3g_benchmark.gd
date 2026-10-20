extends "res://tests/phase3f_benchmark.gd"
## Same dense fixture, frame windows, streaming workload and batching as 3F.


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
	var baseline: Dictionary = await _measure_phase3f_profile(0)
	var prominent: Dictionary = await _measure_phase3f_profile(2)
	terrain.set_directional_cliff_projection_enabled(true)
	var directional: Dictionary = await _measure_phase3f_profile(2)
	var result := {
		"engine": Engine.get_version_info().get("string"),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact", "viewport": [1280, 720],
		"baseline": baseline, "prominent": prominent, "directional": directional}
	var file := FileAccess.open("res://screenshots/phase3g_benchmark_graphical.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("PHASE3G_BENCHMARK: PASS")
	quit(0)
