extends "res://tests/phase3b_capture.gd"
## C4E.1 reproduction for alternating diagonal/vertical contour runs. Short
## vertical runs expose projected faces that bypass the exact-degenerate path.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const C4E1_ZOOMS: Array[float] = [1.0, 1.5, 2.0]
const CENTER := Vector2i(32, -28672)

var diagnostic_records: Array[Dictionary] = []
var streaming_revisit_pixel_exact: bool = false


class DiagnosticOverlay extends Node2D:
	var authoritative_path := PackedVector2Array()
	var raw_paths: Array[PackedVector2Array] = []
	var triangles: Array[PackedVector2Array] = []
	var labels: Array[Dictionary] = []
	var chunk_x: float = 0.0
	var chunk_y: float = 0.0
	var vertical_range := Vector2.ZERO

	func _draw() -> void:
		for triangle in triangles:
			draw_polyline(triangle, Color(1.0, 0.2, 0.85, 0.52), 1.0)
		if authoritative_path.size() > 1:
			draw_polyline(authoritative_path, Color(1.0, 0.18, 0.12, 0.95), 3.0)
		for path in raw_paths:
			draw_polyline(path, Color(0.1, 0.95, 1.0, 0.95), 2.0)
			draw_circle(path[0], 3.0, Color(1.0, 0.9, 0.05, 1.0))
			draw_circle(path[path.size() - 1], 3.0, Color(1.0, 0.9, 0.05, 1.0))
		draw_line(
			Vector2(chunk_x, vertical_range.x), Vector2(chunk_x, vertical_range.y),
			Color(0.2, 1.0, 0.25, 0.9), 3.0)
		draw_line(
			Vector2(chunk_x - 22.0 * 32.0, chunk_y),
			Vector2(chunk_x + 22.0 * 32.0, chunk_y),
			Color(0.2, 1.0, 0.25, 0.9), 3.0)
		for label in labels:
			draw_string(
				ThemeDB.fallback_font, label.position + Vector2(4, -4),
				String.num_int64(label.id), HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 11, Color.WHITE)


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["before", "after"]:
		push_error("Phase C4E.1 capture requires user argument: before or after")
		quit(1)
		return
	capture_label = String(arguments[0])
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
	terrain.set_cliff_height_profile(2)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_disconnected_diagonal_fixture()
	terrain._invalidate_streamed_chunks()
	_collect_diagnostics()
	for zoom in C4E1_ZOOMS:
		await _move_camera(CENTER, zoom)
		var zoom_label := _c4e1_zoom_label(zoom)
		var file_name := "c4e1_%s_bent_diagonal_%s.png" % [capture_label, zoom_label]
		await _save(file_name)
		captures.append({"path": "%s/%s" % [OUTPUT_DIR, file_name], "zoom": zoom})
		if capture_label == "after":
			_save_comparison(zoom_label, file_name)
	if capture_label == "after":
		streaming_revisit_pixel_exact = await _verify_streaming_revisit()
	await _capture_diagnostic_overlay()
	_write_diagnostics()
	print("PHASE_C4E1_CAPTURE: PASS label=%s captures=%d candidates=%d" % [
		capture_label, captures.size(), diagnostic_records.size()])
	quit(0)


func _build_disconnected_diagonal_fixture() -> void:
	_fill(CENTER - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-17, 18):
		var edge: int = _fixture_edge(y)
		for x in range(-28, edge + 1):
			_set_cell(CENTER + Vector2i(x, y), 3, 2)


func _fixture_edge(y: int) -> int:
	if y < -11:
		return y - 5
	if y < -7:
		return -16
	if y < -2:
		return y - 8
	if y < 2:
		return -10
	if y < 7:
		return y - 12
	if y < 11:
		return -5
	return y - 16


func _collect_diagnostics() -> void:
	var first := CENTER + Vector2i(-30, -19)
	var last := CENTER + Vector2i(30, 19)
	var segment_id: int = 0
	for world_y in range(first.y, last.y + 1):
		for world_x in range(first.x, last.x + 1):
			var world_cell := Vector2i(world_x, world_y)
			var chunk := Vector2i(
				floori(float(world_x) / 32.0), floori(float(world_y) / 32.0))
			var local := world_cell - chunk * 32
			var heights := PackedInt32Array([
				terrain.get_world_elevation(world_cell - Vector2i.ONE),
				terrain.get_world_elevation(world_cell + Vector2i(0, -1)),
				terrain.get_world_elevation(world_cell + Vector2i(-1, 0)),
				terrain.get_world_elevation(world_cell),
			])
			for level in range(1, 3):
				var mask: int = 0
				for corner in range(4):
					if heights[corner] >= level:
						mask |= 8 >> corner
				if mask == 0 or mask == 15:
					continue
				for segment in OrganicCliffMeshBuilder._unified_contour_segments(
						mask, world_cell, level, terrain.world_seed):
					var path: PackedVector2Array = OrganicCliffMeshBuilder._unified_contour_path(
						segment, mask, local.x, local.y, world_cell, level,
						terrain.world_seed, terrain.get_cliff_height_step())
					for point_index in range(path.size()):
						path[point_index] += Vector2(chunk * 32 * 32)
					var first_delta: Vector2 = path[1] - path[0]
					var second_delta: Vector2 = path[2] - path[1]
					var path_delta: Vector2 = path[2] - path[0]
					if (absf(path_delta.y) > absf(path_delta.x)
							and absf(path_delta.x) <= 5.0):
						diagnostic_records.append({
							"segment_id": segment_id,
							"world_cell": [world_cell.x, world_cell.y],
							"level": level,
							"mask": mask,
							"path": _path_to_arrays(path),
							"first_delta": [first_delta.x, first_delta.y],
							"second_delta": [second_delta.x, second_delta.y],
						})
					segment_id += 1


func _path_to_arrays(path: PackedVector2Array) -> Array:
	var result: Array = []
	for point in path:
		result.append([point.x, point.y])
	return result


func _verify_streaming_revisit() -> bool:
	var reference: Image = Image.load_from_file(
		"%s/c4e1_after_bent_diagonal_1_5x.png" % OUTPUT_DIR)
	await _move_camera(CENTER + Vector2i(160, 96), 1.5)
	await _move_camera(CENTER, 1.5)
	var revisit: Image = root.get_texture().get_image()
	var matches: bool = hash(reference.get_data()) == hash(revisit.get_data())
	assert(matches, "C4E.1 output changed after streaming away and revisiting")
	return matches


func _capture_diagnostic_overlay() -> void:
	await _move_camera(CENTER, 1.5)
	var overlay := DiagnosticOverlay.new()
	overlay.z_index = 4096
	overlay.chunk_x = float(CENTER.x * 32)
	overlay.chunk_y = float(CENTER.y * 32)
	overlay.vertical_range = Vector2(
		float((CENTER.y - 20) * 32), float((CENTER.y + 20) * 32))
	for y in range(-17, 18):
		overlay.authoritative_path.append(Vector2(
			float(CENTER.x + _fixture_edge(y)) * 32.0,
			float(CENTER.y + y) * 32.0 - 64.0))
	for record in diagnostic_records:
		var cell: Array = record.world_cell
		if (int(record.level) != 2
				or abs(int(cell[0]) - CENTER.x) > 20
				or abs(int(cell[1]) - CENTER.y) > 18):
			continue
		var path := PackedVector2Array()
		for point in record.path:
			path.append(Vector2(float(point[0]), float(point[1])))
		overlay.raw_paths.append(path)
		if int(record.segment_id) % 8 == 0:
			overlay.labels.append({
				"id": int(record.segment_id),
				"position": path[1],
			})
	_collect_mesh_triangles(overlay)
	demo.add_child(overlay)
	await _wait_frames(3)
	await _save("c4e1_%s_diagnostic_overlay_1_5x.png" % capture_label)
	overlay.queue_free()
	await _wait_frames(2)


func _collect_mesh_triangles(overlay: DiagnosticOverlay) -> void:
	var material_lookup := func(pos: Vector2i) -> int:
		return terrain.get_world_visible_cell(pos)
	var height_lookup := func(pos: Vector2i) -> int:
		return terrain.get_world_elevation(pos)
	for chunk_y in [-897, -896]:
		for chunk_x in [0, 1]:
			var chunk := Vector2i(chunk_x, chunk_y)
			var result: Dictionary = OrganicCliffMeshBuilder.build(
				chunk, 3, terrain.world_seed, material_lookup, height_lookup,
				terrain.liquid_by_id, true, true, true, true,
				terrain.get_cliff_height_step(), true)
			var chunk_offset := Vector2(chunk * 32 * 32)
			for mesh in result.meshes:
				if mesh == null:
					continue
				var arrays: Array = mesh.surface_get_arrays(0)
				var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for index in range(0, indices.size(), 3):
					var triangle := PackedVector2Array([
						vertices[indices[index]] + chunk_offset,
						vertices[indices[index + 1]] + chunk_offset,
						vertices[indices[index + 2]] + chunk_offset,
						vertices[indices[index]] + chunk_offset,
					])
					var center: Vector2 = (triangle[0] + triangle[1] + triangle[2]) / 3.0
					if (absf(center.x - float(CENTER.x * 32)) <= 22.0 * 32.0
							and absf(center.y - float(CENTER.y * 32)) <= 20.0 * 32.0):
						overlay.triangles.append(triangle)


func _save_comparison(zoom_label: String, after_name: String) -> void:
	var before: Image = Image.load_from_file(
		"%s/c4e1_before_bent_diagonal_%s.png" % [OUTPUT_DIR, zoom_label])
	var after: Image = Image.load_from_file("%s/%s" % [OUTPUT_DIR, after_name])
	assert(before != null and after != null, "Matched C4E.1 captures must exist")
	var combined := Image.create(
		before.get_width() * 2, before.get_height(), false, before.get_format())
	combined.blit_rect(before, before.get_used_rect(), Vector2i.ZERO)
	combined.blit_rect(after, after.get_used_rect(), Vector2i(before.get_width(), 0))
	assert(combined.save_png(
		"%s/c4e1_compare_bent_diagonal_%s.png" % [OUTPUT_DIR, zoom_label]) == OK)


func _write_diagnostics() -> void:
	var path := "%s/c4e1_%s_contour_diagnostics.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not write C4E.1 diagnostics")
	file.store_string(JSON.stringify({
		"phase": "C4E.1",
		"capture_label": capture_label,
		"seed": terrain.world_seed,
		"fixture_center": [CENTER.x, CENTER.y],
		"chunk_boundary_x": 32,
		"near_vertical_segments": diagnostic_records,
		"captures": captures,
		"streaming_revisit_pixel_exact": streaming_revisit_pixel_exact,
	}, "\t"))
	file.close()


func _c4e1_zoom_label(zoom: float) -> String:
	return String.num(zoom, 1).replace(".", "_") + "x"
