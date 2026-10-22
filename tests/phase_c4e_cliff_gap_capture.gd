extends "res://tests/phase3b_capture.gd"
## Deterministic Phase C4E cliff-gap comparison matrix. The harness owns only
## presentation fixtures; authoritative generation and runtime rendering stay
## in their established systems.

const C4E_ZOOMS: Array[float] = [1.0, 1.5, 2.0]

var comparisons: Array[String] = []
var streaming_revisit_pixel_exact: bool = false


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["before", "after"]:
		push_error("Phase C4E capture requires user argument: before or after")
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
	terrain.set_unified_cliff_contours_enabled(true)
	terrain.set_directional_cliff_projection_enabled(true)
	terrain.set_cliff_height_profile(2)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_c4e_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_scenario(scenario)
	if capture_label == "after":
		streaming_revisit_pixel_exact = await _verify_streaming_revisit(centers_for_seam())
	_write_manifest()
	print("PHASE_C4E_CAPTURE: PASS label=%s captures=%d" % [capture_label, captures.size()])
	quit(0)


func _build_c4e_scenarios() -> void:
	var origin := Vector2i(24576, 12288)
	var centers := [
		origin, origin + Vector2i(96, 0), origin + Vector2i(192, 0),
		origin + Vector2i(288, 0), origin + Vector2i(384, 0),
		origin + Vector2i(480, 0), origin + Vector2i(576, 0),
		Vector2i(32, -24576),
	]
	_build_cardinal_fixture(centers[0])
	_add_scenario("straight_cardinal_edges", centers[0],
		"Straight north, south, east, and west height transitions.")
	_build_corner_fixture(centers[1])
	_add_scenario("convex_concave_corners", centers[1],
		"Convex spur and concave notch on one raised surface.")
	_build_diagonal_fixture(centers[2], 4)
	_add_scenario("diagonal_organic_boundary", centers[2],
		"Long diagonal and organic marching-square transitions.")
	_build_single_cell_fixture(centers[3])
	_add_scenario("isolated_single_cell", centers[3],
		"One isolated raised cell surrounded by ground terrain.")
	_build_plateau_fixture(centers[4])
	_add_scenario("multi_cell_plateau", centers[4],
		"Broad raised plateau with uninterrupted cardinal sides.")
	_build_multilevel_fixture(centers[5])
	_add_scenario("multi_level_transitions", centers[5],
		"Adjacent one-, two-, and three-level terraces.")
	_build_water_contact_fixture(centers[6])
	_add_scenario("water_contact", centers[6],
		"Raised dirt and stone faces meeting water.")
	_build_signed_seam_fixture(centers[7], 32)
	_add_scenario("chunk_seam", centers[7],
		"Diagonal grass cliff crossing positive and negative Y chunk seams.")


func _add_scenario(label: String, center: Vector2i, description: String) -> void:
	scenarios.append({
		"label": label,
		"center": center,
		"kind": "controlled",
		"description": description,
	})


func _build_cardinal_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-12, -8), Vector2i(24, 16), 4, 2)


func _build_corner_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-18, -11), Vector2i(32, 21), 2, 2)
	_fill(center + Vector2i(14, -3), Vector2i(8, 7), 2, 2)
	_fill(center + Vector2i(-5, 3), Vector2i(9, 7), 3, 0)


func _build_single_cell_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_set_cell(center, 4, 2)


func _build_plateau_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-21, -11), Vector2i(42, 22), 3, 2)


func _build_multilevel_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-23, -12), Vector2i(46, 24), 2, 1)
	_fill(center + Vector2i(-15, -8), Vector2i(30, 16), 4, 2)
	_fill(center + Vector2i(-7, -4), Vector2i(14, 8), 5, 3)


func _build_water_contact_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	_fill(center + Vector2i(-24, -14), Vector2i(23, 22), 2, 2)
	_fill(center + Vector2i(1, -14), Vector2i(23, 22), 4, 3)


func _build_signed_seam_fixture(center: Vector2i, seam_x: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-15, 16):
		for x in range(-27, 28):
			if x <= floori(float(y) * 1.25):
				_set_cell(center + Vector2i(x, y), 3, 2)
	assert(center.x == seam_x)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in C4E_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "c4e_%s_%s_%s.png" % [
			capture_label, String(scenario.label), _zoom_label(zoom)]
		await _save(file_name)
		if capture_label == "after":
			_save_comparison(String(scenario.label), _zoom_label(zoom), file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": String(scenario.label),
			"camera_cell": _vector_to_array(scenario.center),
			"camera_world": _vector_to_array(demo.camera.position),
			"zoom": zoom,
		})


func _save_comparison(scenario: String, zoom_label: String, after_name: String) -> void:
	var before_path := "%s/c4e_before_%s_%s.png" % [OUTPUT_DIR, scenario, zoom_label]
	var before: Image = Image.load_from_file(before_path)
	var after: Image = Image.load_from_file("%s/%s" % [OUTPUT_DIR, after_name])
	assert(before != null and after != null, "Matched C4E captures must exist")
	var combined := Image.create(
		before.get_width() * 2, before.get_height(), false, before.get_format())
	combined.blit_rect(before, before.get_used_rect(), Vector2i.ZERO)
	combined.blit_rect(after, after.get_used_rect(), Vector2i(before.get_width(), 0))
	var path := "%s/c4e_compare_%s_%s.png" % [OUTPUT_DIR, scenario, zoom_label]
	assert(combined.save_png(path) == OK, "Could not save C4E comparison")
	comparisons.append(path)


func centers_for_seam() -> Vector2i:
	return Vector2i(32, -24576)


func _verify_streaming_revisit(center: Vector2i) -> bool:
	var reference: Image = Image.load_from_file(
		"%s/c4e_after_chunk_seam_1_5x.png" % OUTPUT_DIR)
	await _move_camera(center + Vector2i(160, 96), 1.5)
	await _move_camera(center, 1.5)
	var revisit: Image = root.get_texture().get_image()
	var matches: bool = hash(reference.get_data()) == hash(revisit.get_data())
	assert(matches, "C4E output changed after streaming away and revisiting")
	return matches


func _move_camera(cell: Vector2i, zoom: float) -> void:
	await super._move_camera(cell, zoom)
	for _frame in range(2400):
		if terrain.get_pending_chunk_retirement_count() == 0:
			await _wait_frames(4)
			return
		await process_frame
	assert(false, "Phase C4E capture chunk retirement did not become idle")


func _write_manifest() -> void:
	var manifest := {
		"phase": "C4E",
		"capture_label": capture_label,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"zooms": C4E_ZOOMS,
		"rendering_flags": {
			"unified_contours": terrain.is_unified_cliff_contours_enabled(),
			"directional_projection": terrain.directional_cliff_projection_enabled,
			"cliff_height_step": terrain.get_cliff_height_step(),
			"edge_overlays": terrain.cliff_edge_overlays_visible,
			"shadows": terrain.cliff_shadows_visible,
		},
		"scenarios": scenarios,
		"captures": captures,
		"comparisons": comparisons,
		"streaming_revisit_pixel_exact": streaming_revisit_pixel_exact,
	}
	var path := "%s/c4e_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _zoom_label(zoom: float) -> String:
	if is_equal_approx(zoom, 1.0):
		return "1_0x"
	if is_equal_approx(zoom, 1.5):
		return "1_5x"
	return "2_0x"
