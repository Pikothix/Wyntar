extends SceneTree
## Repeatable Phase 8A comparison captures. The first two cameras match the
## Phase 6B baseline fixtures; the gallery shows every integrated archetype.

const OUTPUT_DIR := "res://.artifacts"

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	_create_phase6b_comparison_fixtures()
	terrain._invalidate_streamed_chunks()
	await _capture_at("phase8a_comparison_sparse_grassland_1_0x", Vector2i(210, 200), 1.0)
	await _capture_at("phase8a_comparison_rocky_boulders_1_0x", Vector2i(210, 232), 1.0)
	await _capture_at("phase8a_comparison_lake_vegetation_1_0x", Vector2i(242, 232), 1.0)
	await _capture_at("phase8a_comparison_chunk_boundary_1_0x", Vector2i(256, 264), 1.0)
	await _create_and_capture_gallery()
	print("PHASE8A_GRAPHICAL_CAPTURE: PASS")
	quit(0)


func _create_phase6b_comparison_fixtures() -> void:
	_fill(Vector2i(194, 184), Vector2i(32, 32), 3, 0)
	_fill(Vector2i(194, 216), Vector2i(32, 32), 4, 2)
	_fill(Vector2i(203, 225), Vector2i(14, 14), 7, 3)
	_fill(Vector2i(226, 216), Vector2i(32, 32), 3, 0)
	_fill(Vector2i(235, 224), Vector2i(14, 15), 0, 2)
	for y in range(223, 240):
		for x in range(234, 250):
			var pos := Vector2i(x, y)
			if terrain.world.get_cell(pos) != 0 and (x in [234, 249] or y in [223, 239]):
				_set_fixture_cell(pos, 6, 0)
	_fill(Vector2i(240, 248), Vector2i(32, 32), 3, 1)
	_fill(Vector2i(248, 255), Vector2i(17, 18), 3, 2)


func _create_and_capture_gallery() -> void:
	terrain.set_environment_object_generation_enabled(false)
	var origin := Vector2i(386, 386)
	_fill(origin, Vector2i(28, 18), 3, 0)
	_fill(origin + Vector2i(14, 0), Vector2i(14, 6), 2, 0)
	for x in range(origin.x, origin.x + 28):
		for y in range(origin.y + 6, origin.y + 12):
			_set_fixture_cell(Vector2i(x, y), 4, 1)
		for y in range(origin.y + 12, origin.y + 18):
			_set_fixture_cell(Vector2i(x, y), 3, 2)
	terrain._invalidate_streamed_chunks()
	await _move_camera(Vector2(origin + Vector2i(14, 9)) * Vector2(32, 32), 1.0)
	var anchors: Array[Vector2i] = [
		origin + Vector2i(3, 4), origin + Vector2i(9, 4),
		origin + Vector2i(15, 4), origin + Vector2i(21, 4),
		origin + Vector2i(3, 9), origin + Vector2i(9, 9),
		origin + Vector2i(15, 9), origin + Vector2i(21, 9),
		origin + Vector2i(5, 15), origin + Vector2i(12, 15),
		origin + Vector2i(19, 15),
	]
	var ids := PackedInt32Array([0, 1, 2, 3, 8, 9, 10, 11, 4, 5, 7])
	var variants := PackedByteArray([0, 1, 2, 0, 0, 1, 2, 3, 0, 1, 2])
	var anchor_x := PackedInt32Array()
	var anchor_y := PackedInt32Array()
	var heights := PackedByteArray()
	for index in range(anchors.size()):
		anchor_x.append(anchors[index].x)
		anchor_y.append(anchors[index].y)
		heights.append(0 if index < 4 else (1 if index < 8 else 2))
	var chunk_coord: Vector2i = terrain.world_cell_to_chunk(origin)
	terrain.environment_object_renderer.set_chunk_objects(
		chunk_coord, ids, variants, anchor_x, anchor_y, heights)
	terrain.environment_object_renderer.flush_pending()
	await _wait_frames(4)
	await _save("phase8a_procedural_archetype_gallery")


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_fixture_cell(Vector2i(x, y), terrain_id, elevation)


func _set_fixture_cell(pos: Vector2i, terrain_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, terrain_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_at(label: String, cell: Vector2i, zoom: float) -> void:
	await _move_camera(Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16), zoom)
	await _save(label)


func _move_camera(position: Vector2, zoom: float) -> void:
	demo.camera.position = position
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_streaming_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(3)


func _save(label: String) -> void:
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	var error: Error = root.get_texture().get_image().save_png(path)
	assert(error == OK, "Could not save %s" % path)


func _wait_until_streaming_idle(max_frames: int = 1200) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	push_warning("Streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
