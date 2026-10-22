extends SceneTree
## Deterministic G5 before/after matrix and matched rendering benchmark.

const OUTPUT_DIR := "res://.artifacts"
const CENTER := Vector2i(12000, 6000)
const VIEWPORT := Vector2i(1280, 720)
const MATERIALS := [
	{"id": 1, "name": "sand"}, {"id": 2, "name": "dirt"},
	{"id": 4, "name": "stone"}, {"id": 5, "name": "snow"},
	{"id": 6, "name": "mud"}, {"id": 7, "name": "gravel"},
]
const ZOOMS: Array[float] = [1.0, 1.5, 2.0]
const BLOCK_HALF := 11
const BENCHMARK_FRAMES := 240

var demo
var terrain
var centers: Array[Vector2i] = []
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
	terrain.environment_object_generation_enabled = false
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _move_camera(CENTER, 0.5, true)

	for enabled in [false, true]:
		terrain.set_stochastic_terrain_detail_enabled(enabled)
		await _move_camera(CENTER, 0.5, false)
		_save_full("g5_%s_mixed_elevation_seed84521.png" % _state(enabled))
		for index in range(MATERIALS.size()):
			for zoom in ZOOMS:
				await _capture_material(index, zoom, enabled, 84521)

	var unaffected_match := await _verify_unaffected_materials()
	_set_seed_offsets(13579)
	terrain.set_stochastic_terrain_detail_enabled(true)
	await _move_camera(centers[2], 1.5, false)
	_save_crop("g5_enabled_stone_seed13579_z1_5x.png")
	_set_seed_offsets(84521)
	var revisit_match := await _verify_streaming_revisit()
	var performance := {
		"g4_baseline": await _measure(false),
		"g5_enabled": await _measure(true),
	}
	_write_manifest(revisit_match, unaffected_match, performance)
	print("PHASE_G5_CAPTURE: PASS captures=%d comparisons=%d" % [
		captures.size(), comparisons.size()])
	quit(0)


func _build_fixture() -> void:
	for index in range(MATERIALS.size()):
		var column: int = index % 3
		var row: int = index / 3
		var block_center := CENTER + Vector2i((column - 1) * 23, row * 23 - 11)
		centers.append(block_center)
		for y in range(block_center.y - BLOCK_HALF, block_center.y + BLOCK_HALF + 1):
			for x in range(block_center.x - BLOCK_HALF, block_center.x + BLOCK_HALF + 1):
				var cell := Vector2i(x, y)
				terrain.world.set_override(cell, int(MATERIALS[index]["id"]))
				var elevation := 0
				if y >= block_center.y + 7:
					elevation = 1 + (column % 2)
				terrain.world.set_elevation_override(cell, elevation)


func _capture_material(index: int, zoom: float, enabled: bool, seed: int) -> void:
	await _move_camera(centers[index] - Vector2i(0, 3), zoom, false)
	var zoom_label := String.num(zoom, 1).replace(".", "_")
	var key := "%s_seed%d_z%sx" % [MATERIALS[index]["name"], seed, zoom_label]
	var file_name := "g5_%s_%s.png" % [_state(enabled), key]
	var image := _center_crop(root.get_texture().get_image())
	assert(image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK)
	captures.append({
		"path": "%s/%s" % [OUTPUT_DIR, file_name],
		"material_id": MATERIALS[index]["id"], "material": MATERIALS[index]["name"],
		"enabled": enabled, "seed": seed, "zoom": zoom,
		"camera_cell": [centers[index].x, centers[index].y - 3],
	})
	if not enabled:
		before_by_key[key] = image
	else:
		var comparison := Image.create(image.get_width() * 2, image.get_height(), false, image.get_format())
		comparison.blit_rect(before_by_key[key], before_by_key[key].get_used_rect(), Vector2i.ZERO)
		comparison.blit_rect(image, image.get_used_rect(), Vector2i(image.get_width(), 0))
		var path := "%s/g5_compare_%s.png" % [OUTPUT_DIR, key]
		assert(comparison.save_png(path) == OK)
		comparisons.append(path)


func _verify_unaffected_materials() -> bool:
	var results: Array[bool] = []
	for terrain_id in [0, 3, 5, 7]:
		var material: ShaderMaterial = terrain.visual_material_by_id[terrain_id]
		results.append(float(material.get_shader_parameter(
			"stochastic_terrain_detail_enabled")) == 0.0)
	return results.all(func(value): return value)


func _verify_streaming_revisit() -> bool:
	terrain.set_stochastic_terrain_detail_enabled(true)
	await _move_camera(centers[2] - Vector2i(0, 3), 1.5, true)
	var first_hash := _image_hash(_center_crop(root.get_texture().get_image()))
	await _move_camera(CENTER + Vector2i(160, 96), 1.5, true)
	await _move_camera(centers[2] - Vector2i(0, 3), 1.5, true)
	return first_hash == _image_hash(_center_crop(root.get_texture().get_image()))


func _measure(enabled: bool) -> Dictionary:
	terrain.set_stochastic_terrain_detail_enabled(enabled)
	await _move_camera(centers[2], 1.0, false)
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
		"p99_frame_ms": samples[ceili(samples.size() * 0.99) - 1],
		"average_draw_calls": draws / samples.size(),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


func _move_camera(cell: Vector2i, zoom: float, update_streaming: bool) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16.0, 16.0)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	if update_streaming:
		demo._update_visible_world_region()
		await _wait_surface_idle()
	demo.camera.force_update_scroll()
	await _frames(4)


func _wait_surface_idle(limit: int = 1800) -> void:
	for _frame in range(limit):
		await process_frame
		if terrain.get_pending_chunk_count() == 0 and terrain.get_pending_edit_cell_count() == 0:
			return
	assert(false, "G5 surface streaming did not settle")


func _set_seed_offsets(world_seed: int) -> void:
	for definition in terrain.Catalog.MATERIALS:
		var terrain_id: int = int(definition["id"])
		terrain.visual_material_by_id[terrain_id].set_shader_parameter("seed_offset", Vector2(
			float(posmod(world_seed + terrain_id * 1301, 8192)),
			float(posmod(world_seed * 3 + terrain_id * 3253, 8192))))


func _save_full(file_name: String) -> void:
	assert(root.get_texture().get_image().save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK)


func _save_crop(file_name: String) -> void:
	assert(_center_crop(root.get_texture().get_image()).save_png(
		"%s/%s" % [OUTPUT_DIR, file_name]) == OK)


func _center_crop(image: Image) -> Image:
	return image.get_region(Rect2i((image.get_width() - 600) / 2,
		(image.get_height() - 600) / 2, 600, 600))


func _write_manifest(revisit_match: bool, unaffected_match: bool, performance: Dictionary) -> void:
	var manifest := {
		"phase": "G5", "engine": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "viewport": [1280, 720],
		"world_seeds": [84521, 13579], "zooms": ZOOMS,
		"captures": captures, "comparisons": comparisons,
		"streaming_revisit_pixel_exact": revisit_match,
		"grass_water_snow_gravel_excluded": unaffected_match,
		"performance": performance,
	}
	var file := FileAccess.open("%s/g5_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
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
