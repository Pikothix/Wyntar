extends SceneTree
## Phase 7C repeatable frame and preparation benchmark. Presentation timings
## are reported separately; authoritative state remains owned by TerrainWorld.

const SAMPLE_FRAMES: int = 60

var demo
var terrain


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
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_fixtures()
	terrain._invalidate_streamed_chunks()

	await _move_camera(Vector2i(620, 620))
	await _sample_mode("static_view", func(_frame: int) -> void: pass)
	await _sample_mode("camera_only_streaming", func(_frame: int) -> void:
		demo.camera.position += Vector2(80.0, 24.0)
		demo.camera.force_update_scroll()
		demo._update_visible_world_region())

	await _move_camera(Vector2i(620, 620))
	await _sample_mode("shoreline_heavy", func(_frame: int) -> void: pass)
	await _move_camera(Vector2i(748, 620))
	await _sample_mode("dense_cliffs", func(_frame: int) -> void: pass)

	var edit_cell := Vector2i(620, 620)
	await _sample_mode("terrain_edit_near_liquid", func(frame: int) -> void:
		if frame % 12 == 0:
			terrain.set_world_cell(edit_cell, 1 if terrain.get_world_cell(edit_cell) == 0 else 0))
	await _wait_until_idle()

	var serialized: String = JSON.stringify(terrain.export_authoritative_snapshot())
	var parsed: Variant = JSON.parse_string(serialized)
	await _sample_mode("save_load_regeneration", func(frame: int) -> void:
		if frame == 0:
			var result: Dictionary = terrain.import_authoritative_snapshot(parsed)
			assert(bool(result["ok"]), result["error"])
			demo._update_visible_world_region())
	await _wait_until_idle()

	var memory_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var chunks: int = maxi(terrain.total_profiled_chunks, 1)
	print("PHASE7C_PREPARATION chunks=%d chunk_avg_ms=%.3f chunk_worst_ms=%.3f liquid_surface_avg_ms=%.4f cliff_total_avg_ms=%.4f cliff_lip_avg_ms=%.4f memory_bytes=%d scheduler_overruns=%d" % [
		terrain.total_profiled_chunks,
		float(terrain.profile_total_chunk_usec) / chunks / 1000.0,
		float(terrain.profile_worst_chunk_usec) / 1000.0,
		float(terrain.profile_total_liquid_surface_usec) / chunks / 1000.0,
		float(terrain.profile_total_cliff_usec) / chunks / 1000.0,
		float(terrain.profile_total_cliff_edge_usec) / chunks / 1000.0,
		memory_bytes, terrain.chunk_processing_overrun_frames,
	])
	print("PHASE7C_BENCHMARK: PASS")
	quit(0)


func _build_fixtures() -> void:
	# Shoreline-heavy checkerboard at sea level.
	for y in range(592, 649):
		for x in range(580, 661):
			var water: bool = (floori(float(x) / 5.0) + floori(float(y) / 5.0)) % 2 == 0
			_set_cell(Vector2i(x, y), 0 if water else (1 if x % 2 == 0 else 3), 0)
	# Dense stepped cliffs with liquid contacts.
	for y in range(592, 649):
		for x in range(708, 789):
			var band: int = posmod(
				floori(float(x - 708) / 7.0) + floori(float(y - 592) / 6.0), 4)
			var material_id: int = 0 if band == 0 else (4 if band >= 2 else 7)
			_set_cell(Vector2i(x, y), material_id, band)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


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
	print("PHASE7C_MODE mode=%s frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f scheduler_overruns=%d" % [
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
	assert(false, "Phase 7C benchmark did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]
