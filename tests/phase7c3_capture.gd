extends SceneTree
## Deterministic rendered/F6 evidence for Phase 7C.3 island editing and cliffs.

const OUTPUT_DIR := "res://.artifacts"
const VIEW_SIZE := Vector2i(80, 48)
const EditorController = preload("res://scripts/world_editor_controller.gd")

var demo
var terrain
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
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		for zoom in [0.5, 1.0, 3.0]:
			await _capture_pair(String(scenario.label), scenario.center, zoom)
	print("PHASE7C3_GRAPHICAL_CAPTURE: PASS captures=%d" % (scenarios.size() * 6))
	quit(0)


func _build_scenarios() -> void:
	var centers: Array[Vector2i] = [
		Vector2i(2200, 1600), Vector2i(2304, 1600),
		Vector2i(2408, 1600), Vector2i(2512, 1600),
		Vector2i(2200, 1680), Vector2i(2304, 1680),
		Vector2i(2408, 1680), Vector2i(2512, 1680),
	]
	for center in centers:
		_fill(center - VIEW_SIZE / 2, VIEW_SIZE, 0, 0)

	scenarios.append({"label": "empty_lake", "center": centers[0]})

	# Raising water-owned ground alone exposes the derived sand substrate.
	_set_cell(centers[1], 0, 1)
	scenarios.append({"label": "one_cell_island", "center": centers[1]})

	_fill(centers[2] - Vector2i.ONE, Vector2i(3, 3), 0, 1)
	scenarios.append({"label": "three_by_three_island", "center": centers[2]})

	for y in range(-8, 9):
		for x in range(-13, 14):
			if float(x * x) / 169.0 + float(y * y) / 64.0 <= 1.0:
				if not (x > 6 and y < -2) and not (x < -8 and y > 2):
					_set_cell(centers[3] + Vector2i(x, y), 1, 1)
	scenarios.append({"label": "irregular_island", "center": centers[3]})

	_fill(centers[4] - Vector2i(10, 7), Vector2i(21, 14), 1, 1)
	_fill(centers[4] - Vector2i(5, 4), Vector2i(11, 7), 4, 2)
	scenarios.append({"label": "two_level_drop", "center": centers[4]})

	_fill(centers[5] - Vector2i(32, 16), Vector2i(20, 32), 3, 3)
	_fill(centers[5] - Vector2i(10, 5), Vector2i(13, 10), 1, 1)
	scenarios.append({"label": "island_beside_cliff", "center": centers[5]})

	for y in range(-13, 14):
		for x in range(-20, 21):
			var coast: int = -4 + floori(sin(float(y) * 0.55) * 5.0)
			if x <= coast:
				_set_cell(centers[6] + Vector2i(x, y), 3, 2 if x < coast - 5 else 1)
	scenarios.append({"label": "irregular_shoreline_cliff", "center": centers[6]})

	# Exercise the real command path: lower below the liquid plane, then restore
	# both elevation commands with undo before capturing the restored island.
	var restored: Vector2i = centers[7]
	_fill(restored - Vector2i.ONE, Vector2i(3, 3), 1, 2)
	demo.editor.edit_mode = EditorController.EditMode.ELEVATION
	demo.editor.brush_shape = EditorController.BrushShape.SQUARE
	demo.editor.brush_size = 3
	demo.editor.elevation_tool = EditorController.ElevationTool.LOWER
	demo.editor.begin_stroke(restored)
	demo.editor.end_stroke()
	demo.editor.begin_stroke(restored)
	demo.editor.end_stroke()
	demo.editor.undo()
	demo.editor.undo()
	scenarios.append({"label": "lowered_then_undo_restored", "center": restored})


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_pair(label: String, cell: Vector2i, zoom: float) -> void:
	await _move_camera(cell, zoom)
	var zoom_label: String = (
		"0_5x" if is_equal_approx(zoom, 0.5)
		else ("1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"))
	demo.cursor.visible = false
	demo.cursor.show_elevation_overlay = false
	await _wait_frames(2)
	await _save("phase7c3_%s_rendered_%s" % [label, zoom_label])
	demo.cursor.visible = true
	demo.cursor.enabled = true
	demo.cursor.show_elevation_overlay = true
	demo.cursor.queue_redraw()
	await _wait_frames(2)
	await _save("phase7c3_%s_f6_%s" % [label, zoom_label])
	demo.cursor.show_elevation_overlay = false


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
	assert(image != null, "Graphical renderer is required for Phase 7C.3 captures")
	var error: Error = image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	assert(error == OK, "Could not save %s" % label)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 7C.3 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
