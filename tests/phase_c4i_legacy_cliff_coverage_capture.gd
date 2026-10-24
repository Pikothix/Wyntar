extends "res://tests/phase_c4h_legacy_cliff_coverage_capture.gd"
## Matched C4I coverage captures and exact-clear-pixel measurements across the
## complete C4H fixture matrix, zooms, and all accepted height profiles.

const C4I_PROFILES := [
	{"label": "baseline", "value": TerrainRenderer.CliffHeightProfile.BASELINE},
	{"label": "moderate", "value": TerrainRenderer.CliffHeightProfile.MODERATE},
	{"label": "prominent", "value": TerrainRenderer.CliffHeightProfile.PROMINENT},
]

var measurements: Array[Dictionary] = []
var selected_profiles: Array = C4I_PROFILES


func _run() -> void:
	if OS.get_cmdline_user_args().has("quick"):
		selected_profiles = [C4I_PROFILES[1]]
	elif OS.get_cmdline_user_args().has("prominent"):
		selected_profiles = [C4I_PROFILES[2]]
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color("ff00ff"))
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
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
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_c4h_scenarios()
	terrain._invalidate_streamed_chunks()
	for profile in selected_profiles:
		terrain.set_cliff_height_profile(int(profile.value))
		for repair in [false, true]:
			terrain.set_legacy_cliff_coverage_repair_enabled(repair)
			capture_label = "after" if repair else "before"
			for scenario in scenarios:
				await _capture_c4i_scenario(scenario, String(profile.label), repair)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.MODERATE)
	terrain.set_legacy_cliff_coverage_repair_enabled(true)
	streaming_revisit_pixel_exact = await _verify_c4i_streaming_revisit(
		_find_scenario("chunk_boundary_crossing"))
	_write_c4i_manifest()
	print("PHASE_C4I_CAPTURE: PASS captures=%d uncovered_before=%d uncovered_after=%d revisit=%s" % [
		captures.size(), _total_uncovered(false), _total_uncovered(true),
		str(streaming_revisit_pixel_exact)])
	quit(0)


func _capture_c4i_scenario(
		scenario: Dictionary, profile_label: String, repair: bool) -> void:
	for zoom in C4H_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "c4i_%s_%s_%s_%s.png" % [
			capture_label, profile_label, String(scenario.label),
			_c4h_zoom_label(zoom)]
		var image: Image = root.get_texture().get_image()
		assert(image != null, "Graphical renderer is required for C4I captures")
		assert(image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK)
		var geometry: Dictionary = _geometry_totals()
		var record := {
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"repair_enabled": repair,
			"profile": profile_label,
			"scenario": String(scenario.label),
			"direction": _direction_class(String(scenario.label)),
			"elevation_class": _elevation_class(String(scenario.label)),
			"zoom": zoom,
			"uncovered_pixels": _count_clear_pixels(image),
			"clear_or_blended_pixels": _count_clear_or_blended_pixels(image),
			"geometry": geometry,
			"draw_calls": Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		}
		measurements.append(record)
		captures.append(record)


func _count_clear_pixels(image: Image) -> int:
	var rgba: Image = image.duplicate()
	rgba.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = rgba.get_data()
	var count: int = 0
	for offset in range(0, data.size(), 4):
		if (data[offset] == 255 and data[offset + 1] == 0
				and data[offset + 2] == 255 and data[offset + 3] == 255):
			count += 1
	return count


func _count_clear_or_blended_pixels(image: Image) -> int:
	var rgba: Image = image.duplicate()
	rgba.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = rgba.get_data()
	var count: int = 0
	for offset in range(0, data.size(), 4):
		if (data[offset] >= 180 and data[offset + 1] <= 100
				and data[offset + 2] >= 180 and data[offset + 3] == 255):
			count += 1
	return count


func _geometry_totals() -> Dictionary:
	var totals := {
		"vertices": 0, "triangles": 0, "coverage_vertices": 0,
		"coverage_triangles": 0, "coverage_meshes": 0, "build_usec": 0,
	}
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		totals.vertices += int(stats.vertex_count)
		totals.triangles += int(stats.triangle_count)
		totals.coverage_vertices += int(stats.coverage_vertex_count)
		totals.coverage_triangles += int(stats.coverage_triangle_count)
		totals.coverage_meshes += int(stats.coverage_mesh_count)
		totals.build_usec += int(stats.build_usec)
	return totals


func _verify_c4i_streaming_revisit(scenario: Dictionary) -> bool:
	await _move_camera(scenario.center, 2.5)
	var reference: Image = root.get_texture().get_image()
	await _move_camera(scenario.center + Vector2i(160, 96), 2.5)
	await _move_camera(scenario.center, 2.5)
	var revisit: Image = root.get_texture().get_image()
	return hash(reference.get_data()) == hash(revisit.get_data())


func _find_scenario(label: String) -> Dictionary:
	for scenario in scenarios:
		if String(scenario.label) == label:
			return scenario
	assert(false, "Missing C4I scenario %s" % label)
	return {}


func _total_uncovered(repair: bool) -> int:
	var total: int = 0
	for record in measurements:
		if bool(record.repair_enabled) == repair:
			total += int(record.uncovered_pixels)
	return total


func _direction_class(label: String) -> String:
	if label == "long_north_south_boundary" or label == "one_cell_ridge":
		return "lateral"
	if label == "long_east_west_boundary":
		return "projected_foot"
	if label == "chunk_boundary_crossing":
		return "diagonal_seam"
	return "mixed_corner_or_intersection"


func _elevation_class(label: String) -> String:
	if label == "multiple_elevation_levels" or label == "water_contact":
		return "multi_level"
	return "height_two"


func _write_c4i_manifest() -> void:
	var manifest := {
		"phase": "C4I",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"profiles": selected_profiles,
		"zooms": C4H_ZOOMS,
		"measurements": measurements,
		"streaming_revisit_pixel_exact": streaming_revisit_pixel_exact,
	}
	var file := FileAccess.open("%s/c4i_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write C4I capture manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
