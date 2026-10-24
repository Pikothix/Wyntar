extends SceneTree
## Matched G6/G7 captures and same-scene rendering benchmark.

const OUTPUT_DIR := "res://.artifacts/g7"
const CENTER := Vector2i(18000, 9000)
const VIEWPORT := Vector2i(1280, 720)
const ZOOMS: Array[float] = [1.0, 1.75, 2.5, 3.5]
const BENCHMARK_FRAMES := 240

var demo
var terrain
var centers := {
	"dirt": CENTER + Vector2i(-54, -28),
	"stone": CENTER + Vector2i(0, -28),
	"mixed": CENTER + Vector2i(54, -28),
	"gravel_mud": CENTER + Vector2i(-28, 28),
	"natural": CENTER + Vector2i(120, 80),
}
var captures: Array[Dictionary] = []
var comparisons: Array[String] = []
var baseline_by_key: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DisplayServer.window_set_size(VIEWPORT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.include_elevation_demo = false
	demo.procedural_elevation_enabled = false
	demo.decorations_enabled = false
	demo.environment_objects_enabled = false
	demo.chunks_created_per_frame = 8
	demo.max_chunk_processing_ms = 10.0
	demo.chunk_work_quantum_cells = 256
	demo.max_tile_cells_per_frame = 4096
	root.add_child(demo)
	await _frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _move_camera(CENTER, 1.0, true)
	for enabled in [false, true]:
		terrain.set_terrain_noise_refinement_enabled(enabled)
		for scenario in centers:
			for zoom in ZOOMS:
				await _capture(String(scenario), zoom, enabled)
	var revisit_match := await _verify_streaming_revisit()
	var performance := {
		"g6_baseline": await _measure(false),
		"g7_refined": await _measure(true),
	}
	_write_manifest(revisit_match, performance)
	print("PHASE_G7_CAPTURE: PASS captures=%d comparisons=%d" % [
		captures.size(), comparisons.size()])
	quit(0)


func _build_fixture() -> void:
	_fill(CENTER - Vector2i(90, 50), Vector2i(180, 100), 3)
	_fill(centers.dirt - Vector2i(25, 21), Vector2i(50, 42), 2)
	_fill(centers.stone - Vector2i(25, 21), Vector2i(50, 42), 4)
	for y in range(-21, 21):
		for x in range(-25, 25):
			var boundary := sin(float(y) * 0.31) * 4.0 + sin(float(y) * 0.09) * 7.0
			_set_cell(centers.mixed + Vector2i(x, y), 2 if float(x) < boundary else 4)
	for y in range(-21, 21):
		for x in range(-25, 25):
			var boundary := sin(float(y) * 0.27) * 5.0
			_set_cell(centers.gravel_mud + Vector2i(x, y),
				7 if float(x) < boundary else 6)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), terrain_id)


func _set_cell(cell: Vector2i, terrain_id: int) -> void:
	terrain.world.set_override(cell, terrain_id)
	terrain.world.set_elevation_override(cell, 0)


func _capture(scenario: String, zoom: float, enabled: bool) -> void:
	await _move_camera(centers[scenario], zoom, true)
	var zoom_label := String.num(zoom, 2).replace(".", "_")
	var key := "%s_z%sx" % [scenario, zoom_label]
	var state := "refined" if enabled else "baseline"
	var file_name := "g7_%s_%s.png" % [state, key]
	var image := _center_crop(_viewport_image())
	assert(image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK)
	captures.append({"path": "%s/%s" % [OUTPUT_DIR, file_name],
		"scenario": scenario, "refined": enabled, "zoom": zoom,
		"camera_cell": [centers[scenario].x, centers[scenario].y]})
	if not enabled:
		baseline_by_key[key] = image
	elif baseline_by_key.has(key):
		var comparison := Image.create(
			image.get_width() * 2, image.get_height(), false, image.get_format())
		comparison.blit_rect(baseline_by_key[key], image.get_used_rect(), Vector2i.ZERO)
		comparison.blit_rect(image, image.get_used_rect(), Vector2i(image.get_width(), 0))
		var path := "%s/g7_compare_%s.png" % [OUTPUT_DIR, key]
		assert(comparison.save_png(path) == OK)
		comparisons.append(path)


func _verify_streaming_revisit() -> bool:
	terrain.set_terrain_noise_refinement_enabled(true)
	await _move_camera(centers.mixed, 1.75, true)
	var first := _image_hash(_center_crop(_viewport_image()))
	await _move_camera(CENTER + Vector2i(256, 160), 1.75, true)
	await _move_camera(centers.mixed, 1.75, true)
	return first == _image_hash(_center_crop(_viewport_image()))


func _measure(enabled: bool) -> Dictionary:
	terrain.set_terrain_noise_refinement_enabled(enabled)
	await _move_camera(CENTER, 1.0, true)
	await _frames(30)
	var samples: Array[float] = []
	var draws := 0.0
	for _frame in range(BENCHMARK_FRAMES):
		var started := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	samples.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	return {"frames": samples.size(), "average_frame_ms": total / samples.size(),
		"p95_frame_ms": samples[ceili(samples.size() * 0.95) - 1],
		"average_draw_calls": draws / samples.size(),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}


func _move_camera(cell: Vector2i, zoom: float, update_streaming: bool) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16.0, 16.0)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	if update_streaming:
		demo._update_visible_world_region()
		await _wait_idle()
	demo.camera.force_update_scroll()
	await _frames(4)


func _wait_idle(limit: int = 1800) -> void:
	for _frame in range(limit):
		await process_frame
		if terrain.get_pending_chunk_count() == 0 \
				and terrain.get_pending_edit_cell_count() == 0:
			return
	assert(false, "G7 streaming did not settle")


func _center_crop(image: Image) -> Image:
	return image.get_region(Rect2i((image.get_width() - 600) / 2,
		(image.get_height() - 600) / 2, 600, 600))


func _viewport_image() -> Image:
	var texture := root.get_texture()
	assert(texture != null, "G7 capture requires a rendering display driver")
	return texture.get_image()


func _write_manifest(revisit_match: bool, performance: Dictionary) -> void:
	var file := FileAccess.open("%s/g7_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"phase": "G7",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "viewport": [1280, 720],
		"world_seed": 84521, "zooms": ZOOMS, "captures": captures,
		"comparisons": comparisons,
		"streaming_revisit_pixel_exact": revisit_match,
		"performance": performance}, "\t"))
	file.close()


func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
