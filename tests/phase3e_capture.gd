extends "res://tests/phase3b_capture.gd"
## Matched Phase 3D/3E evidence with the requested 2.31x regression view.

const PHASE3E_ZOOMS: Array[float] = [0.5, 1.0, 2.31, 3.0]


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["baseline", "prototype"]:
		push_error("Phase 3E capture requires user argument: baseline or prototype")
		quit(1)
		return
	capture_label = String(arguments[0])
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(capture_label == "prototype")
	if arguments.size() > 2 and String(arguments[2]) == "faces_only":
		terrain.set_cliff_edge_overlays_visible(false)
		terrain.set_cliff_shadows_visible(false)
	var scenario_filter: String = String(arguments[1]) if arguments.size() > 1 else ""
	_build_phase3e_scenarios(scenario_filter)
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_scenario(scenario)
	# Filtered runs are fresh-process diagnostics and must not replace the full
	# matched-matrix manifest with a four-image subset.
	if arguments.size() <= 1:
		_write_manifest()
	print("PHASE3E_CAPTURE: PASS label=%s captures=%d" % [capture_label, captures.size()])
	quit(0)


func _build_phase3e_scenarios(scenario_filter: String = "") -> void:
	var origin := Vector2i(20480, 10240)
	var centers := [
		origin, origin + Vector2i(96, 0), origin + Vector2i(192, 0),
		origin + Vector2i(288, 0), origin + Vector2i(384, 0),
		origin + Vector2i(480, 0), Vector2i(32, -20480),
		Vector2i(-32, -20480), origin + Vector2i(576, 0)]
	if scenario_filter in ["", "long_diagonal_multichunk"]:
		_build_diagonal_fixture(centers[0], 4)
		_add_scenario("long_diagonal_multichunk", centers[0],
			"Long stone diagonal spanning multiple streamed chunks.")
	if scenario_filter in ["", "s_winding_boundary"]:
		_build_winding_fixture(centers[1])
		_add_scenario("s_winding_boundary", centers[1],
			"S-shaped dirt boundary with alternating turns.")
	if scenario_filter in ["", "convex_concave_corners"]:
		_build_corner_fixture(centers[2])
		_add_scenario("convex_concave_corners", centers[2],
			"Explicit convex spur and concave notch.")
	if scenario_filter in ["", "isolated_one_two_three"]:
		_build_isolated_fixture(centers[3])
		_add_scenario("isolated_one_two_three", centers[3],
			"Isolated one-, two-, and three-level formations.")
	if scenario_filter in ["", "mixed_height_adjacent"]:
		_build_mixed_height_fixture(centers[4])
		_add_scenario("mixed_height_adjacent", centers[4],
			"Adjacent height-one, height-two, and height-three terraces.")
	if scenario_filter in ["", "dirt_stone_transition"]:
		_build_dirt_stone_fixture(centers[5])
		_add_scenario("dirt_stone_transition", centers[5],
			"Unified contour crossing a dirt/stone material transition.")
	if scenario_filter in ["", "user_diagonal_grass_reproduction"]:
		_build_user_diagonal_fixture(centers[8])
		_add_scenario("user_diagonal_grass_reproduction", centers[8],
			"Prominent grass escarpment matching the reported 2.31x staircase case.")
	if scenario_filter in ["", "positive_chunk_seam"]:
		_build_signed_seam_fixture(centers[6], 32)
		_add_scenario("positive_chunk_seam", centers[6],
			"Diagonal grass cliff crossing positive chunk seams.")
	if scenario_filter in ["", "negative_chunk_seam"]:
		_build_signed_seam_fixture(centers[7], -32)
		_add_scenario("negative_chunk_seam", centers[7],
			"Diagonal grass cliff crossing negative chunk seams.")


func _add_scenario(label: String, center: Vector2i, description: String) -> void:
	scenarios.append({
		"label": label, "center": center, "kind": "controlled",
		"description": description,
	})


func _build_corner_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-22, -13), Vector2i(35, 23), 3, 2)
	_fill(center + Vector2i(13, -4), Vector2i(10, 8), 3, 2)
	_fill(center + Vector2i(-7, 3), Vector2i(10, 8), 3, 0)


func _build_mixed_height_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-13, 14):
		var edge: int = floori(float(y) * 0.72)
		for x in range(-26, edge + 1):
			var height: int = 1 if y < -4 else (2 if y < 6 else 3)
			_set_cell(center + Vector2i(x, y), 3, height)


func _build_dirt_stone_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-14, 15):
		var edge: int = floori(sin(float(y) * 0.22) * 5.0)
		for x in range(-26, edge + 1):
			_set_cell(center + Vector2i(x, y), 2 if y < 0 else 4, 2)


func _build_signed_seam_fixture(center: Vector2i, seam_x: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-15, 16):
		for x in range(-27, 28):
			if x <= floori(float(y) * 1.25):
				_set_cell(center + Vector2i(x, y), 3, 2)
	assert(center.x == seam_x)


func _build_user_diagonal_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-16, 16):
		var edge: int = floori(float(y) * 0.95 + sin(float(y) * 0.31) * 2.0)
		for x in range(-27, edge + 1):
			_set_cell(center + Vector2i(x, y), 3, 1)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in PHASE3E_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "phase3e_%s_%s_%s.png" % [
			capture_label, String(scenario.label), _zoom_label(zoom)]
		await _save(file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": String(scenario.label),
			"camera_cell": _vector_to_array(scenario.center),
			"camera_world": _vector_to_array(demo.camera.position),
			"zoom": zoom,
		})


func _move_camera(cell: Vector2i, zoom: float) -> void:
	await super._move_camera(cell, zoom)
	# Phase 1G retires replaced chunk subtrees over several frames. Waiting only
	# for build jobs can photograph old Phase 3D components over the new contour.
	for _frame in range(2400):
		if terrain.get_pending_chunk_retirement_count() == 0:
			await _wait_frames(4)
			return
		await process_frame
	assert(false, "Phase 3E capture chunk retirement did not become idle")


func _write_manifest() -> void:
	var manifest := {
		"phase": "3E", "capture_label": capture_label,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(), "viewport": [1280, 720],
		"world_seed": terrain.world_seed, "zooms": PHASE3E_ZOOMS,
		"phase3d_baseline": capture_label == "baseline",
		"unified_contours": capture_label == "prototype",
		"scenarios": scenarios, "captures": captures,
	}
	var path := "%s/phase3e_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _zoom_label(zoom: float) -> String:
	if is_equal_approx(zoom, 0.5):
		return "0_5x"
	if is_equal_approx(zoom, 1.0):
		return "1_0x"
	if is_equal_approx(zoom, 2.31):
		return "2_31x"
	return "3_0x"
