extends "res://tests/phase3e_capture.gd"
## Matched Phase 3F baseline/moderate/prominent evidence. Every mode uses the
## same authoritative fixtures, seed, camera cells, viewport, and zooms.

const PHASE3F_ZOOMS: Array[float] = [1.0, 2.31, 3.0]
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["baseline", "moderate", "prominent"]:
		push_error("Phase 3F capture requires: baseline, moderate, or prominent")
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
	terrain.set_cliff_height_profile(_profile_id(capture_label))
	_build_phase3f_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_scenario(scenario)
	_write_manifest()
	print("PHASE3F_CAPTURE: PASS label=%s captures=%d" % [capture_label, captures.size()])
	quit(0)


func _build_phase3f_scenarios() -> void:
	var origin := Vector2i(24576, 12288)
	_build_plateau(origin, 1)
	_add_scenario("one_level_grass_plateau", origin, "One-level grass plateau.")
	_build_plateau(origin + Vector2i(96, 0), 2)
	_add_scenario("two_level_raised_landmass", origin + Vector2i(96, 0), "Two-level raised grass landmass.")
	_build_plateau(origin + Vector2i(192, 0), 3)
	_add_scenario("three_level_cliff", origin + Vector2i(192, 0), "Three-level stone cliff.")
	_build_diagonal_fixture(origin + Vector2i(288, 0), 4)
	_add_scenario("long_diagonal_escarpment", origin + Vector2i(288, 0), "Long diagonal organic escarpment.")
	_build_winding_fixture(origin + Vector2i(384, 0))
	_add_scenario("winding_cliff", origin + Vector2i(384, 0), "Winding cliff with alternating turns.")
	_build_corner_fixture(origin + Vector2i(480, 0))
	_add_scenario("convex_concave_corners", origin + Vector2i(480, 0), "Convex spur and concave notch.")
	_build_narrow_ridge(origin + Vector2i(576, 0))
	_add_scenario("narrow_ridges", origin + Vector2i(576, 0), "Narrow connected multi-height ridges.")
	_build_isolated_fixture(origin + Vector2i(672, 0))
	_add_scenario("isolated_formations", origin + Vector2i(672, 0), "Small isolated one-, two-, and three-level formations.")
	_build_mixed_height_fixture(origin + Vector2i(768, 0))
	_add_scenario("mixed_height_junctions", origin + Vector2i(768, 0), "Mixed-height junctions and terraces.")
	_build_signed_seam_fixture(Vector2i(32, -24576), 32)
	_add_scenario("positive_chunk_boundary", Vector2i(32, -24576), "Cliff crossing a positive chunk seam.")
	_build_signed_seam_fixture(Vector2i(-32, -24576), -32)
	_add_scenario("negative_chunk_boundary", Vector2i(-32, -24576), "Cliff crossing a negative chunk seam.")


func _build_plateau(center: Vector2i, height: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	# Keep the complete crest, face, and toe visible even in the matched 3x frame.
	_fill(center + Vector2i(-5, -3), Vector2i(10, 7), 4 if height == 3 else 3, height)


func _build_narrow_ridge(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-22, 23):
		var x: int = roundi(sin(float(y) * 0.22) * 7.0)
		for width in range(-2, 3):
			_set_cell(center + Vector2i(x + width, y), 4, 2 if y < 5 else 3)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in PHASE3F_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "phase3f_%s_%s_%s.png" % [
			capture_label, String(scenario.label), _zoom_label(zoom)]
		await _save(file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": String(scenario.label),
			"camera_cell": _vector_to_array(scenario.center),
			"camera_world": _vector_to_array(demo.camera.position),
			"zoom": zoom,
		})


func _write_manifest() -> void:
	var manifest := {
		"phase": "3F", "capture_label": capture_label,
		"height_profile": _profile_id(capture_label),
		"height_step": terrain.get_cliff_height_step(),
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(), "viewport": [1280, 720],
		"world_seed": terrain.world_seed, "zooms": PHASE3F_ZOOMS,
		"unified_contours": true, "scenarios": scenarios, "captures": captures,
	}
	var path := "%s/phase3f_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _profile_id(label: String) -> int:
	match label:
		"moderate":
			return TerrainRenderer.CliffHeightProfile.MODERATE
		"prominent":
			return TerrainRenderer.CliffHeightProfile.PROMINENT
		_:
			return TerrainRenderer.CliffHeightProfile.BASELINE
