extends SceneTree
## Matched G5/G6 captures and a same-scene rendering benchmark.

const OUTPUT_DIR := "res://.artifacts"
const CENTER := Vector2i(18000, 9000)
const VIEWPORT := Vector2i(1280, 720)
const ZOOMS: Array[float] = [1.0, 1.5, 2.0]
const BENCHMARK_FRAMES := 240

var demo
var terrain
var centers := {
	"snow": CENTER + Vector2i(-26, -21),
	"gravel": CENTER + Vector2i(26, -21),
	"water": CENTER + Vector2i(-26, 23),
	"cliff": CENTER + Vector2i(26, 23),
}
var captures: Array[Dictionary] = []
var comparisons: Array[String] = []
var before_by_key: Dictionary = {}


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
	await _move_camera(CENTER, 0.5, true)

	for enabled in [false, true]:
		_apply_g6(enabled)
		terrain.set_water_animation_time_override(4.0)
		for scenario in ["snow", "gravel", "water", "cliff"]:
			for zoom in ZOOMS:
				await _capture(scenario, zoom, enabled, 84521, 4.0)
		await _move_camera(CENTER, 0.5, false)
		_save_full("g6_%s_mixed_elevated_seed84521.png" % _state(enabled))
		for timestamp in [0.0, 2.0, 6.0]:
			terrain.set_water_animation_time_override(timestamp)
			await _capture("water", 1.5, enabled, 84521, timestamp, true)

	_set_seed_offsets(13579)
	_apply_g6(true)
	terrain.set_water_animation_time_override(4.0)
	for scenario in ["snow", "gravel", "water", "cliff"]:
		await _capture(scenario, 1.5, true, 13579, 4.0)
	_set_seed_offsets(84521)
	var revisit_match := await _verify_streaming_revisit()
	var performance := {
		"g5_baseline": await _measure(false),
		"g6_enabled": await _measure(true),
	}
	_write_manifest(revisit_match, performance)
	print("PHASE_G6_CAPTURE: PASS captures=%d comparisons=%d" % [
		captures.size(), comparisons.size()])
	quit(0)


func _build_fixture() -> void:
	_fill(CENTER - Vector2i(60, 48), Vector2i(120, 96), 3, 0)
	_fill(centers.snow - Vector2i(22, 18), Vector2i(44, 36), 5, 0)
	_fill(centers.gravel - Vector2i(22, 18), Vector2i(44, 36), 7, 0)
	_fill(centers.water - Vector2i(22, 18), Vector2i(44, 36), 1, 0)
	for y in range(-17, 18):
		for x in range(-21, 22):
			var delta := Vector2(float(x) / 21.0, float(y) / 17.0)
			if delta.length_squared() < 0.88 + sin(float(y) * 0.43) * 0.035:
				_set_cell(centers.water + Vector2i(x, y), 0, 0)
	_fill(centers.cliff - Vector2i(22, 18), Vector2i(44, 36), 2, 0)
	_fill(centers.cliff + Vector2i(-17, -13), Vector2i(34, 13), 4, 2)
	_fill(centers.cliff + Vector2i(-9, -12), Vector2i(18, 7), 4, 3)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), terrain_id, elevation)


func _set_cell(cell: Vector2i, terrain_id: int, elevation: int) -> void:
	terrain.world.set_override(cell, terrain_id)
	terrain.world.set_elevation_override(cell, elevation)


func _apply_g6(enabled: bool) -> void:
	terrain.set_remaining_terrain_detail_enabled(enabled)
	terrain.set_water_repetition_correction_enabled(enabled)
	terrain.set_cliff_repetition_correction_enabled(enabled)


func _capture(
		scenario: String, zoom: float, enabled: bool, seed: int,
		water_time: float, timestamp_capture: bool = false) -> void:
	await _move_camera(centers[scenario], zoom, false)
	var zoom_label := String.num(zoom, 1).replace(".", "_")
	var suffix := "_t%s" % String.num(water_time, 1).replace(".", "_") \
		if timestamp_capture else ""
	var key := "%s_seed%d_z%sx%s" % [scenario, seed, zoom_label, suffix]
	var file_name := "g6_%s_%s.png" % [_state(enabled), key]
	var image := _center_crop(_viewport_image())
	assert(image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK)
	captures.append({
		"path": "%s/%s" % [OUTPUT_DIR, file_name], "scenario": scenario,
		"enabled": enabled, "seed": seed, "zoom": zoom,
		"water_time": water_time, "camera_cell": [centers[scenario].x, centers[scenario].y],
	})
	if seed == 84521:
		if not enabled:
			before_by_key[key] = image
		elif before_by_key.has(key):
			var comparison := Image.create(
				image.get_width() * 2, image.get_height(), false, image.get_format())
			comparison.blit_rect(before_by_key[key], before_by_key[key].get_used_rect(), Vector2i.ZERO)
			comparison.blit_rect(image, image.get_used_rect(), Vector2i(image.get_width(), 0))
			var path := "%s/g6_compare_%s.png" % [OUTPUT_DIR, key]
			assert(comparison.save_png(path) == OK)
			comparisons.append(path)


func _verify_streaming_revisit() -> bool:
	_apply_g6(true)
	await _move_camera(centers.gravel, 1.5, true)
	var first := _image_hash(_center_crop(_viewport_image()))
	await _move_camera(CENTER + Vector2i(192, 96), 1.5, true)
	await _move_camera(centers.gravel, 1.5, true)
	return first == _image_hash(_center_crop(_viewport_image()))


func _measure(enabled: bool) -> Dictionary:
	_apply_g6(enabled)
	await _move_camera(CENTER, 1.0, false)
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
	return {
		"frames": samples.size(), "average_frame_ms": total / samples.size(),
		"p95_frame_ms": samples[ceili(samples.size() * 0.95) - 1],
		"average_draw_calls": draws / samples.size(),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


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
		if terrain.get_pending_chunk_count() == 0 and terrain.get_pending_edit_cell_count() == 0:
			return
	assert(false, "G6 streaming did not settle")


func _set_seed_offsets(world_seed: int) -> void:
	for definition in terrain.Catalog.MATERIALS:
		var terrain_id: int = int(definition["id"])
		terrain.visual_material_by_id[terrain_id].set_shader_parameter("seed_offset", Vector2(
			float(posmod(world_seed + terrain_id * 1301, 8192)),
			float(posmod(world_seed * 3 + terrain_id * 3253, 8192))))
	for source_id in terrain.cliff_material_by_source:
		terrain.cliff_material_by_source[source_id].set_shader_parameter("seed_offset", Vector2(
			float(posmod(world_seed * 7 + int(source_id) * 1871, 8192)),
			float(posmod(world_seed * 11 + int(source_id) * 3917, 8192))))


func _save_full(file_name: String) -> void:
	var image := _viewport_image()
	assert(image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK)


func _center_crop(image: Image) -> Image:
	return image.get_region(Rect2i((image.get_width() - 600) / 2,
		(image.get_height() - 600) / 2, 600, 600))


func _viewport_image() -> Image:
	var texture := root.get_texture()
	assert(texture != null, "G6 capture requires a rendering display driver")
	var image := texture.get_image()
	assert(image != null, "G6 capture could not read the viewport image")
	return image


func _write_manifest(revisit_match: bool, performance: Dictionary) -> void:
	var file := FileAccess.open("%s/g6_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({
		"phase": "G6", "engine": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "viewport": [1280, 720],
		"world_seeds": [84521, 13579], "zooms": ZOOMS,
		"captures": captures, "comparisons": comparisons,
		"streaming_revisit_pixel_exact": revisit_match,
		"performance": performance,
	}, "\t"))
	file.close()


func _state(enabled: bool) -> String:
	return "enabled" if enabled else "disabled"


func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
