extends SceneTree
## Deterministic Phase 7C.2 comparison matrix for cliff shape treatment.

const OUTPUT_DIR := "res://.artifacts"
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
			await _capture_at(String(scenario["label"]), scenario["center"], zoom)
	await _capture_annotated_small_island()
	print("PHASE7C2_GRAPHICAL_CAPTURE: PASS prefix=%s captures=%d" % [
		capture_prefix, scenarios.size() * 3 + 1])
	quit(0)


func _build_scenarios() -> void:
	var centers: Array[Vector2i] = [
		Vector2i(1400, 1200), Vector2i(1528, 1200),
		Vector2i(1656, 1200), Vector2i(1784, 1200),
		Vector2i(1912, 1200), Vector2i(1400, 1296),
		Vector2i(1528, 1296), Vector2i(1656, 1296),
		Vector2i(1792, 1296), Vector2i(1912, 1296),
	]
	for center in centers:
		_fill(center - VIEW_SIZE / 2, VIEW_SIZE, 0, 2)

	# 1. Compact sand island: the original problem shape.
	_fill(centers[0] - Vector2i(3, 2), Vector2i(6, 4), 1, 2)
	scenarios.append({"label": "small_sand_island", "center": centers[0]})

	# 2. One authoritative raised cell remains elevated without four strips.
	_set_cell(centers[1], 1, 2)
	scenarios.append({"label": "single_cell_island", "center": centers[1]})

	# 3. Two-cell-wide island exercises the narrow-shape rule.
	_fill(centers[2] - Vector2i(1, 3), Vector2i(2, 6), 1, 2)
	scenarios.append({"label": "two_cell_island", "center": centers[2]})

	# 4. A narrow peninsula connects to a broad raised coast at the north.
	_fill(centers[3] - Vector2i(26, 24), Vector2i(52, 18), 3, 2)
	_fill(centers[3] - Vector2i(1, 8), Vector2i(2, 18), 1, 2)
	scenarios.append({"label": "narrow_peninsula", "center": centers[3]})

	# 5. Water cuts a concave inlet into raised grass.
	_fill(centers[4] - VIEW_SIZE / 2, VIEW_SIZE, 3, 2)
	for y in range(centers[4].y - 22, centers[4].y + 23):
		var inlet_half: int = maxi(2, 13 - absi(y - centers[4].y) / 2)
		for x in range(centers[4].x - inlet_half, centers[4].x + inlet_half + 1):
			_set_cell(Vector2i(x, y), 0, 1)
	scenarios.append({"label": "irregular_coastal_inlet", "center": centers[4]})

	# 6. Broad plateau preserves the long primary southern wall.
	_fill(centers[5] - Vector2i(42, 22), Vector2i(84, 22), 4, 2)
	scenarios.append({"label": "broad_southern_wall", "center": centers[5]})

	# 7. Broad top and side boundaries retain subtle tertiary cues.
	_fill(centers[6] - Vector2i(5, 3), Vector2i(10, 7), 3, 2)
	scenarios.append({"label": "north_and_side_boundaries", "center": centers[6]})

	# 8. Multi-level sand/stone mass beside sea-level water.
	_fill(centers[7] - Vector2i(22, 15), Vector2i(44, 15), 1, 1)
	_fill(centers[7] - Vector2i(13, 15), Vector2i(26, 15), 4, 3)
	scenarios.append({"label": "multi_level_water_cliff", "center": centers[7]})

	# 9. x=1792 is a 32-cell boundary; the corner crosses it deliberately.
	_fill(centers[8] - Vector2i(19, 13), Vector2i(38, 26), 3, 2)
	for y in range(centers[8].y, centers[8].y + 13):
		for x in range(centers[8].x, centers[8].x + 19):
			_set_cell(Vector2i(x, y), 0, 1)
	scenarios.append({"label": "chunk_boundary_corner", "center": centers[8]})

	# 10. Mixed cliff owners verify dirt/stone source continuity.
	_fill(centers[9] - Vector2i(36, 15), Vector2i(18, 15), 1, 1)
	_fill(centers[9] - Vector2i(18, 15), Vector2i(18, 15), 2, 2)
	_fill(centers[9] + Vector2i(0, -15), Vector2i(18, 15), 3, 2)
	_fill(centers[9] + Vector2i(18, -15), Vector2i(18, 15), 4, 3)
	scenarios.append({"label": "mixed_material_cliffs", "center": centers[9]})


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _capture_at(label: String, cell: Vector2i, zoom: float) -> void:
	await _move_camera(cell, zoom)
	var zoom_label: String = "0_5x" if is_equal_approx(zoom, 0.5) else ("1_0x" if is_equal_approx(zoom, 1.0) else "3_0x")
	await _save("phase7c2_%s_%s_%s" % [capture_prefix, label, zoom_label])


func _capture_annotated_small_island() -> void:
	await _move_camera(scenarios[0]["center"], 3.0)
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	root.add_child(canvas)
	var label := Label.new()
	label.position = Vector2(24, 22)
	label.text = (
		"BEFORE: detached full-height side returns"
		if capture_prefix == "before"
		else "AFTER: secondary returns shortened into the south wall")
	label.add_theme_color_override(
		"font_color", Color("ffcf70") if capture_prefix == "before" else Color("9ff0b2"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)
	var arrow := Line2D.new()
	arrow.width = 4.0
	arrow.default_color = Color("ffcf70") if capture_prefix == "before" else Color("9ff0b2")
	arrow.points = PackedVector2Array([
		Vector2(390, 62), Vector2(535, 190), Vector2(570, 310),
	])
	canvas.add_child(arrow)
	await _wait_frames(2)
	await _save("phase7c2_%s_annotated_small_island_3_0x" % capture_prefix)
	canvas.queue_free()
	await process_frame


func _move_camera(cell: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(3)


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	assert(image != null, "Graphical renderer is required for Phase 7C.2 captures")
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	var error: Error = image.save_png(path)
	assert(error == OK, "Could not save %s" % path)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase 7C.2 capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
