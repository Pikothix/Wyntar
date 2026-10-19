extends SceneTree
## Phase 7C.4 graphical benchmark for unified cliff profile preparation.

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
	_build_fixtures()
	terrain._invalidate_streamed_chunks()

	await _move_camera(Vector2i(4300, 3000))
	await _sample("static_terrain", func(_frame: int) -> void: pass)
	await _sample("camera_streaming", func(_frame: int) -> void:
		demo.camera.position += Vector2(96, 32)
		demo.camera.force_update_scroll()
		demo._update_visible_world_region())
	await _move_camera(Vector2i(4428, 3000))
	await _sample("dense_cliffs", func(_frame: int) -> void: pass)
	await _move_camera(Vector2i(4300, 3128))
	await _sample("isolated_raised_cells", func(_frame: int) -> void: pass)
	await _move_camera(Vector2i(4428, 3128))
	await _sample("large_plateau", func(_frame: int) -> void: pass)
	await _sample("large_elevation_brush", func(frame: int) -> void:
		if frame % 8 == 0:
			_apply_height_square(Vector2i(4420 + frame / 4, 3128), 11, 3 if frame % 16 == 0 else 1))
	await _wait_until_idle()
	await _sample_undo_redo()
	var snapshot: Variant = JSON.parse_string(JSON.stringify(terrain.export_authoritative_snapshot()))
	await _sample("save_load_regeneration", func(frame: int) -> void:
		if frame == 0:
			var result: Dictionary = terrain.import_authoritative_snapshot(snapshot)
			assert(bool(result.ok), result.error)
			demo._update_visible_world_region())
	await _wait_until_idle()
	var chunks: int = maxi(terrain.total_profiled_chunks, 1)
	print("PHASE7C4_PREPARATION chunks=%d avg_ms=%.3f worst_ms=%.3f cliff_avg_ms=%.4f edge_avg_ms=%.4f memory_mib=%.2f scheduler_overruns=%d" % [
		terrain.total_profiled_chunks,
		float(terrain.profile_total_chunk_usec) / chunks / 1000.0,
		float(terrain.profile_worst_chunk_usec) / 1000.0,
		float(terrain.profile_total_cliff_usec) / chunks / 1000.0,
		float(terrain.profile_total_cliff_edge_usec) / chunks / 1000.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		terrain.chunk_processing_overrun_frames])
	print("PHASE7C4_BENCHMARK: PASS")
	quit(0)


func _build_fixtures() -> void:
	_fill(Vector2i(4264, 2964), Vector2i(72, 72), 1, 0)
	for y in range(2964, 3036):
		for x in range(4392, 4464):
			_set_cell(Vector2i(x, y), 4, posmod((x - 4392) / 4 + (y - 2964) / 5, 4))
	_fill(Vector2i(4264, 3092), Vector2i(72, 72), 1, 0)
	for y in range(3094, 3162, 4):
		for x in range(4266, 4334, 4):
			_set_cell(Vector2i(x, y), 1, 1 + posmod(x + y, 3))
	_fill(Vector2i(4392, 3092), Vector2i(72, 72), 1, 0)
	_fill(Vector2i(4400, 3100), Vector2i(56, 48), 1, 2)


func _sample_undo_redo() -> void:
	editor.edit_mode = EditorController.EditMode.ELEVATION
	editor.brush_shape = EditorController.BrushShape.SQUARE
	editor.brush_size = 11
	editor.elevation_tool = EditorController.ElevationTool.SET_HEIGHT
	editor.target_elevation = 3
	editor.begin_stroke(Vector2i(4428, 3128))
	editor.continue_stroke(Vector2i(4436, 3132))
	editor.end_stroke()
	await _wait_until_idle()
	await _sample("undo_redo", func(frame: int) -> void:
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
			edits.append({"cell": Vector2i(x, y), "kind": "elevation",
				"state": {"has_override": true, "value": height}})
	terrain.apply_world_edit_states(edits)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _sample(label: String, action: Callable) -> void:
	var values: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	var overruns_before: int = terrain.chunk_processing_overrun_frames
	for frame in range(SAMPLE_FRAMES):
		action.call(frame)
		await process_frame
		var now: int = Time.get_ticks_usec()
		values.append(float(now - previous) / 1000.0)
		previous = now
	values.sort()
	var total: float = 0.0
	for value in values:
		total += value
	print("PHASE7C4_MODE mode=%s avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f scheduler_overruns=%d" % [
		label, total / values.size(), _percentile(values, 0.95),
		_percentile(values, 0.99), values[-1],
		terrain.chunk_processing_overrun_frames - overruns_before])


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
	assert(false, "Phase 7C.4 benchmark did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]
