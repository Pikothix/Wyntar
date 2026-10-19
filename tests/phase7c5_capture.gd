extends SceneTree
## Phase 7C.5 visual acceptance matrix at 1x and 3x. Each scenario emits a
## normal frame plus a diagnostic frame that separates geometry from shadows.

const OUTPUT_DIR := "res://screenshots"
const VIEW_SIZE := Vector2i(58, 36)
const GeometryOverlay = preload("res://tests/phase7c5_geometry_overlay.gd")

var demo
var terrain
var diagnostic_overlay
var scenarios: Array[Dictionary] = []


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
	print("PHASE7C5_CAPTURE: PASS captures=%d" % [scenarios.size() * 4])
	quit(0)


func _build_scenarios() -> void:
	var centers := [
		Vector2i(5200, 2600), Vector2i(5280, 2600), Vector2i(5360, 2600),
		Vector2i(5440, 2600), Vector2i(5520, 2600), Vector2i(5200, 2680),
		Vector2i(5280, 2680), Vector2i(5360, 2680), Vector2i(4096, 2680),
		Vector2i(5480, 2680),
	]
	for center in centers:
		_fill(center - VIEW_SIZE / 2, VIEW_SIZE, 1, 0)

	_set_cell(centers[0], 1, 1)
	scenarios.append({"label": "isolated_height_1", "center": centers[0]})
	_set_cell(centers[1], 1, 2)
	scenarios.append({"label": "isolated_height_2", "center": centers[1]})
	_set_cell(centers[2], 1, 3)
	scenarios.append({"label": "isolated_height_3", "center": centers[2]})
	_fill(centers[3] - Vector2i.ONE, Vector2i(3, 3), 1, 2)
	scenarios.append({"label": "plateau_3x3", "center": centers[3]})
	_build_diagonal(centers[4], 1, 2)
	scenarios.append({"label": "long_diagonal", "center": centers[4]})
	_build_winding(centers[5], 1, 2)
	scenarios.append({"label": "winding_convex_concave", "center": centers[5]})
	_fill(centers[6] - VIEW_SIZE / 2, VIEW_SIZE, 0, 0)
	_build_diagonal(centers[6], 1, 2)
	scenarios.append({"label": "sand_cliff_meets_water", "center": centers[6]})
	_fill(centers[7] - Vector2i(3, 2), Vector2i(7, 5), 4, 2)
	scenarios.append({"label": "stone_two_level_drop", "center": centers[7]})
	_build_diagonal(centers[8], 1, 2)
	scenarios.append({"label": "chunk_seam", "center": centers[8]})
	_build_overview(centers[9])
	scenarios.append({"label": "overview", "center": centers[9]})


func _build_diagonal(center: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(-12, 13):
		for x in range(-22, 23):
			if x <= floori(float(y) * 1.45):
				_set_cell(center + Vector2i(x, y), material_id, elevation)


func _build_winding(center: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(-11, 12):
		var edge: int = floori(sin(float(y) * 0.58) * 7.0)
		for x in range(-22, edge + 1):
			_set_cell(center + Vector2i(x, y), material_id, elevation)
	# Concave notch paired with a convex spur.
	_fill(center + Vector2i(-2, -2), Vector2i(7, 5), 1, 0)
	_fill(center + Vector2i(2, 5), Vector2i(8, 4), material_id, elevation)


func _build_overview(center: Vector2i) -> void:
	_fill(center + Vector2i(-18, -9), Vector2i(10, 8), 1, 1)
	_fill(center + Vector2i(-6, -8), Vector2i(9, 7), 3, 2)
	_fill(center + Vector2i(6, -7), Vector2i(11, 6), 4, 3)
	_build_winding(center + Vector2i(0, 8), 1, 2)


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
	await _save("phase7c5_after_%s_rendered_%s" % [label, zoom_label])
	diagnostic_overlay.configure(terrain, cell)
	diagnostic_overlay.visible = true
	diagnostic_overlay.queue_redraw()
	await _wait_frames(2)
	await _save("phase7c5_after_%s_diagnostic_%s" % [label, zoom_label])


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
	if image == null:
		push_error("Graphical renderer is required for Phase 7C.5 captures")
		quit(1)
		return
	var error: Error = image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	if error != OK:
		push_error("Could not save %s" % label)
		quit(1)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 7C.5 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
