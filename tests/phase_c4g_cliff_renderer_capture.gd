extends "res://tests/phase_c4e_cliff_gap_capture.gd"
## Identical C4G comparison matrix across every implemented renderer mode.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const C4G_ZOOMS: Array[float] = [1.0, 1.75, 2.5, 3.5]
const C4G_MODES := [
	{"label": "legacy", "value": TerrainRenderer.CliffRenderingMode.LEGACY},
	{"label": "grid", "value": TerrainRenderer.CliffRenderingMode.GRID},
	{"label": "unified", "value": TerrainRenderer.CliffRenderingMode.UNIFIED},
	{"label": "stylised", "value": TerrainRenderer.CliffRenderingMode.STYLISED},
]


func _run() -> void:
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
	terrain.set_grid_aligned_cliff_rim_enabled(false)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.PROMINENT)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_c4g_scenarios()
	terrain._invalidate_streamed_chunks()
	for mode in C4G_MODES:
		capture_label = String(mode.label)
		terrain.set_cliff_rendering_mode(int(mode.value))
		for scenario in scenarios:
			await _capture_c4g_scenario(scenario)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	await _wait_until_idle()
	_write_c4g_manifest()
	print("PHASE_C4G_CAPTURE: PASS captures=%d" % captures.size())
	quit(0)


func _build_c4g_scenarios() -> void:
	var origin := Vector2i(40960, 20480)
	var centers: Array[Vector2i] = []
	for index in range(9):
		centers.append(origin + Vector2i(index * 96, 0))
	_build_single_cell_fixture(centers[0])
	_add_scenario("single_raised_cell", centers[0], "One square raised cell.")
	_fill(centers[1] - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(centers[1] - Vector2i.ONE, Vector2i(2, 2), 4, 2)
	_add_scenario("two_by_two_plateau", centers[1], "2x2 stone plateau.")
	_fill(centers[2] - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(centers[2] + Vector2i(-23, -3), Vector2i(46, 6), 4, 2)
	_add_scenario("long_straight_wall", centers[2], "Long cardinal wall.")
	_build_stepped_fixture(centers[3])
	_add_scenario("curved_stepped_wall", centers[3], "Stepped curve with convex and concave turns.")
	_fill(centers[4] - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(centers[4] + Vector2i(-8, -8), Vector2i(5, 17), 2, 2)
	_fill(centers[4] + Vector2i(-3, 4), Vector2i(15, 5), 2, 2)
	_add_scenario("l_shaped_plateau", centers[4], "L-shaped dirt plateau.")
	_build_multilevel_fixture(centers[5])
	_add_scenario("multi_level_elevation", centers[5], "One-, two-, and three-level terraces.")
	_build_grass_stone_fixture(centers[6])
	_add_scenario("grass_stone_transition", centers[6], "Shared-height grass and stone transition.")
	_build_sand_water_fixture(centers[7])
	_add_scenario("sand_water_contact", centers[7], "Raised sand and stone at water contact.")
	_build_signed_seam_fixture(centers[8], centers[8].x)
	_add_scenario("chunk_boundary_crossing", centers[8], "Formation crossing an exact chunk boundary.")
	scenarios.append({
		"label": "natural_terrain", "center": Vector2i.ZERO, "kind": "generated",
		"description": "Unmodified generated terrain seed.",
	})


func _build_stepped_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-12, 13):
		var edge: int = floori(sin(float(y) * 0.25) * 5.0) + floori(float(y) / 3.0)
		for x in range(-18, edge + 1):
			_set_cell(center + Vector2i(x, y), 2, 2)


func _build_grass_stone_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 2, 0)
	_fill(center + Vector2i(-18, -9), Vector2i(18, 18), 3, 2)
	_fill(center + Vector2i(0, -9), Vector2i(18, 18), 4, 2)


func _build_sand_water_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	_fill(center + Vector2i(-20, -11), Vector2i(20, 18), 1, 2)
	_fill(center + Vector2i(0, -11), Vector2i(20, 18), 4, 2)


func _capture_c4g_scenario(scenario: Dictionary) -> void:
	for zoom in C4G_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "c4g_%s_%s_%s.png" % [
			capture_label, String(scenario.label), _c4g_zoom_label(zoom)]
		await _save(file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"mode": capture_label, "scenario": String(scenario.label), "zoom": zoom,
		})


func _write_c4g_manifest() -> void:
	var manifest := {
		"phase": "C4G", "engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(), "viewport": [1280, 720],
		"world_seed": terrain.world_seed, "zooms": C4G_ZOOMS,
		"modes": C4G_MODES, "scenarios": scenarios, "captures": captures,
		"experimental_default": terrain.get_cliff_rendering_mode() == TerrainRenderer.CliffRenderingMode.LEGACY,
	}
	var file := FileAccess.open("%s/c4g_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write C4G capture manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _c4g_zoom_label(zoom: float) -> String:
	return str(zoom).replace(".", "_") + "x"
