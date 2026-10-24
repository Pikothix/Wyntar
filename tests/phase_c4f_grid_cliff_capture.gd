extends "res://tests/phase_c4e_cliff_gap_capture.gd"
## Matched C4E.1/C4F visual matrix. Fixtures mutate only the test-owned world;
## production elevation authority and save data are unchanged.

const C4F_ZOOMS: Array[float] = [1.0, 1.75, 2.5, 3.5]


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["c4e1", "c4f"]:
		push_error("Phase C4F capture requires user argument: c4e1 or c4f")
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
	terrain.set_grid_aligned_cliff_rim_enabled(capture_label == "c4f")
	terrain.set_cliff_height_profile(2)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_c4f_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_c4f_scenario(scenario)
	_write_c4f_manifest()
	print("PHASE_C4F_CAPTURE: PASS label=%s captures=%d" % [capture_label, captures.size()])
	quit(0)


func _build_c4f_scenarios() -> void:
	var origin := Vector2i(32768, 16384)
	var centers := PackedVector2Array()
	for index in range(10):
		centers.append(Vector2(origin + Vector2i(index * 96, 0)))
	_build_single_cell_fixture(Vector2i(centers[0]))
	_add_scenario("one_cell", Vector2i(centers[0]), "One raised cell.")
	_fill_fixture(Vector2i(centers[1]), [Vector2i(0, 0), Vector2i(1, 0)])
	_add_scenario("two_adjacent", Vector2i(centers[1]), "Two adjacent raised cells.")
	_rect_fixture(Vector2i(centers[2]), Vector2i(2, 2))
	_add_scenario("two_by_two", Vector2i(centers[2]), "2x2 raised platform.")
	_rect_fixture(Vector2i(centers[3]), Vector2i(3, 3))
	_add_scenario("three_by_three", Vector2i(centers[3]), "3x3 raised platform.")
	_fill_fixture(Vector2i(centers[4]), [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
		Vector2i(1, 2), Vector2i(2, 2)])
	_add_scenario("l_plateau", Vector2i(centers[4]), "L-shaped plateau.")
	_rect_fixture(Vector2i(centers[5]), Vector2i(9, 1))
	_add_scenario("narrow_strip", Vector2i(centers[5]), "Narrow elevated strip.")
	_build_corner_fixture(Vector2i(centers[6]))
	_add_scenario("large_irregular", Vector2i(centers[6]), "Large irregular plateau.")
	_build_multilevel_fixture(Vector2i(centers[7]))
	_add_scenario("multi_level", Vector2i(centers[7]), "Multi-level elevation.")
	_build_water_contact_fixture(Vector2i(centers[8]))
	_add_scenario("water_contact", Vector2i(centers[8]), "Cliffs bordering water and mixed materials.")
	_add_scenario("natural_terrain", Vector2i.ZERO, "Naturally generated terrain.")


func _fill_fixture(center: Vector2i, offsets: Array[Vector2i]) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for offset in offsets:
		_set_cell(center + offset, 4, 2)


func _rect_fixture(center: Vector2i, size: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center - size / 2, size, 4, 2)


func _capture_c4f_scenario(scenario: Dictionary) -> void:
	for zoom in C4F_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var zoom_label := str(zoom).replace(".", "_") + "x"
		var file_name := "c4f_%s_%s_%s.png" % [
			capture_label, String(scenario.label), zoom_label]
		await _save(file_name)
		if capture_label == "c4f":
			var before_path := "%s/c4f_c4e1_%s_%s.png" % [
				OUTPUT_DIR, String(scenario.label), zoom_label]
			var before: Image = Image.load_from_file(before_path)
			var after: Image = Image.load_from_file("%s/%s" % [OUTPUT_DIR, file_name])
			assert(before != null and after != null, "Matched C4F captures must exist")
			var combined := Image.create(before.get_width() * 2, before.get_height(), false, before.get_format())
			combined.blit_rect(before, before.get_used_rect(), Vector2i.ZERO)
			combined.blit_rect(after, after.get_used_rect(), Vector2i(before.get_width(), 0))
			var compare_path := "%s/c4f_compare_%s_%s.png" % [OUTPUT_DIR, scenario.label, zoom_label]
			assert(combined.save_png(compare_path) == OK)
			comparisons.append(compare_path)
		captures.append({"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": scenario.label, "zoom": zoom})


func _write_c4f_manifest() -> void:
	var manifest := {
		"phase": "C4F", "capture_label": capture_label,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"viewport": [1280, 720], "world_seed": terrain.world_seed,
		"zooms": C4F_ZOOMS, "grid_aligned_rim": capture_label == "c4f",
		"corner_radius_pixels": 4, "cell_size_pixels": 32,
		"scenarios": scenarios, "captures": captures, "comparisons": comparisons,
	}
	var path := "%s/c4f_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not write C4F manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
