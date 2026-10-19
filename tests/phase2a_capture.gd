extends SceneTree
## Phase 2A four-mode comparison using identical logical targets. Natural
## captures retain gameplay UI/detail; fixture captures isolate geometry.

const OUTPUT_DIR := "res://screenshots"
const ObliqueProjection = preload("res://scripts/oblique_projection.gd")

const MODES: Array[Dictionary] = [
	{"label": "phase1b", "oblique": false, "edges": true, "shadows": true},
	{"label": "phase1b_no_edges", "oblique": false, "edges": false, "shadows": true},
	{"label": "phase1b_no_shadows", "oblique": false, "edges": true, "shadows": false},
	{"label": "phase2a_oblique", "oblique": true, "edges": true, "shadows": true},
]

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

	# Representative generated gameplay view; keep normal environmental detail.
	await _capture_matrix("natural_gameplay", Vector2i(16, 16))

	# Isolate a deterministic fixture spanning chunks -1, 0, and +1.
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_fixture()
	terrain._invalidate_streamed_chunks()
	await _capture_matrix("mixed_cliff_fixture", Vector2i(0, 1))

	print("PHASE2A_CAPTURE: PASS captures=16")
	quit(0)


func _capture_matrix(label: String, center: Vector2i) -> void:
	for mode in MODES:
		terrain.set_cliff_edge_overlays_visible(bool(mode.edges))
		terrain.set_cliff_shadows_visible(bool(mode.shadows))
		terrain.set_oblique_presentation_enabled(bool(mode.oblique))
		for zoom in [1.0, 3.0]:
			await _move_camera(center, zoom, bool(mode.oblique))
			await _save("phase2a_%s_%s_%s" % [
				label, String(mode.label), _zoom_label(zoom)])


func _build_fixture() -> void:
	for y in range(-24, 25):
		for x in range(-48, 49):
			_set_cell(Vector2i(x, y), 3, 0)

	# Dirt single-level formation with a convex spur.
	for y in range(-16, -3):
		for x in range(-43, -17):
			if x < -21 or y < -8:
				_set_cell(Vector2i(x, y), 2, 1)

	# Stone multilevel formation crosses both x=0 and x=32 boundaries and
	# contains a concave recess plus faces in every cardinal direction.
	for y in range(-18, 9):
		for x in range(-14, 43):
			if y < 2 + roundi(sin(float(x) * 0.24) * 4.0):
				var height := 3 if y < -7 else 2
				_set_cell(Vector2i(x, y), 4, height)
	for y in range(-10, -2):
		for x in range(5, 15):
			_set_cell(Vector2i(x, y), 3, 0)

	# Shoreline cliff on the lower/right edge.
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


func _move_camera(cell: Vector2i, zoom: float, oblique: bool) -> void:
	if oblique:
		demo.camera.position = ObliqueProjection.project_cell_center(
			cell, terrain.get_world_surface_elevation(cell))
	else:
		demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Graphical renderer is required for Phase 2A captures")
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
	assert(false, "Phase 2A capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
