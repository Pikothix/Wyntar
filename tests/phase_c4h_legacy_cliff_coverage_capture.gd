extends "res://tests/phase_c4e_cliff_gap_capture.gd"
## C4H investigation-only capture matrix. It creates deterministic presentation
## fixtures and isolates existing render layers without changing production code.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const C4H_ZOOMS: Array[float] = [1.0, 1.75, 2.5, 3.5]
const C4H_MODES := [
	{"label": "legacy", "value": TerrainRenderer.CliffRenderingMode.LEGACY},
	{"label": "unified", "value": TerrainRenderer.CliffRenderingMode.UNIFIED},
]
const DIAGNOSTIC_SCENARIOS := [
	"long_north_south_boundary",
	"grass_dirt_elevation_boundary",
	"stone_sand_elevation_boundary",
	"almost_touching_formations",
	"three_way_intersection",
	"concave_corner",
	"chunk_boundary_crossing",
	"water_contact",
]

var diagnostic_captures: Array[Dictionary] = []


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color("ff00ff"))
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
	terrain.set_legacy_cliff_coverage_repair_enabled(false)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.MODERATE)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_c4h_scenarios()
	terrain._invalidate_streamed_chunks()
	for mode in C4H_MODES:
		capture_label = String(mode.label)
		terrain.set_cliff_rendering_mode(int(mode.value))
		for scenario in scenarios:
			await _capture_c4h_scenario(scenario)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	await _wait_until_idle()
	for scenario in scenarios:
		if String(scenario.label) in DIAGNOSTIC_SCENARIOS:
			await _capture_diagnostic_layers(scenario)
	_set_layer_visibility(true, true, true, false, false)
	_write_c4h_manifest()
	print("PHASE_C4H_CAPTURE: PASS captures=%d diagnostics=%d" % [
		captures.size(), diagnostic_captures.size()])
	quit(0)


func _build_c4h_scenarios() -> void:
	var origin := Vector2i(49152, 24576)
	var centers: Array[Vector2i] = []
	for index in range(13):
		centers.append(origin + Vector2i(index * 96, 0))
	_build_long_north_south(centers[0])
	_add_scenario("long_north_south_boundary", centers[0],
		"Long vertical raised/lower boundary dominated by side-return geometry.")
	_build_long_east_west(centers[1])
	_add_scenario("long_east_west_boundary", centers[1],
		"Long horizontal raised/lower boundary dominated by projected wall geometry.")
	_build_material_elevation_boundary(centers[2], 3, 2)
	_add_scenario("grass_dirt_elevation_boundary", centers[2],
		"Grass height-two plateau adjoining lower dirt.")
	_build_material_elevation_boundary(centers[3], 4, 1)
	_add_scenario("stone_sand_elevation_boundary", centers[3],
		"Stone height-two plateau adjoining lower sand.")
	_build_single_cell_fixture(centers[4])
	_add_scenario("isolated_raised_cell", centers[4], "Single isolated height-two stone cell.")
	_build_narrow_ridge(centers[5])
	_add_scenario("one_cell_ridge", centers[5], "One-cell-wide height-two dirt ridge.")
	_build_almost_touching(centers[6])
	_add_scenario("almost_touching_formations", centers[6],
		"Two raised formations separated by one authoritative lower cell.")
	_build_three_way(centers[7])
	_add_scenario("three_way_intersection", centers[7],
		"Three raised arms meeting different lower-height regions.")
	_build_concave(centers[8])
	_add_scenario("concave_corner", centers[8], "Raised plateau with a square lower notch.")
	_build_convex(centers[9])
	_add_scenario("convex_corner", centers[9], "Raised plateau with a narrow convex spur.")
	_build_multilevel_fixture(centers[10])
	_add_scenario("multiple_elevation_levels", centers[10], "One-, two-, and three-level terraces.")
	_build_chunk_boundary(centers[11])
	_add_scenario("chunk_boundary_crossing", centers[11],
		"Diagonal raised formation crossing the exact X=50208 chunk boundary.")
	_build_water_contact_fixture(centers[12])
	_add_scenario("water_contact", centers[12], "Raised dirt and stone adjoining water.")


func _build_long_north_south(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-18, -15), Vector2i(18, 30), 2, 2)


func _build_long_east_west(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-25, -15), Vector2i(50, 15), 2, 2)


func _build_material_elevation_boundary(
		center: Vector2i, raised_material: int, lower_material: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, lower_material, 0)
	for y in range(-14, 15):
		var edge: int = floori(sin(float(y) * 0.31) * 4.0)
		for x in range(-24, edge + 1):
			_set_cell(center + Vector2i(x, y), raised_material, 2)


func _build_narrow_ridge(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-1, -14), Vector2i(2, 28), 2, 2)


func _build_almost_touching(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-13, -9), Vector2i(12, 18), 2, 2)
	_fill(center + Vector2i(2, -9), Vector2i(12, 18), 4, 2)
	# The lower channel is intentional authority, not a renderer-created hole.
	_fill(center + Vector2i(-1, -2), Vector2i(3, 5), 3, 0)


func _build_three_way(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-4, -14), Vector2i(8, 29), 2, 2)
	_fill(center + Vector2i(-18, -4), Vector2i(36, 8), 2, 2)
	_fill(center + Vector2i(4, -4), Vector2i(14, 8), 4, 1)


func _build_concave(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-18, -13), Vector2i(36, 26), 2, 2)
	_fill(center + Vector2i(-3, 0), Vector2i(12, 13), 3, 0)


func _build_convex(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-18, -10), Vector2i(24, 20), 4, 2)
	_fill(center + Vector2i(6, -2), Vector2i(12, 5), 4, 2)


func _build_chunk_boundary(center: Vector2i) -> void:
	assert(posmod(center.x, 32) == 0)
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-15, 16):
		for x in range(-27, 28):
			if x <= floori(float(y) * 0.8) + 2:
				_set_cell(center + Vector2i(x, y), 4, 2)


func _capture_c4h_scenario(scenario: Dictionary) -> void:
	for zoom in C4H_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "c4h_%s_%s_%s.png" % [
			capture_label, String(scenario.label), _c4h_zoom_label(zoom)]
		await _save(file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"mode": capture_label,
			"scenario": String(scenario.label),
			"center_cell": _vector_to_array(scenario.center),
			"zoom": zoom,
		})


func _capture_diagnostic_layers(scenario: Dictionary) -> void:
	await _move_camera(scenario.center, 2.5)
	var passes := [
		{"label": "full", "flags": [true, true, true, false, false]},
		{"label": "ground_only", "flags": [true, false, false, false, false]},
		{"label": "surface_only", "flags": [false, true, false, false, false]},
		{"label": "face_only", "flags": [false, false, true, false, false]},
		{"label": "ground_and_surface", "flags": [true, true, false, false, false]},
		{"label": "ground_and_face", "flags": [true, false, true, false, false]},
		{"label": "with_rims", "flags": [true, true, true, true, false]},
		{"label": "with_shadows", "flags": [true, true, true, false, true]},
	]
	for pass_record in passes:
		var flags: Array = pass_record.flags
		_set_layer_visibility(flags[0], flags[1], flags[2], flags[3], flags[4])
		await _wait_frames(2)
		var file_name := "c4h_diag_%s_%s.png" % [
			String(scenario.label), String(pass_record.label)]
		await _save(file_name)
		diagnostic_captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": String(scenario.label),
			"pass": String(pass_record.label),
			"center_cell": _vector_to_array(scenario.center),
		})


func _set_layer_visibility(
		ground: bool, surface: bool, faces: bool, rims: bool, shadows: bool) -> void:
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.visible = ground
		for surface_group in chunk.elevated_layers:
			if surface_group != null:
				for layer in surface_group:
					layer.visible = surface
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.cliff_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null:
				layer.visible = faces and layer.mesh != null
		for layer in chunk.cliff_edge_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_edge_mesh_layers:
			if layer != null:
				layer.visible = rims and layer.mesh != null
		for layer in chunk.cliff_shadow_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_shadow_mesh_layers:
			if layer != null:
				layer.visible = shadows and layer.mesh != null


func _write_c4h_manifest() -> void:
	var manifest := {
		"phase": "C4H",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"zooms": C4H_ZOOMS,
		"modes": C4H_MODES,
		"scenarios": scenarios,
		"captures": captures,
		"diagnostic_captures": diagnostic_captures,
		"diagnostic_clear_color": "ff00ff",
		"legacy_settings": {
			"unified_contours": true,
			"directional_projection": true,
			"height_profile": "moderate",
			"edge_overlays": false,
			"shadows": false,
		},
	}
	var file := FileAccess.open("%s/c4h_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write C4H capture manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _c4h_zoom_label(zoom: float) -> String:
	return str(zoom).replace(".", "_") + "x"
