extends SceneTree
## Phase G3 fixed-camera before/after matrix and bounded matched benchmark.

const OUTPUT_DIR := "res://.artifacts"
const CENTER := Vector2i(12000, 6000)
const VIEWPORT := Vector2i(1280, 720)
const ZOOMS: Array[float] = [1.0, 1.5, 2.0]
const BENCHMARK_FRAMES := 360

var demo
var terrain
var captures: Array[Dictionary] = []
var before_by_key: Dictionary = {}
var enabled_hash_by_key: Dictionary = {}
var comparisons: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(VIEWPORT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.include_elevation_demo = false
	demo.procedural_elevation_enabled = false
	demo.decorations_enabled = false
	demo.environment_objects_enabled = false
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _move_camera(1.0)

	for enabled in [false, true]:
		for zoom in ZOOMS:
			await _capture_mode(84521, true, enabled, "seed84521_g1on", zoom)
		await _capture_mode(84521, false, enabled, "seed84521_g1off", 1.5)
		await _capture_mode(13579, true, enabled, "seed13579_g1on", 1.5)

	var streaming_revisit_match: bool = await _verify_streaming_revisit()
	var performance := {
		"g3_disabled": await _measure_mode(false),
		"g3_enabled": await _measure_mode(true),
	}
	_write_manifest(performance, streaming_revisit_match)
	print("PHASE_G3_CAPTURE: PASS captures=%d comparisons=%d" % [
		captures.size(), comparisons.size()])
	quit(0)


func _build_fixture() -> void:
	for y in range(CENTER.y - 28, CENTER.y + 29):
		for x in range(CENTER.x - 36, CENTER.x + 37):
			terrain.world.set_override(Vector2i(x, y), 3)
			terrain.world.set_elevation_override(Vector2i(x, y), 0)


func _capture_mode(
		seed: int, g1_enabled: bool, g3_enabled: bool,
		scenario: String, zoom: float) -> void:
	_apply_mode(seed, g1_enabled, g3_enabled)
	await _move_camera(zoom)
	var state: String = "enabled" if g3_enabled else "disabled"
	var zoom_label: String = String.num(zoom, 1).replace(".", "_")
	var key := "%s_z%sx" % [scenario, zoom_label]
	var file_name := "g3_%s_%s.png" % [state, key]
	var image: Image = root.get_texture().get_image()
	assert(image != null, "Graphical renderer is required for G3 capture")
	assert(image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK,
		"Could not save G3 capture")
	captures.append({
		"path": "%s/%s" % [OUTPUT_DIR, file_name],
		"state": state,
		"seed": seed,
		"g1_enabled": g1_enabled,
		"g3_enabled": g3_enabled,
		"camera_cell": [CENTER.x, CENTER.y],
		"camera_on_chunk_boundary_x": posmod(CENTER.x, 32) == 0,
		"zoom": zoom,
	})
	if not g3_enabled:
		before_by_key[key] = image
	else:
		enabled_hash_by_key[key] = _image_hash(image)
		_save_side_by_side(key, before_by_key[key], image)


func _save_side_by_side(key: String, before: Image, after: Image) -> void:
	var combined := Image.create(
		before.get_width() * 2, before.get_height(), false, before.get_format())
	combined.blit_rect(before, before.get_used_rect(), Vector2i.ZERO)
	combined.blit_rect(after, after.get_used_rect(), Vector2i(before.get_width(), 0))
	var path := "%s/g3_compare_%s.png" % [OUTPUT_DIR, key]
	assert(combined.save_png(path) == OK, "Could not save G3 comparison")
	comparisons.append(path)


func _apply_mode(seed: int, g1_enabled: bool, g3_enabled: bool) -> void:
	terrain.world_seed = seed
	terrain.set_clustered_grass_detail_controls(
		0.70, 0.35, 0.004, 0.12, 0.04, 48131)
	terrain.set_clustered_grass_detail_enabled(g1_enabled)
	terrain.set_organic_grass_color_variation_controls(0.0015, 0.055, 0.018)
	terrain.set_organic_grass_color_variation_enabled(true)
	terrain.set_grass_texture_repetition_correction_enabled(g3_enabled)


func _move_camera(zoom: float) -> void:
	await _move_camera_to(CENTER, zoom)


func _move_camera_to(center: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16.0, 16.0)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _verify_streaming_revisit() -> bool:
	_apply_mode(84521, true, true)
	await _move_camera_to(CENTER + Vector2i(160, 96), 1.5)
	await _move_camera_to(CENTER, 1.5)
	var revisit: Image = root.get_texture().get_image()
	var matches: bool = _image_hash(revisit) == String(
		enabled_hash_by_key["seed84521_g1on_z1_5x"])
	assert(matches, "G3 changed after streaming away and revisiting fixed coordinates")
	return matches


func _measure_mode(enabled: bool) -> Dictionary:
	_apply_mode(84521, true, enabled)
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


func _write_manifest(performance: Dictionary, streaming_revisit_match: bool) -> void:
	var manifest := {
		"phase": "G3",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [VIEWPORT.x, VIEWPORT.y],
		"world_seeds": [84521, 13579],
		"camera_cell": [CENTER.x, CENTER.y],
		"camera_on_chunk_boundary_x": posmod(CENTER.x, 32) == 0,
		"zooms": ZOOMS,
		"captures": captures,
		"comparisons": comparisons,
		"streaming_revisit_pixel_exact": streaming_revisit_match,
		"performance": performance,
	}
	var file := FileAccess.open("%s/g3_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write G3 manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase G3 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
