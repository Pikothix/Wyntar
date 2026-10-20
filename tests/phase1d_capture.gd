extends SceneTree
## Phase 1D visual matrix. Both modes keep Phase 1B faces active; "before"
## retains legacy edge/shadow atlases and "after" uses unified mesh batches.

const OUTPUT_DIR := "res://.artifacts"
const FIXTURE_SIZE := Vector2i(48, 30)

var demo
var terrain
var scenarios: Array[Dictionary] = []
var edited: bool = false


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
	terrain.set_organic_cliff_geometry_enabled(true)
	_build_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		for zoom in [1.0, 3.0]:
			await _move_camera(scenario.center, zoom)
			if bool(scenario.get("edit", false)) and not edited:
				var edits: Array[Dictionary] = [{
					"cell": scenario.center + Vector2i(2, -2),
					"kind": "elevation",
					"state": {"has_override": true, "value": 1},
				}]
				terrain.apply_world_edit_states(edits)
				await _wait_until_idle()
				edited = true
			await _capture_mode(String(scenario.label), zoom, false)
			await _capture_mode(String(scenario.label), zoom, true)
	print("PHASE1D_CAPTURE: PASS captures=%d" % [scenarios.size() * 4])
	quit(0)


func _build_scenarios() -> void:
	var dirt := Vector2i(12000, 6000)
	var stone := Vector2i(12080, 6000)
	var shore := Vector2i(12160, 6000)
	var positive := Vector2i(4096, 4608)
	var negative := Vector2i(-4096, -3072)
	var editing := Vector2i(12240, 6000)
	_build_dirt_multilevel(dirt)
	_build_stone_returns(stone)
	_build_shoreline(shore)
	_build_boundary(positive, 4)
	_build_boundary(negative, 2)
	_build_dirt_multilevel(editing)
	scenarios = [
		{"label": "natural_gameplay", "center": Vector2i.ZERO},
		{"label": "dirt_multilevel_recess", "center": dirt},
		{"label": "stone_corners_returns", "center": stone},
		{"label": "shoreline_cliffs", "center": shore},
		{"label": "positive_chunk_boundary", "center": positive},
		{"label": "negative_chunk_boundary", "center": negative},
		{"label": "editing_rebuild", "center": editing, "edit": true},
	]


func _build_dirt_multilevel(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-19, -11), Vector2i(38, 19), 2, 3)
	_fill(center + Vector2i(-7, -5), Vector2i(14, 8), 2, 1)
	_fill(center + Vector2i(-13, 8), Vector2i(12, 5), 2, 2)


func _build_stone_returns(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-18, -11), Vector2i(36, 14), 4, 3)
	_fill(center + Vector2i(-18, 3), Vector2i(13, 8), 4, 2)
	_fill(center + Vector2i(5, -4), Vector2i(13, 11), 4, 3)
	_fill(center + Vector2i(-4, -5), Vector2i(9, 7), 3, 0)


func _build_shoreline(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	_fill(center + Vector2i(-19, -11), Vector2i(38, 17), 2, 2)
	_fill(center + Vector2i(-12, -8), Vector2i(24, 11), 4, 3)
	_fill(center + Vector2i(-4, -3), Vector2i(8, 5), 0, 0)


func _build_boundary(center: Vector2i, material_id: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-12, 10):
		var edge: int = floori(sin(float(y) * 0.48) * 5.0)
		for x in range(-21, 22):
			if x < edge:
				_set_cell(center + Vector2i(x, y), material_id, 3 if y < 2 else 2)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_mode(label: String, zoom: float, unified: bool) -> void:
	terrain.set_unified_cliff_components_enabled(unified)
	await _wait_frames(3)
	var mode: String = "after" if unified else "before"
	var zoom_label: String = "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"
	await _save("phase1d_%s_%s_%s" % [mode, label, zoom_label])


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
		push_error("Graphical renderer is required for Phase 1D captures")
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
	assert(false, "Phase 1D capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
