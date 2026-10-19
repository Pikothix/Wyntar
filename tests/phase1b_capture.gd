extends SceneTree
## Phase 1B comparison matrix. "Before" is the retained Phase 1A TileMap
## geometry; "after" enables the experimental chunk-batched cliff mesh.

const OUTPUT_DIR := "res://screenshots"
const FIXTURE_SIZE := Vector2i(48, 30)

var demo
var terrain
var scenarios: Array[Dictionary] = []
var applied_edit_scenarios: Dictionary = {}


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
			if scenario.has("edit_cell") and not applied_edit_scenarios.has(scenario.label):
				var edits: Array[Dictionary] = [{
					"cell": scenario.edit_cell, "kind": "material",
					"state": {"has_override": true, "value": 2},
				}, {
					"cell": scenario.edit_cell, "kind": "elevation",
					"state": {"has_override": true, "value": 2},
				}]
				terrain.apply_world_edit_states(edits)
				await _wait_until_idle()
				applied_edit_scenarios[scenario.label] = true
			await _capture_mode(String(scenario.label), zoom, false)
			await _capture_mode(String(scenario.label), zoom, true)
	print("PHASE1B_CAPTURE: PASS captures=%d" % [scenarios.size() * 4])
	quit(0)


func _build_scenarios() -> void:
	var dirt := Vector2i(9000, 4500)
	var stone := Vector2i(9080, 4500)
	var shore := Vector2i(9160, 4500)
	var convex := Vector2i(9000, 4580)
	var concave := Vector2i(9080, 4580)
	var editing := Vector2i(9160, 4580)
	var positive := Vector2i(4096, 4608)
	var negative := Vector2i(-4096, -3072)
	_build_straight(dirt, 2, 1, false)
	_build_straight(stone, 4, 3, false)
	_build_straight(shore, 4, 3, true)
	_build_corner(convex, false)
	_build_corner(concave, true)
	_build_straight(editing, 2, 3, false)
	_build_boundary(positive)
	_build_boundary(negative)
	scenarios = [
		{"label": "dirt_single_straight", "center": dirt},
		{"label": "stone_multilevel_straight", "center": stone},
		{"label": "shoreline_multilevel", "center": shore},
		{"label": "convex_corner", "center": convex},
		{"label": "concave_corner", "center": concave},
		{"label": "editing_rebuild", "center": editing,
			"edit_cell": editing},
		{"label": "positive_chunk_boundary", "center": positive + Vector2i(0, -4)},
		{"label": "negative_chunk_boundary", "center": negative + Vector2i(0, -4)},
	]


func _build_straight(
		center: Vector2i, material_id: int, height: int, shoreline: bool) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0 if shoreline else 3, 0)
	_fill(center + Vector2i(-19, -11), Vector2i(38, 11), material_id, height)


func _build_corner(center: Vector2i, concave: bool) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-17, -12), Vector2i(34, 12), 4, 3)
	if concave:
		_fill(center + Vector2i(-5, -7), Vector2i(10, 8), 3, 0)
	else:
		_fill(center + Vector2i(-6, 0), Vector2i(12, 7), 4, 3)


func _build_boundary(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-12, 1):
		var edge: int = floori(sin(float(y) * 0.48) * 4.0)
		for x in range(-20, 21):
			if y < edge:
				_set_cell(center + Vector2i(x, y), 4, 3)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_mode(label: String, zoom: float, organic: bool) -> void:
	terrain.set_organic_cliff_geometry_enabled(organic)
	await _wait_frames(3)
	var mode: String = "after" if organic else "before"
	var zoom_label: String = "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"
	await _save("phase1b_%s_%s_%s" % [mode, label, zoom_label])


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
		push_error("Graphical renderer is required for Phase 1B captures")
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
	assert(false, "Phase 1B capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
