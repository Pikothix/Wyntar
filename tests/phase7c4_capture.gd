extends SceneTree
## Matched Phase 7C.4 geometry showcase at 1x and 3x. Pass `before` or
## `after` as the first user argument to preserve comparable evidence.

const OUTPUT_DIR := "res://.artifacts"
const VIEW_SIZE := Vector2i(64, 40)
const GeometryOverlay = preload("res://tests/phase7c4_geometry_overlay.gd")

var demo
var terrain
var capture_prefix: String = "after"
var scenarios: Array[Dictionary] = []
var diagnostic_overlay


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		capture_prefix = args[0].validate_filename()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	diagnostic_overlay = GeometryOverlay.new()
	diagnostic_overlay.z_index = 100
	terrain.add_child(diagnostic_overlay)
	_build_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		for zoom in [1.0, 3.0]:
			await _capture_pair(String(scenario.label), scenario.center, zoom)
	print("PHASE7C4_CAPTURE: PASS prefix=%s captures=%d" % [
		capture_prefix, scenarios.size() * 4])
	quit(0)


func _build_scenarios() -> void:
	var centers: Array[Vector2i] = []
	for row in range(2):
		for column in range(7):
			centers.append(Vector2i(3600 + column * 88, 2200 + row * 72))
	for center in centers:
		_fill(center - VIEW_SIZE / 2, VIEW_SIZE, 1, 0)

	_set_cell(centers[0], 1, 1)
	scenarios.append({"label": "isolated_height_1", "center": centers[0]})
	_set_cell(centers[1], 1, 2)
	scenarios.append({"label": "isolated_height_2", "center": centers[1]})
	_set_cell(centers[2], 1, 3)
	scenarios.append({"label": "isolated_height_3", "center": centers[2]})
	_fill(centers[3] - Vector2i.ONE, Vector2i(3, 3), 1, 1)
	scenarios.append({"label": "plateau_3x3_height_1", "center": centers[3]})
	_fill(centers[4] - Vector2i.ONE, Vector2i(3, 3), 1, 2)
	scenarios.append({"label": "plateau_3x3_height_2", "center": centers[4]})
	_fill(centers[5] - Vector2i(4, 3), Vector2i(9, 6), 1, 1)
	_fill(centers[5] - Vector2i(2, 2), Vector2i(5, 4), 1, 3)
	scenarios.append({"label": "drop_height_3_to_1", "center": centers[5]})
	_build_irregular(centers[6], 1, 2)
	scenarios.append({"label": "irregular_plateau", "center": centers[6]})

	# Water matrix uses a clean sea-level lake around each shape.
	for index in range(7, 14):
		_fill(centers[index] - VIEW_SIZE / 2, VIEW_SIZE, 0, 0)
	_set_cell(centers[7], 0, 1)
	scenarios.append({"label": "water_island_1x1", "center": centers[7]})
	_fill(centers[8] - Vector2i.ONE, Vector2i(3, 3), 0, 1)
	scenarios.append({"label": "water_island_3x3", "center": centers[8]})
	_fill(centers[9] - Vector2i(4, 3), Vector2i(9, 6), 1, 1)
	_fill(centers[9] - Vector2i(2, 2), Vector2i(5, 4), 4, 2)
	scenarios.append({"label": "water_island_two_level", "center": centers[9]})
	_fill(centers[10] - Vector2i(16, 12), Vector2i(32, 8), 1, 1)
	_fill(centers[10] - Vector2i(2, 5), Vector2i(5, 12), 1, 1)
	scenarios.append({"label": "raised_peninsula", "center": centers[10]})
	_fill(centers[11] - Vector2i(16, 12), Vector2i(32, 12), 3, 2)
	scenarios.append({"label": "cliff_meets_water", "center": centers[11]})
	var seam_center := Vector2i(4096, centers[12].y)
	_fill(seam_center - VIEW_SIZE / 2, VIEW_SIZE, 0, 0)
	for y in range(-12, 13):
		for x in range(-20, 5 + floori(sin(float(y) * 0.5) * 4.0)):
			_set_cell(seam_center + Vector2i(x, y), 1, 2)
	scenarios.append({"label": "shoreline_chunk_boundary", "center": seam_center})
	_build_irregular(centers[13], 1, 2)
	scenarios.append({"label": "water_irregular_plateau", "center": centers[13]})


func _build_irregular(center: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(-7, 8):
		for x in range(-11, 12):
			if float(x * x) / 121.0 + float(y * y) / 49.0 <= 1.0:
				if not (x > 5 and y < -1) and not (x < -6 and y > 2):
					_set_cell(center + Vector2i(x, y), material_id, elevation)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_pair(label: String, cell: Vector2i, zoom: float) -> void:
	await _move_camera(cell, zoom)
	var zoom_label: String = "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"
	diagnostic_overlay.visible = false
	await _wait_frames(2)
	await _save("phase7c4_%s_%s_rendered_%s" % [capture_prefix, label, zoom_label])
	diagnostic_overlay.configure(terrain, cell)
	diagnostic_overlay.visible = true
	diagnostic_overlay.queue_redraw()
	await _wait_frames(2)
	await _save("phase7c4_%s_%s_diagnostic_%s" % [capture_prefix, label, zoom_label])


func _move_camera(cell: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(3)


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	assert(image != null, "Graphical renderer is required for Phase 7C.4 captures")
	var error: Error = image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	assert(error == OK, "Could not save %s" % label)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 7C.4 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
