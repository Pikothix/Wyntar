extends SceneTree
## Validates and captures the real main.tscn startup path without changing either
## cliff feature flag. Terrain remains authoritative; this script only observes
## the presentation nodes produced by the normal gameplay scene.

const OUTPUT_PATH := "res://screenshots/phase1b_normal_gameplay_enabled.png"

var demo
var terrain
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_until_idle()
	await _wait_frames(3)
	terrain = demo.terrain

	_expect(demo.organic_cliff_geometry_enabled,
		"main.tscn starts with Phase 1B organic cliff geometry enabled")
	_expect(demo.procedural_cliff_materials_enabled,
		"main.tscn starts with Phase 1A procedural cliff materials enabled")
	_expect(terrain.is_organic_cliff_geometry_enabled(),
		"normal startup passes the Phase 1B flag to TerrainRenderer")
	_expect(terrain.is_procedural_cliff_materials_enabled(),
		"normal startup passes the Phase 1A flag to TerrainRenderer")

	var organic_mesh_count := 0
	var organic_face_count := 0
	var visible_legacy_face_layers := 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		organic_mesh_count += int(stats.mesh_count)
		organic_face_count += int(stats.face_count)
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null and layer.mesh != null:
				_expect(layer.visible,
					"built organic cliff meshes are visible in main.tscn")
		for layer in chunk.cliff_layers:
			if layer != null and layer.visible:
				visible_legacy_face_layers += 1

	_expect(organic_mesh_count > 0,
		"normal gameplay chunks contain organic cliff mesh batches")
	_expect(organic_face_count > 0,
		"normal gameplay chunks contain organic cliff faces")
	_expect(visible_legacy_face_layers == 0,
		"legacy rectangular cliff face layers are hidden")

	var image: Image = root.get_texture().get_image()
	_expect(image != null, "graphical renderer supplies a gameplay capture")
	if image != null:
		var save_error: Error = image.save_png(OUTPUT_PATH)
		_expect(save_error == OK, "normal gameplay screenshot is saved")

	if failures.is_empty():
		print("PHASE1B_MAIN_STARTUP: PASS meshes=%d faces=%d legacy_visible=%d screenshot=%s" % [
			organic_mesh_count, organic_face_count, visible_legacy_face_layers, OUTPUT_PATH])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1B_MAIN_STARTUP: FAIL (%d)" % failures.size())
	quit(1)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if demo != null and demo.terrain != null:
			terrain = demo.terrain
			if (terrain.get_pending_chunk_count() == 0
					and terrain.get_pending_edit_cell_count() == 0
					and terrain.get_pending_edit_environment_chunk_count() == 0):
				return
	assert(false, "Phase 1B main startup streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
