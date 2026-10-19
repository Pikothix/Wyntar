extends SceneTree
## Phase 7C.3 graphical benchmark for raised-island editing and regeneration.

const SAMPLE_FRAMES: int = 48
const EditorController = preload("res://scripts/world_editor_controller.gd")

var demo
var terrain
var editor


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	editor = demo.editor
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_fill(Vector2i(2976, 2976), Vector2i(112, 112), 0, 0)
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2i(3032, 3032))
	await _sample_mode("static_lake", func(_frame: int) -> void: pass)
	await _sample_mode("camera_streaming", func(_frame: int) -> void:
		demo.camera.position += Vector2(96.0, 32.0)
		demo.camera.force_update_scroll()
		demo._update_visible_world_region())
	await _move_camera(Vector2i(3032, 3032))
	await _sample_mode("large_island_edit", func(frame: int) -> void:
		if frame % 8 == 0:
			_apply_height_square(Vector2i(3022 + frame / 4, 3032), 11, 2))
	await _wait_until_idle()
	await _sample_undo_redo()
	var serialized: String = JSON.stringify(terrain.export_authoritative_snapshot())
	var parsed: Variant = JSON.parse_string(serialized)
	await _sample_mode("save_load_regeneration", func(frame: int) -> void:
		if frame == 0:
			var result: Dictionary = terrain.import_authoritative_snapshot(parsed)
			assert(bool(result["ok"]), result["error"])
			demo._update_visible_world_region())
	await _wait_until_idle()
	var chunks: int = maxi(terrain.total_profiled_chunks, 1)
	print("PHASE7C3_REGEN chunks=%d avg_ms=%.3f worst_ms=%.3f cliff_avg_ms=%.4f memory_mib=%.2f scheduler_overruns=%d" % [
		terrain.total_profiled_chunks,
		float(terrain.profile_total_chunk_usec) / chunks / 1000.0,
		float(terrain.profile_worst_chunk_usec) / 1000.0,
		float(terrain.profile_total_cliff_usec) / chunks / 1000.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		terrain.chunk_processing_overrun_frames,
	])
	print("PHASE7C3_BENCHMARK: PASS")
	quit(0)


func _sample_undo_redo() -> void:
	editor.edit_mode = EditorController.EditMode.ELEVATION
	editor.brush_shape = EditorController.BrushShape.SQUARE
	editor.brush_size = 11
	editor.elevation_tool = EditorController.ElevationTool.SET_HEIGHT
	editor.target_elevation = 3
	editor.begin_stroke(Vector2i(3032, 3032))
	editor.continue_stroke(Vector2i(3040, 3036))
	editor.end_stroke()
	await _wait_until_idle()
	await _sample_mode("undo_redo_island", func(frame: int) -> void:
		if frame % 8 == 0:
			if frame % 16 == 0:
				editor.undo()
			else:
				editor.redo())
	await _wait_until_idle()


func _apply_height_square(center: Vector2i, size: int, height: int) -> void:
	var edits: Array[Dictionary] = []
	var half: int = size / 2
	for y in range(center.y - half, center.y + half + 1):
		for x in range(center.x - half, center.x + half + 1):
			edits.append({
				"cell": Vector2i(x, y), "kind": "elevation",
				"state": {"has_override": true, "value": height},
			})
	terrain.apply_world_edit_states(edits)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			terrain.world.set_override(Vector2i(x, y), material_id)
			terrain.world.set_elevation_override(Vector2i(x, y), elevation)


func _sample_mode(label: String, action: Callable) -> void:
	var values: Array[float] = []
	var previous_usec: int = Time.get_ticks_usec()
	var overruns_before: int = terrain.chunk_processing_overrun_frames
	for frame in range(SAMPLE_FRAMES):
		action.call(frame)
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		values.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
	values.sort()
	var total: float = 0.0
	for value in values:
		total += value
	print("PHASE7C3_MODE mode=%s frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f scheduler_overruns=%d" % [
		label, values.size(), total / values.size(), _percentile(values, 0.95),
		_percentile(values, 0.99), values[-1],
		terrain.chunk_processing_overrun_frames - overruns_before,
	])


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	await _wait_frames(3)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 7C.3 benchmark did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]
