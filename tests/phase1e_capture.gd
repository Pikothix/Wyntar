extends SceneTree
## Phase 1E A/B matrix. Both modes use unified Phase 1D components; only the
## return silhouette algorithm changes, so terrain data and framing match.

const OUTPUT_DIR := "res://screenshots"
const FIXTURE_SIZE := Vector2i(48, 30)

var demo
var terrain
var scenarios: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)

	# Capture an unmodified gameplay view before fixture-only generation flags
	# are disabled, so the comparison is not restricted to favourable layouts.
	await _capture_scenario({"label": "natural_gameplay", "center": Vector2i.ZERO})
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_scenario(scenario)
	print("PHASE1E_CAPTURE: PASS captures=%d" % [(scenarios.size() + 1) * 4])
	quit(0)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in [1.0, 3.0]:
		await _move_camera(scenario.center, zoom)
		await _capture_mode(String(scenario.label), zoom, false)
		await _capture_mode(String(scenario.label), zoom, true)


func _build_scenarios() -> void:
	var dirt := Vector2i(13200, 6600)
	var returns := Vector2i(13280, 6600)
	var corners := Vector2i(13360, 6600)
	var shore := Vector2i(13440, 6600)
	var levels := Vector2i(13520, 6600)
	var positive := Vector2i(4096, 4608)
	var negative := Vector2i(-4096, -3072)
	_build_dirt_multilevel(dirt)
	_build_return_diagnostic(returns)
	_build_corners(corners)
	_build_shoreline(shore)
	_build_multi_elevation(levels)
	_build_boundary(positive, 4)
	_build_boundary(negative, 2)
	scenarios = [
		{"label": "dirt_multilevel_phase1a", "center": dirt},
		{"label": "east_west_return_diagnostic", "center": returns},
		{"label": "convex_concave_stone", "center": corners},
		{"label": "shoreline_cliffs", "center": shore},
		{"label": "multi_elevation_formation", "center": levels},
		{"label": "positive_chunk_boundary", "center": positive},
		{"label": "negative_chunk_boundary", "center": negative},
	]


func _build_dirt_multilevel(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-19, -11), Vector2i(38, 19), 2, 3)
	_fill(center + Vector2i(-7, -5), Vector2i(14, 8), 2, 1)
	_fill(center + Vector2i(-13, 8), Vector2i(12, 5), 2, 2)


func _build_return_diagnostic(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-15, -12), Vector2i(30, 8), 2, 3)
	_fill(center + Vector2i(-11, -4), Vector2i(22, 8), 2, 3)
	_fill(center + Vector2i(-7, 4), Vector2i(14, 9), 2, 3)
	# One side-only notch exposes a long return before it meets a south wall.
	_fill(center + Vector2i(-2, -8), Vector2i(4, 16), 3, 0)


func _build_corners(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-19, -11), Vector2i(16, 17), 4, 3)
	_fill(center + Vector2i(-3, -11), Vector2i(20, 10), 4, 3)
	_fill(center + Vector2i(5, -1), Vector2i(12, 9), 4, 3)
	_fill(center + Vector2i(-14, -6), Vector2i(7, 7), 3, 0)


func _build_shoreline(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	_fill(center + Vector2i(-19, -11), Vector2i(38, 18), 2, 2)
	_fill(center + Vector2i(-12, -8), Vector2i(24, 12), 4, 3)
	_fill(center + Vector2i(-4, -3), Vector2i(8, 5), 0, 0)


func _build_multi_elevation(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-20, -11), Vector2i(40, 20), 2, 1)
	_fill(center + Vector2i(-15, -8), Vector2i(30, 14), 2, 2)
	_fill(center + Vector2i(-9, -5), Vector2i(18, 8), 4, 3)


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


func _capture_mode(label: String, zoom: float, refined: bool) -> void:
	terrain.set_refined_cliff_silhouettes_enabled(refined)
	await _wait_frames(3)
	var mode: String = "refined" if refined else "phase1d"
	var zoom_label: String = "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"
	await _save("phase1e_%s_%s_%s" % [mode, label, zoom_label])


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
		push_error("Graphical renderer is required for Phase 1E captures")
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
	assert(false, "Phase 1E capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
