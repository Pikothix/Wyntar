extends SceneTree
## Controlled Phase G2 before/after matrix plus bounded matched benchmark.

const OUTPUT_DIR := "res://.artifacts"
const MEADOW_CENTER := Vector2i(12000, 6000)
const MIXED_CENTER := Vector2i(12128, 6000)
const BOUNDARY_CENTER := Vector2i(12160, 6000)
const VIEWPORT := Vector2i(1280, 720)
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
	demo.decorations_enabled = false
	demo.environment_objects_enabled = false
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	_build_fixtures()
	terrain._invalidate_streamed_chunks()
	await _move_camera(MEADOW_CENTER, 1.0)

	for enabled in [false, true]:
		await _capture_mode(84521, true, enabled, "meadow", MEADOW_CENTER, 1.0)
		await _capture_mode(84521, true, enabled, "meadow_zoom", MEADOW_CENTER, 2.31)
		await _capture_mode(84521, true, enabled, "dirt_sand", MIXED_CENTER, 1.0)
		await _capture_mode(84521, true, enabled, "chunk_boundary", BOUNDARY_CENTER, 2.31)
		await _capture_mode(84521, false, enabled, "meadow_g1_off", MEADOW_CENTER, 1.0)
		await _capture_mode(13579, true, enabled, "meadow_second_seed", MEADOW_CENTER, 1.0)

	var performance: Dictionary = {
		"g2_disabled": await _measure_mode(false),
		"g2_enabled": await _measure_mode(true),
	}
	_write_manifest(performance)
	print("PHASE_G2_CAPTURE: PASS captures=%d" % captures.size())
	quit(0)


func _build_fixtures() -> void:
	_fill(MEADOW_CENTER - Vector2i(26, 20), Vector2i(52, 40), 3)
	_fill(MIXED_CENTER - Vector2i(26, 20), Vector2i(70, 40), 3)
	for y in range(-15, 16):
		for x in range(-24, 25):
			var point: Vector2i = MIXED_CENTER + Vector2i(x, y)
			if Vector2(x + 13, y - 1).length() < 7.0:
				_set_cell(point, 2)
			elif Vector2(x - 13, y + 3).length() < 6.5:
				_set_cell(point, 1)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), terrain_id)


func _set_cell(point: Vector2i, terrain_id: int) -> void:
	terrain.world.set_override(point, terrain_id)
	terrain.world.set_elevation_override(point, 0)


func _capture_mode(
		seed: int, g1_enabled: bool, g2_enabled: bool, scenario: String,
		center: Vector2i, zoom: float) -> void:
	_apply_mode(seed, g1_enabled, g2_enabled)
	await _move_camera(center, zoom)
	var state: String = "after" if g2_enabled else "before"
	var g1_label: String = "on" if g1_enabled else "off"
	var zoom_label: String = String.num(zoom, 2).replace(".", "_")
	var file_name: String = "g2_%s_seed%d_g1%s_%s_z%sx.png" % [
		state, seed, g1_label, scenario, zoom_label]
	var image: Image = root.get_texture().get_image()
	assert(image != null, "Graphical renderer is required for Phase G2 capture")
	var error: Error = image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	assert(error == OK, "Could not save Phase G2 capture")
	captures.append({
		"path": "%s/%s" % [OUTPUT_DIR, file_name],
		"state": state,
		"seed": seed,
		"g1_enabled": g1_enabled,
		"g2_enabled": g2_enabled,
		"scenario": scenario,
		"camera_cell": [center.x, center.y],
		"zoom": zoom,
	})


func _apply_mode(seed: int, g1_enabled: bool, g2_enabled: bool) -> void:
	terrain.world_seed = seed
	terrain.set_clustered_grass_detail_controls(0.70, 0.35, 0.004, 0.12, 0.04, 48131)
	terrain.set_clustered_grass_detail_enabled(g1_enabled)
	terrain.set_organic_grass_color_variation_controls(0.0015, 0.055, 0.018)
	terrain.set_organic_grass_color_variation_enabled(g2_enabled)


func _move_camera(center: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16.0, 16.0)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _measure_mode(enabled: bool) -> Dictionary:
	_apply_mode(84521, true, enabled)
	await _move_camera(MEADOW_CENTER, 1.0)
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


func _write_manifest(performance: Dictionary) -> void:
	var manifest: Dictionary = {
		"phase": "G2",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [VIEWPORT.x, VIEWPORT.y],
		"parameters": {
			"broad_variation_scale": 0.0015,
			"color_variation_strength": 0.055,
			"fine_variation_strength": 0.018,
		},
		"captures": captures,
		"performance": performance,
	}
	var file: FileAccess = FileAccess.open(
		"%s/g2_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write Phase G2 capture manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase G2 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
