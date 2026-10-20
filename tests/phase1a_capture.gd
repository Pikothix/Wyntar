extends SceneTree
## Phase 1A before/after visual acceptance fixtures. The same authoritative
## cells are captured with only the shared cliff material flag changed.

const OUTPUT_DIR := "res://.artifacts"
const FIXTURE_SIZE := Vector2i(46, 28)

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
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_scenarios()
	terrain._invalidate_streamed_chunks()

	for scenario in scenarios:
		for zoom in [1.0, 3.0]:
			await _move_camera(scenario.center, zoom)
			await _capture_appearance(String(scenario.label), zoom, false)
			await _capture_appearance(String(scenario.label), zoom, true)
	print("PHASE1A_CAPTURE: PASS captures=%d" % [scenarios.size() * 4])
	quit(0)


func _build_scenarios() -> void:
	var dirt := Vector2i(7200, 3600)
	var stone := Vector2i(7280, 3600)
	var shore := Vector2i(7360, 3600)
	var positive := Vector2i(4096, 3712)
	var negative := Vector2i(-4096, -2048)
	_build_material_fixture(dirt, 2, 3, false)
	_build_material_fixture(stone, 4, 3, false)
	_build_material_fixture(shore, 4, 3, true)
	_build_boundary_fixture(positive)
	_build_boundary_fixture(negative)
	scenarios = [
		{"label": "dirt_multilevel", "center": dirt},
		{"label": "stone_multilevel", "center": stone},
		{"label": "stone_shoreline_multilevel", "center": shore},
		{"label": "positive_chunk_boundary", "center": positive},
		{"label": "negative_chunk_boundary", "center": negative},
	]


func _build_material_fixture(
		center: Vector2i, material_id: int, height: int, shoreline: bool) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0 if shoreline else 3, 0)
	# A stepped southern edge exposes all stacked segments in a single view.
	for y in range(-11, 1):
		var inset: int = maxi(0, (y + 11) / 4)
		for x in range(-16 + inset, 17 - inset):
			_set_cell(center + Vector2i(x, y), material_id, height)
	_fill(center + Vector2i(-13, -7), Vector2i(8, 7), material_id, 1)
	_fill(center + Vector2i(5, -8), Vector2i(8, 8), material_id, 2)


func _build_boundary_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	# The visible face crosses x=center.x, which is an exact chunk boundary.
	for y in range(-11, 1):
		var edge: int = floori(sin(float(y) * 0.55) * 3.0)
		for x in range(-18, 19):
			if y < edge:
				_set_cell(center + Vector2i(x, y), 4, 3)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_appearance(label: String, zoom: float, procedural: bool) -> void:
	terrain.set_procedural_cliff_materials_enabled(procedural)
	await _wait_frames(3)
	var appearance: String = "after" if procedural else "before"
	var zoom_label: String = "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"
	await _save("phase1a_%s_%s_%s" % [appearance, label, zoom_label])


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
		push_error("Graphical renderer is required for Phase 1A captures")
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
	assert(false, "Phase 1A capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
