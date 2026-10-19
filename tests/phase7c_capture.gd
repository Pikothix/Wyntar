extends SceneTree
## Phase 7C deterministic visual matrix. Run against the Phase 7B.1 baseline
## and the current project with the same prefix to obtain identical views.

const OUTPUT_DIR := "res://screenshots"
const VIEW_SIZE := Vector2i(96, 56)

var demo
var terrain
var capture_prefix: String = "after"
var scenarios: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		capture_prefix = args[0].validate_filename()
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
	for scenario in scenarios:
		for zoom in [0.5, 1.0, 3.0]:
			await _capture_at(
				String(scenario["label"]), scenario["center"], zoom)
	print("PHASE7C_GRAPHICAL_CAPTURE: PASS prefix=%s captures=%d" % [
		capture_prefix, scenarios.size() * 3])
	quit(0)


func _build_scenarios() -> void:
	var centers: Array[Vector2i] = [
		Vector2i(900, 900), Vector2i(1028, 900),
		Vector2i(1156, 900), Vector2i(1284, 900),
		Vector2i(900, 996), Vector2i(1028, 996),
		Vector2i(1156, 996), Vector2i(1284, 996),
	]
	for center in centers:
		_fill(center - VIEW_SIZE / 2, VIEW_SIZE, 3, 0)

	# 1. Large water body with an irregular grass shoreline.
	_fill_ellipse(centers[0] - Vector2i(34, 0), Vector2(35, 20), 0, 2)
	scenarios.append({"label": "large_water_body", "center": centers[0]})

	# 2. Calm water meeting a broad sand beach.
	_fill(centers[1] - VIEW_SIZE / 2, VIEW_SIZE, 1, 0)
	for y in range(centers[1].y - 28, centers[1].y + 28):
		for x in range(centers[1].x - 48, centers[1].x + 5 + posmod(y, 7)):
			_set_cell(Vector2i(x, y), 0, 2)
	scenarios.append({"label": "water_against_sand", "center": centers[1]})

	# 3. Water directly against grass.
	_fill_ellipse(centers[2] - Vector2i(28, 0), Vector2(29, 22), 0, 1)
	scenarios.append({"label": "water_against_grass", "center": centers[2]})

	# 4. Raised grass and stone faces terminating in water.
	_fill(centers[3] - VIEW_SIZE / 2, VIEW_SIZE, 0, 3)
	_fill(centers[3] - Vector2i(42, 24), Vector2i(84, 24), 3, 2)
	_fill(centers[3] - Vector2i(18, 24), Vector2i(36, 24), 4, 3)
	scenarios.append({"label": "water_beside_cliffs", "center": centers[3]})

	# 5. Liquid owns a high ground value but must still render only at sea level;
	# adjacent sand and grass sit in raised surface bands.
	_fill(centers[4] - VIEW_SIZE / 2, VIEW_SIZE, 1, 2)
	for y in range(centers[4].y - 20, centers[4].y + 20):
		for x in range(centers[4].x - 34, centers[4].x + 4):
			_set_cell(Vector2i(x, y), 0, 3)
	_fill(centers[4] + Vector2i(4, -20), Vector2i(30, 40), 3, 3)
	scenarios.append({"label": "height_overlap_regression", "center": centers[4]})

	# 6. One plateau exposes north, east, west lips and a southern wall.
	_fill(centers[5] - VIEW_SIZE / 2, VIEW_SIZE, 2, 0)
	_fill(centers[5] - Vector2i(12, 7), Vector2i(24, 14), 3, 2)
	_fill(centers[5] - Vector2i(4, 2), Vector2i(8, 5), 5, 3)
	scenarios.append({"label": "cliff_lip_directions", "center": centers[5]})

	# 7. Rough materials retain higher-frequency character.
	_fill(centers[6] - VIEW_SIZE / 2, VIEW_SIZE, 4, 1)
	for y in range(centers[6].y - 28, centers[6].y + 28):
		for x in range(centers[6].x - 48, centers[6].x + 48):
			if posmod(x * 13 + y * 7, 17) < 8:
				_set_cell(Vector2i(x, y), 7, 1)
	scenarios.append({"label": "dense_stone_gravel", "center": centers[6]})

	# 8. Quiet materials demonstrate low-frequency, low-contrast variation.
	_fill(centers[7] - VIEW_SIZE / 2, Vector2i(48, 56), 1, 0)
	_fill(centers[7] + Vector2i(0, -28), Vector2i(48, 56), 5, 1)
	scenarios.append({"label": "calm_sand_snow", "center": centers[7]})


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


func _capture_at(label: String, cell: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(3)
	var zoom_label: String = "0_5x" if is_equal_approx(zoom, 0.5) else ("1_0x" if is_equal_approx(zoom, 1.0) else "3_0x")
	var path: String = "%s/phase7c_%s_%s_%s.png" % [
		OUTPUT_DIR, capture_prefix, label, zoom_label]
	var error: Error = root.get_texture().get_image().save_png(path)
	assert(error == OK, "Could not save %s" % path)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase 7C capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
