extends "res://tests/phase3f_capture.gd"
## Matched presentation-only evidence. Lake elevations are explicit, not inferred
## from water colour. This is a reproduction fixture, not the user's saved lake.


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or arguments[0] not in ["baseline", "prominent", "directional"]:
		quit(1)
		return
	capture_label = arguments[0]
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	# Capture time must not change the liquid pattern between modes.
	terrain.visual_material_by_id[0].set_shader_parameter("liquid_motion_enabled", 0.0)
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
	terrain.set_cliff_height_profile(0 if capture_label == "baseline" else 2)
	terrain.set_directional_cliff_projection_enabled(capture_label == "directional")
	var lake_center := Vector2i(24576, 12480)
	_build_lake(lake_center, 2)
	_add_scenario("recessed_sand_lake", lake_center, "Water 0, surrounding sand 2.")
	_build_lake(lake_center + Vector2i(96, 0), 0)
	_add_scenario("equal_height_lake", lake_center + Vector2i(96, 0), "Water and sand both 0: no cliff.")
	_build_phase3f_scenarios()
	var snow_center := lake_center + Vector2i(192, 0)
	_fill(snow_center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(snow_center + Vector2i(-5, -3), Vector2i(10, 7), 5, 3)
	_add_scenario("snow_plateau", snow_center, "Three-level snow plateau.")
	var diagonal_center := lake_center + Vector2i(288, 0)
	_fill(diagonal_center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-16, 16):
		for x in range(-27, 28):
			if x <= floori(-float(y) * 1.45):
				_set_cell(diagonal_center + Vector2i(x, y), 4, 3)
	_add_scenario("south_facing_diagonal", diagonal_center, "Mirrored escarpment facing the camera.")
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		if arguments.size() > 1 and scenario.label != arguments[1]:
			continue
		await _capture_scenario(scenario)
	var suffix: String = "_" + arguments[1] if arguments.size() > 1 else ""
	var file := FileAccess.open("res://.artifacts/phase3g_%s%s_manifest.json" % [capture_label, suffix], FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"seed": terrain.world_seed, "viewport": [1280, 720],
		"height_step": terrain.get_cliff_height_step(),
		"directional": terrain.directional_cliff_projection_enabled,
		"scenarios": scenarios, "captures": captures}, "\t"))
	print("PHASE3G_CAPTURE: PASS %s images=%d" % [capture_label, captures.size()])
	quit(0)


func _build_lake(center: Vector2i, surrounding_height: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 1, surrounding_height)
	for y in range(-3, 4):
		for x in range(-5, 6):
			if float(x * x) / 25.0 + float(y * y) / 9.0 <= 1.0:
				_set_cell(center + Vector2i(x, y), 0, 0)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in PHASE3F_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "phase3g_%s_%s_%s.png" % [
			capture_label, scenario.label, _zoom_label(zoom)]
		await _save(file_name)
		captures.append({"path": "res://.artifacts/" + file_name,
			"scenario": scenario.label, "zoom": zoom,
			"camera_world": _vector_to_array(demo.camera.position)})
