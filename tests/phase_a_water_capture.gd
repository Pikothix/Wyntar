extends SceneTree
## Phase A matched visual matrix. Every mode uses the same authored fixtures,
## viewport, camera, seed, zoom, and fixed shader animation time.

const OUTPUT_DIR := "res://screenshots"
const FIXTURE_SIZE := Vector2i(104, 64)
const FIXED_TIME := 6.0

var demo
var terrain
var scenarios: Array[Dictionary] = []
var manifest: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_scenarios()
	terrain._invalidate_streamed_chunks()

	for mode in ["baseline", "enhanced_no_glints", "enhanced_glints"]:
		_apply_mode(mode)
		terrain.set_water_animation_time_override(FIXED_TIME)
		for scenario in scenarios:
			for zoom in [0.5, 1.0, 3.0]:
				await _capture_at(mode, String(scenario.label), scenario.center, zoom, FIXED_TIME)

	var animation_center: Vector2i = scenarios[0].center
	for mode in ["baseline", "enhanced_no_glints", "enhanced_glints"]:
		_apply_mode(mode)
		for frame_index in range(4):
			var animation_time: float = FIXED_TIME + frame_index * 0.25
			terrain.set_water_animation_time_override(animation_time)
			await _capture_at(
				mode, "animation_large_lake", animation_center, 1.0,
				animation_time, frame_index)

	var manifest_path := "%s/phase_a_capture_manifest.json" % OUTPUT_DIR
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(file != null, "Could not write %s" % manifest_path)
	file.store_string(JSON.stringify({
		"world_seed": demo.world_seed,
		"viewport": [1280, 720],
		"fixed_time_seconds": FIXED_TIME,
		"captures": manifest,
	}, "\t"))
	print("PHASE_A_WATER_CAPTURE: PASS captures=%d manifest=%s" % [
		manifest.size(), manifest_path])
	quit(0)


func _apply_mode(mode: String) -> void:
	terrain.set_experimental_water_enhancement_enabled(mode != "baseline")
	terrain.set_water_enhancement_controls(
		0.32, 2.4, 0.55, 0.0 if mode == "enhanced_no_glints" else 0.14, 0.38)


func _build_scenarios() -> void:
	var centers: Array[Vector2i] = [
		Vector2i(800, 800), Vector2i(960, 800), Vector2i(1120, 800),
		Vector2i(1280, 800), Vector2i(1440, 800), Vector2i(1536, 928),
		Vector2i(-512, -512),
	]
	for center in centers:
		_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)

	# 1. Large open lake with irregular grass edges.
	_fill_ellipse(centers[0], Vector2(46, 27), 0, 0)
	scenarios.append({"label": "large_open_lake", "center": centers[0]})

	# 2. Small enclosed pond.
	_fill_ellipse(centers[1], Vector2(13, 9), 0, 0)
	scenarios.append({"label": "small_enclosed_pond", "center": centers[1]})

	# 3. Water against an irregular sandy shoreline.
	_fill(centers[2] - FIXTURE_SIZE / 2, FIXTURE_SIZE, 1, 0)
	for y in range(centers[2].y - 32, centers[2].y + 32):
		for x in range(centers[2].x - 52, centers[2].x + posmod(y, 9) - 2):
			_set_cell(Vector2i(x, y), 0, 0)
	scenarios.append({"label": "irregular_sandy_shoreline", "center": centers[2]})

	# 4. Water meeting grassland directly.
	for y in range(centers[3].y - 32, centers[3].y + 32):
		for x in range(centers[3].x - 52, centers[3].x + 5 + posmod(y * 3, 11)):
			_set_cell(Vector2i(x, y), 0, 0)
	scenarios.append({"label": "grassland_shoreline", "center": centers[3]})

	# 5. Water adjacent to raised grass and stone cliffs.
	_fill(centers[4] - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	_fill(centers[4] - Vector2i(46, 30), Vector2i(92, 27), 3, 2)
	_fill(centers[4] - Vector2i(20, 30), Vector2i(40, 27), 4, 3)
	scenarios.append({"label": "water_adjacent_to_cliffs", "center": centers[4]})

	# 6. Open water centred exactly on a 32-cell chunk boundary.
	_fill(centers[5] - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	scenarios.append({"label": "water_crossing_chunk_boundaries", "center": centers[5]})

	# 7. Irregular lake entirely at negative world coordinates.
	_fill_ellipse(centers[6], Vector2(43, 25), 0, 0)
	scenarios.append({"label": "negative_world_coordinates", "center": centers[6]})


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _fill_ellipse(
		center: Vector2i, radii: Vector2, material_id: int,
		stored_ground_elevation: int) -> void:
	for y in range(center.y - ceili(radii.y), center.y + ceili(radii.y) + 1):
		for x in range(center.x - ceili(radii.x), center.x + ceili(radii.x) + 1):
			var delta := Vector2(x - center.x, y - center.y) / radii
			var irregularity: float = sin(float(x) * 0.31) * 0.035 + cos(float(y) * 0.27) * 0.035
			if delta.length_squared() <= 1.0 + irregularity:
				_set_cell(Vector2i(x, y), material_id, stored_ground_elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_at(
		mode: String, label: String, cell: Vector2i, zoom: float,
		animation_time: float, frame_index: int = -1) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(3)
	var zoom_label: String = (
		"0_5x" if is_equal_approx(zoom, 0.5)
		else ("1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"))
	var suffix: String = "_frame_%02d_t_%0.2f" % [frame_index, animation_time] if frame_index >= 0 else ""
	var path: String = "%s/phase_a_%s_%s_%s%s.png" % [
		OUTPUT_DIR, mode, label, zoom_label, suffix]
	var error: Error = root.get_texture().get_image().save_png(path)
	assert(error == OK, "Could not save %s" % path)
	manifest.append({
		"path": path, "mode": mode, "scenario": label, "zoom": zoom,
		"animation_time_seconds": animation_time,
	})


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase A capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
