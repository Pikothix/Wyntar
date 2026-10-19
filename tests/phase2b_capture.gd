extends SceneTree
## Identical-seed Phase 2A/2B comparisons for natural gameplay terrain and a
## deterministic multi-material, multi-chunk geometry fixture.

const OUTPUT_DIR := "res://screenshots"
const ObliqueProjection = preload("res://scripts/oblique_projection.gd")

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	terrain.set_oblique_presentation_enabled(true)
	await _capture_comparison("natural_gameplay", Vector2i(16, 16))

	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _capture_comparison("mixed_cliff_fixture", Vector2i(0, 1))
	print("PHASE2B_CAPTURE: PASS captures=8")
	quit(0)


func _capture_comparison(label: String, center: Vector2i) -> void:
	for refined in [false, true]:
		terrain.set_organic_oblique_refinement_enabled(refined)
		var mode := "phase2b_after" if refined else "phase2a_before"
		for zoom in [1.0, 3.0]:
			await _move_camera(center, zoom)
			await _save("phase2b_%s_%s_%s" % [label, mode, _zoom_label(zoom)])


func _build_fixture() -> void:
	for y in range(-24, 25):
		for x in range(-48, 49):
			_set_cell(Vector2i(x, y), 3, 0)
	for y in range(-16, -3):
		for x in range(-43, -17):
			if x < -21 or y < -8:
				_set_cell(Vector2i(x, y), 2, 1)
	for y in range(-18, 9):
		for x in range(-14, 43):
			if y < 2 + roundi(sin(float(x) * 0.24) * 4.0):
				_set_cell(Vector2i(x, y), 4, 3 if y < -7 else 2)
	for y in range(-10, -2):
		for x in range(5, 15):
			_set_cell(Vector2i(x, y), 3, 0)
	for y in range(8, 25):
		for x in range(13, 49):
			_set_cell(Vector2i(x, y), 0, 0)
	for y in range(3, 15):
		for x in range(18, 42):
			if y < 12 - roundi(cos(float(x) * 0.3) * 3.0):
				_set_cell(Vector2i(x, y), 4, 2)


func _set_cell(cell: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(cell, material_id)
	terrain.world.set_elevation_override(cell, elevation)


func _move_camera(cell: Vector2i, zoom: float) -> void:
	demo.camera.position = ObliqueProjection.project_cell_center(
		cell, terrain.get_world_surface_elevation(cell))
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Graphical renderer is required for Phase 2B captures")
		quit(1)
		return
	var error: Error = image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	if error != OK:
		push_error("Could not save %s" % label)
		quit(1)


func _zoom_label(zoom: float) -> String:
	return "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 2B capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
