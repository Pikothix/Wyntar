extends "res://tests/phase_c4i_legacy_cliff_coverage_capture.gd"
## C4J uses the complete C4I matrix and measurements with distinct artifacts.


func _capture_c4i_scenario(
		scenario: Dictionary, profile_label: String, repair: bool) -> void:
	for zoom in C4H_ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "c4j_%s_%s_%s_%s.png" % [
			capture_label, profile_label, String(scenario.label),
			_c4h_zoom_label(zoom)]
		var image: Image = root.get_texture().get_image()
		assert(image != null, "Graphical renderer is required for C4J captures")
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


func _write_c4i_manifest() -> void:
	var manifest := {
		"phase": "C4J",
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
	var file := FileAccess.open("%s/c4j_capture_manifest.json" % OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null, "Could not write C4J capture manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
