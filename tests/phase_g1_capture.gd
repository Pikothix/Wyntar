extends SceneTree
## Deterministic Phase G1 visual matrix and small matched shader benchmark.

const OUTPUT_DIR := "res://.artifacts"
const CENTER := Vector2i(12000, 6000)
const VIEWPORT := Vector2i(1280, 720)
const ZOOMS: Array[float] = [1.0, 2.31]
const BENCHMARK_FRAMES := 360

var demo
var terrain
var captures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(VIEWPORT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _move_camera(1.0)

	var modes := [
		{"name": "legacy", "enabled": false, "coverage": 0.70, "density": 0.35},
		{"name": "clear70_density35", "enabled": true, "coverage": 0.70, "density": 0.35},
		{"name": "clear50_density35", "enabled": true, "coverage": 0.50, "density": 0.35},
		{"name": "clear85_density35", "enabled": true, "coverage": 0.85, "density": 0.35},
		{"name": "clear70_density15", "enabled": true, "coverage": 0.70, "density": 0.15},
		{"name": "clear70_density60", "enabled": true, "coverage": 0.70, "density": 0.60},
	]
	for mode in modes:
		_apply_mode(mode)
		for zoom in ZOOMS:
			await _move_camera(zoom)
			await _save_capture(mode, zoom)

	var performance := {
		"legacy": await _measure_mode(modes[0]),
		"target": await _measure_mode(modes[1]),
	}
	_write_manifest(modes, performance)
	print("PHASE_G1_CAPTURE: PASS captures=%d" % captures.size())
	quit(0)


func _build_fixture() -> void:
	_fill(CENTER - Vector2i(24, 18), Vector2i(48, 36), 3)
	# Curved material islands keep grass boundaries visible without altering
	# elevation, cliffs, or any authoritative generation algorithm.
	for y in range(-13, 14):
		for x in range(-21, 22):
			var point := CENTER + Vector2i(x, y)
			if Vector2(x + 13, y - 1).length() < 6.5:
				_set_cell(point, 2)
			elif Vector2(x - 13, y + 4).length() < 5.5:
				_set_cell(point, 4)
			elif y > 8 + roundi(sin(float(x) * 0.35) * 2.0):
				_set_cell(point, 1)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), terrain_id)


func _set_cell(point: Vector2i, terrain_id: int) -> void:
	terrain.world.set_override(point, terrain_id)
	terrain.world.set_elevation_override(point, 0)


func _apply_mode(mode: Dictionary) -> void:
	terrain.set_clustered_grass_detail_controls(
		float(mode.coverage), float(mode.density), 0.004, 0.12, 0.04, 48131)
	terrain.set_clustered_grass_detail_enabled(bool(mode.enabled))


func _move_camera(zoom: float) -> void:
	demo.camera.position = Vector2(CENTER * terrain.TILE_SIZE) + Vector2(16.0, 16.0)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _save_capture(mode: Dictionary, zoom: float) -> void:
	var zoom_label: String = String.num(zoom, 2).replace(".", "_")
	var file_name := "g1_%s_seed%d_z%sx.png" % [
		String(mode.name), terrain.world_seed, zoom_label]
	var image: Image = root.get_texture().get_image()
	assert(image != null, "Graphical renderer is required for Phase G1 capture")
	var error: Error = image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	assert(error == OK, "Could not save Phase G1 capture")
	captures.append({
		"path": "%s/%s" % [OUTPUT_DIR, file_name],
		"mode": String(mode.name),
		"enabled": bool(mode.enabled),
		"clear_area_coverage": float(mode.coverage),
		"detail_density": float(mode.density),
		"zoom": zoom,
	})


func _measure_mode(mode: Dictionary) -> Dictionary:
	_apply_mode(mode)
	await _move_camera(1.0)
	await _wait_frames(60)
	var samples: Array[float] = []
	var draw_total: float = 0.0
	for _frame in range(BENCHMARK_FRAMES):
		var started: int = Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_total += float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	samples.sort()
	var total: float = 0.0
	for sample in samples:
		total += sample
	return {
		"frames": samples.size(),
		"average_frame_ms": total / samples.size(),
		"p95_frame_ms": samples[ceili(samples.size() * 0.95) - 1],
		"p99_frame_ms": samples[ceili(samples.size() * 0.99) - 1],
		"worst_frame_ms": samples[-1],
		"average_draw_calls": draw_total / samples.size(),
		"static_memory_mib": Performance.get_monitor(
			Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
	}


func _write_manifest(modes: Array, performance: Dictionary) -> void:
	var manifest := {
		"phase": "G1",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [VIEWPORT.x, VIEWPORT.y],
		"world_seed": terrain.world_seed,
		"camera_cell": [CENTER.x, CENTER.y],
		"cluster_scale": 0.004,
		"transition_softness": 0.12,
		"clear_area_residual_density": 0.04,
		"detail_seed_offset": 48131,
		"modes": modes,
		"captures": captures,
		"performance": performance,
	}
	var file := FileAccess.open("%s/g1_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write Phase G1 capture manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase G1 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
