extends SceneTree
## Direct static and rebuild comparison. This records feasibility costs only;
## it does not introduce Phase 2C streaming optimisation.

const ObliqueProjection = preload("res://scripts/oblique_projection.gd")
const OUTPUT_PATH := "res://.artifacts/phase2b_benchmark.json"
const SAMPLE_FRAMES := 120

var demo
var terrain
var results: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_oblique_presentation_enabled(true)
	await _move_camera(Vector2i(256, 128))

	results.phase2a = await _sample()
	results.phase2a.geometry = terrain.get_oblique_metrics()
	var toggle_started := Time.get_ticks_usec()
	terrain.set_organic_oblique_refinement_enabled(true)
	await _wait_frames(3)
	results.phase2b = await _sample()
	results.phase2b.toggle_rebuild_ms = (
		float(Time.get_ticks_usec() - toggle_started) / 1000.0)
	results.phase2b.geometry = terrain.get_oblique_metrics()

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 2B benchmark result")
		quit(1)
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PHASE2B_BENCHMARK: %s" % JSON.stringify(results))
	quit(0)


func _sample() -> Dictionary:
	var values: Array[float] = []
	var draw_calls_total := 0.0
	for _frame in range(SAMPLE_FRAMES):
		var started := Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_calls_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"average_frame_ms": total / float(values.size()),
		"p95_frame_ms": values[clampi(roundi(values.size() * 0.95) - 1, 0, values.size() - 1)],
		"worst_frame_ms": values[-1],
		"average_draw_calls": draw_calls_total / float(values.size()),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = ObliqueProjection.project_cell_center(
		cell, terrain.get_world_surface_elevation(cell))
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase 2B benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
