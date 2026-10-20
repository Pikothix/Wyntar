extends SceneTree
## Basic feasibility measurements only; Phase 2A deliberately does not begin
## the separate Phase 1C optimisation work.

const ObliqueProjection = preload("res://scripts/oblique_projection.gd")
const OUTPUT_PATH := "res://.artifacts/phase2a_benchmark.json"
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

	var target := Vector2i(256, 128)
	await _set_mode_and_center(false, target)
	results.phase1b = await _sample("phase1b")
	var toggle_started := Time.get_ticks_usec()
	terrain.set_oblique_presentation_enabled(true)
	await _set_mode_and_center(true, target)
	var toggle_ms := float(Time.get_ticks_usec() - toggle_started) / 1000.0
	results.phase2a = await _sample("phase2a")
	results.phase2a.toggle_and_build_ms = toggle_ms
	results.phase2a.geometry = terrain.get_oblique_metrics()

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 2A benchmark result")
		quit(1)
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PHASE2A_BENCHMARK: %s" % JSON.stringify(results))
	quit(0)


func _sample(label: String) -> Dictionary:
	var values: Array[float] = []
	var draw_calls_total := 0.0
	for frame in range(SAMPLE_FRAMES):
		if frame % 20 == 0:
			demo.camera.position += Vector2(12.0, 4.0)
			demo.camera.force_update_scroll()
		var started := Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_calls_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	var result := {
		"average_frame_ms": total / float(values.size()),
		"p95_frame_ms": values[clampi(roundi(values.size() * 0.95) - 1, 0, values.size() - 1)],
		"worst_frame_ms": values[-1],
		"average_draw_calls": draw_calls_total / float(values.size()),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	print("PHASE2A_MODE %s %s" % [label, JSON.stringify(result)])
	return result


func _set_mode_and_center(oblique: bool, cell: Vector2i) -> void:
	terrain.set_oblique_presentation_enabled(oblique)
	if oblique:
		demo.camera.position = ObliqueProjection.project_cell_center(
			cell, terrain.get_world_surface_elevation(cell))
	else:
		demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase 2A benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
