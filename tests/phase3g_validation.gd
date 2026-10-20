extends "res://tests/phase3f_validation.gd"
## Structural checks do not certify visual mask/contour correspondence.
## All generated wall coverage remains present; visibility is depth ordering.


func _run() -> void:
	_test_directional_classification()
	_test_coverage_and_regeneration()
	_test_deterministic_mixed_height_and_seams()
	await _test_toggle_and_editor_projection()
	if failures.is_empty():
		print("PHASE3G_VALIDATION: PASS (structural; visual acceptance separate)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_directional_classification() -> void:
	var south: float = OrganicCliffMeshBuilder._directional_face_shade(Vector2.LEFT)
	var north: float = OrganicCliffMeshBuilder._directional_face_shade(Vector2.RIGHT)
	var east: float = OrganicCliffMeshBuilder._directional_face_shade(Vector2.DOWN)
	var west: float = OrganicCliffMeshBuilder._directional_face_shade(Vector2.UP)
	_expect(south > east and south > west and south > north, "Front faces receive strongest illumination")
	_expect(east != west, "Side illumination distinguishes east and west")
	var diagonal: float = OrganicCliffMeshBuilder._directional_face_shade(Vector2(-1, 1))
	_expect(diagonal > east and diagonal < south, "Diagonal shade interpolates continuously")


func _test_coverage_and_regeneration() -> void:
	var height_lookup := func(pos: Vector2i) -> int:
		return 1 + posmod(floori(float(pos.y) / 6), 3) if pos.x < pos.y else 0
	var material_lookup := func(_pos: Vector2i) -> int: return 3
	for coord in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0)]:
		var baseline := OrganicCliffMeshBuilder.build(
			coord, 3, 84521, material_lookup, height_lookup,
			{0: true}, true, true, true, true, 32, false)
		var directional := OrganicCliffMeshBuilder.build(
			coord, 3, 84521, material_lookup, height_lookup,
			{0: true}, true, true, true, true, 32, true)
		var regenerated := OrganicCliffMeshBuilder.build(
			coord, 3, 84521, material_lookup, height_lookup,
			{0: true}, true, true, true, true, 32, true)
		_expect(_geometry_signature(directional) == _geometry_signature(regenerated),
			"Directional mixed-height regeneration is deterministic")
		for key in ["meshes", "edge_meshes", "shadow_meshes"]:
			for index in range(baseline[key].size()):
				var before = baseline[key][index]
				var after = directional[key][index]
				if before == null:
					_expect(after == null, "No spurious directional component")
					continue
				var a: Array = before.surface_get_arrays(0)
				var b: Array = after.surface_get_arrays(0)
				_expect(a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX],
					"Complete coverage, crest/toe and seam coordinates retained")
				_expect(a[Mesh.ARRAY_INDEX] == b[Mesh.ARRAY_INDEX],
					"Directional mode introduces no inverted or missing triangles")
				for color in b[Mesh.ARRAY_COLOR]:
					_expect(color.a > 0.0, "No transparent face removal")
	# Material transitions at equal heights must not manufacture cliffs.
	var flat := OrganicCliffMeshBuilder.build(Vector2i.ZERO, 3, 84521,
		func(pos: Vector2i) -> int: return 0 if pos.x < 16 else 1,
		func(_pos: Vector2i) -> int: return 0,
		{0: true}, true, true, true, true, 32, true)
	_expect(flat.face_count == 0, "Equal-height water/sand has no cliff")


func _test_toggle_and_editor_projection() -> void:
	var terrain = TerrainRenderer.new()
	terrain.organic_cliff_geometry_enabled = true
	terrain.unified_cliff_contours_enabled = true
	terrain.cliff_height_profile = 2
	root.add_child(terrain)
	await process_frame
	var edits: Array[Dictionary] = []
	for y in range(-3, 4):
		for x in range(-3, 4):
			edits.append({"cell": Vector2i(x, y), "kind": "elevation",
				"state": {"has_override": true, "value": 3}})
	terrain.apply_world_edit_states(edits)
	terrain.update_visible_world_rect(Rect2(Vector2(-320, -320), Vector2(640, 640)))
	await _wait_until_idle(terrain)
	var rect: Rect2 = terrain.get_projected_cell_rect(Vector2i.ZERO)
	var polygon: PackedVector2Array = terrain.get_projected_cell_polygon(Vector2i.ZERO)
	for enabled in [true, false, true, false]:
		terrain.set_directional_cliff_projection_enabled(enabled)
		await _wait_until_idle(terrain)
		_expect(terrain.get_projected_cell_rect(Vector2i.ZERO) == rect, "Toggle preserves projection")
		_expect(terrain.get_projected_cell_polygon(Vector2i.ZERO) == polygon, "Brush polygon unchanged")
		var pick: Dictionary = terrain.pick_world_position(rect.get_center())
		_expect(pick.cell == Vector2i.ZERO and pick.elevation == 3, "Picking remains aligned")
		for chunk in terrain.loaded_chunks.values():
			_expect(chunk._organic_face_z_offset() == (-1 if enabled else 3),
				"Runtime toggle and rollback restore face depth")
		_expect(terrain.get_world_elevation(Vector2i.ZERO) == 3, "Authority unchanged")
		if enabled:
			terrain.set_world_elevation(Vector2i.ZERO, 2)
			await _wait_until_idle(terrain)
			var edited_rect: Rect2 = terrain.get_projected_cell_rect(Vector2i.ZERO)
			_expect(edited_rect.position.y == rect.position.y + 32,
				"Brush elevation edit updates projection by the selected height step")
			terrain.set_world_elevation(Vector2i.ZERO, 3)
			await _wait_until_idle(terrain)
			_expect(terrain.get_projected_cell_polygon(Vector2i.ZERO) == polygon,
				"Restoring brush elevation restores its projected polygon")
	terrain.queue_free()
