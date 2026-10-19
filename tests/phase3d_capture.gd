extends "res://tests/phase3b_capture.gd"
## Reuses the accepted Phase 3B fixture matrix and camera path. Baseline keeps
## Phase 3C geometry; prototype enables only the Phase 3D connected profile.


func _move_camera(cell: Vector2i, zoom: float) -> void:
	terrain.set_connected_cliff_contours_enabled(capture_label == "prototype")
	await super._move_camera(cell, zoom)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in ZOOMS:
		await _move_camera(scenario.center, zoom)
		var file_name := "phase3d_%s_%s_%s.png" % [
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
	var scenario_records: Array[Dictionary] = []
	for scenario in scenarios:
		scenario_records.append({
			"label": String(scenario.label),
			"kind": String(scenario.kind),
			"center_cell": _vector_to_array(scenario.center),
			"description": String(scenario.description),
		})
	var manifest := {
		"phase": "3D",
		"capture_label": capture_label,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"fixture_size_cells": _vector_to_array(FIXTURE_SIZE),
		"zooms": ZOOMS,
		"connected_cliff_contours": capture_label == "prototype",
		"scenarios": scenario_records,
		"captures": captures,
	}
	var path := "%s/phase3d_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
