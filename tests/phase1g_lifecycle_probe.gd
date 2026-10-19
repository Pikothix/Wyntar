extends SceneTree
## Isolates synchronous retirement submission from Godot's deferred scene-tree
## and resource release. This probe intentionally performs no replacement build.

const OUTPUT_PATH := "res://screenshots/phase1g_lifecycle_probe_after.json"

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	terrain._invalidate_streamed_chunks()
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	await _wait_frames(10)

	var chunks: Array = terrain.loaded_chunks.values()
	var node_count_before: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resource_count_before: int = roundi(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var memory_before: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var submission_started: int = Time.get_ticks_usec()
	for chunk in chunks:
		terrain._queue_chunk_retirement(chunk)
	var submission_usec: int = Time.get_ticks_usec() - submission_started
	terrain.loaded_chunks.clear()
	var frames: Array[Dictionary] = []
	for frame_index in range(72):
		var started: int = Time.get_ticks_usec()
		await process_frame
		frames.append({
			"index": frame_index + 1,
			"frame_ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"nodes": roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"resources": roundi(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"pending_retirements": terrain.get_pending_chunk_retirement_count(),
		})
	var result := {
		"display_server": DisplayServer.get_name(),
		"chunk_count": chunks.size(),
		"queue_free_submission_ms": float(submission_usec) / 1000.0,
		"node_count_before": node_count_before,
		"resource_count_before": resource_count_before,
		"static_memory_before_mib": memory_before / 1048576.0,
		"frames_after_submission": frames,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 1G lifecycle probe")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE1G_LIFECYCLE_PROBE: %s" % JSON.stringify(result))
	quit(0)


func _build_fixture(center: Vector2i) -> void:
	for y in range(-42, 42):
		for x in range(-54, 54):
			var pos: Vector2i = center + Vector2i(x, y)
			var ridge: float = sin(float(x) * 0.28) + cos(float(y) * 0.23)
			var height: int = clampi(floori((ridge + 2.0) * 0.99), 0, 3)
			terrain.world.set_override(pos, 4 if (x + y) % 4 else 2)
			terrain.world.set_elevation_override(pos, height)


func _wait_until_idle(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1G lifecycle probe did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
